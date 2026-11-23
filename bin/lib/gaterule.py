"""一個 gate 要通知人、停 pane 等別張卡、交協調者 session 代跑，還是由協調者照建議答；協調者與 collect 共用。
只看 waiting，不看 repo、不讀檔、不跑指令、不通知。每個 repo 有建議的 decision 都由協調者照建議答；
approval、第三級、花錢、對外、合併與要人動手的題由使用者答。代跑是照建議跑一次指令、把結果貼回，不是替人做決定。

decide(waiting) 回傳四種處置之一：
  ("human", reason)        留給人；reason 是理由代碼，文字由呼叫端對照
  ("park", waits_on)       等 waits_on 那張卡合進 main
  ("coordinator", "run")   needs: run 且 by: coordinator，協調者 session 照建議跑
  ("answer", pick)         協調者照建議答；pick 是建議，沒有建議的題留給人
"""
import re

# 建議裡有這些字，代表要人動手
HUMAN_WORDS = ("你", "使用者", "沙盒外", "自己跑", "本人", "人工", "跑指令", "跑腳本", "錄", "貼路徑")
HUMAN_QUESTION = ("只有你能做", "誰來跑")
# 協調者會照抄建議去跑，git merge origin/main 這類指令也不能交給它，所以代跑檢查刻意用寬的字詞比對
MERGE_WORDS = ("合併", "merge")
# 只認 MR 語境的合併：合併兩個 helper、git merge origin/main、合併卡片都不算。中文前後不能用 \b，因為 Python 把中文當成 \w
MR_MERGE = re.compile(
    r"mr-merge|merge[ _-]request|(merge|合併) ?api(?![a-z])"
    r"|(合併|merge) ?((mr|pr)s?|![0-9]+)(?![a-z0-9])|(?<![a-z])((mr|pr)s?|![0-9]+) ?(合併|merge)"
    r"|合進 ?main(?![a-z])|merge (into|to) main(?![a-z])|按合併|合 ?[!#][0-9]",
    re.IGNORECASE)
# 白名單沒寫到的說法改看兩個訊號：同時有合併字眼與 MR 錨點才算。origin/main 是本地同步，不算錨點
MERGE_WORD = re.compile(r"合併|merge", re.IGNORECASE)
MR_ANCHOR = re.compile(
    r"(?<![a-z])(mr|pr)s?(?![a-z])|merge[ _-]request|pull[ _-]request|[!#][0-9]+|(?<!origin/)(?<![a-z])(main|master)(?![a-z])",
    re.IGNORECASE)
# 合併字旁邊有授權字（要授權合併嗎、Ready to merge?）是在問要不要合併，沒有 MR 錨點也交人
MERGE_AUTH = re.compile(r"授權|允許|可以|同意|批准|(?<![a-z])(ready|now|should)(?![a-z])", re.IGNORECASE)
# 第三級動作（部署、動 prod、強推、刪資料、打 tag、改 CI、secrets）、花錢與對外發話。單獨的 CI 不算：「等 CI 綠」是操作題，不是改 CI。
# 英文字詞只有右字界，不比中更長的英文字（secretary、process.env、動 circuit），但 camelCase 的 clientSecret、redeploy 照比中
LEVEL3 = re.compile(
    r"deploy|部署"
    r"|force-push|push --force|push -f|強推|drop table|(?<![a-z])truncate(?![a-z])|刪資料|刪除資料"
    r"|drop (column|database|schema)|delete from|rm -rf|reset --hard|刪除?(欄位|表|分支)|git tag|打 ?tag|push --tags"
    r"|(?<![a-z0-9])prod(uction)?(?![a-z0-9])"
    r"|\.gitlab-ci|\.github/workflows|[改動] ?ci(?![a-z])|(?<![a-z])ci ?[設檔]"
    r"|secrets?(?![a-z])|(?<![a-z])sops(?![a-z])|(?<![a-z0-9_])\.env(?![a-z])|金鑰|憑證|api key|credentials?(?![a-z])"
    r"|花錢|付費|費用|購買|訂閱|(?<![a-z])billing(?![a-z])|對外|對客戶|發信|寄信|send email|發公告|issue 留言|issue comment",
    re.IGNORECASE)
# 建議開頭的選項代號（「A」「選 A（最快）」「建議選 b」「選 1。理由」），它指向的選項全文也要比 LEVEL3
CHOICE = re.compile(r"\s*(?:建議)?\s*(?:選項?)?\s*[(（]?([A-Za-z0-9]+)(?![A-Za-z0-9])")
# 邏輯表 ⚠ gate 的建議「1A 2B」是逐項選擇；ITEM 是 waiting.items 裡一項的題號
ITEM_PICK = re.compile(r"([0-9]+)\s*([A-Za-z])(?![A-Za-z0-9])")
ITEM = re.compile(r"\s*([0-9]+)\s")
# 同一張卡第 3 個產表失敗 gate 起交人：連續失敗多半不是重跑能解
LOGIC_MAP_FAILED = re.compile(r"logic-map-failed-([0-9]+)")
LOGIC_MAP_FAILED_LIMIT = 3
# explore 寫的拆法確認 gate 的 id
SPLIT_GATE = "split"
# drive、Stop hook 卡住與協調者等背景工作太久時寫的 gate 標題（drive-<站>-<n>、卡在接 /<站> [#<n>]、stale-wait-<時間>）：
# 建議欄是給人看的提示，不是答案
STUCK_GATE = re.compile(r"drive-[a-z]+-[0-9]+|卡在接 /[a-z]+( #[0-9]+)?|stale-wait-[0-9]+")


def is_mr_merge(text):
    return bool(MR_MERGE.search(text) or (MERGE_WORD.search(text) and MR_ANCHOR.search(text)))


def chosen_option(recommended, options):
    """建議開頭是選項代號時，回以那個代號開頭的選項全文；建議開頭不是代號，或沒有選項用那個代號開頭，回空字串。"""
    m = CHOICE.match(recommended)
    if m is None:
        return ""
    label = re.compile(r"\s*(?:選項\s*)?[(（]?" + re.escape(m.group(1)) + r"(?![A-Za-z0-9])", re.IGNORECASE)
    return next((o for o in options if label.match(o)), "")


def item_choices(recommended, items):
    """逐項建議（「1A 2B」）在 items 裡選中的每個選項文字，用空格接起來。items 一項一行，
    形如「1 D3 欄位：A 直接 DROP COLUMN (Recommended) | B 保留」：以 | 分段，每段取最後一個冒號之後，看它開頭的代號。"""
    by_number = {}
    for line in items:
        m = ITEM.match(line)
        if m:
            by_number[m.group(1)] = line
    picked = []
    for number, label in ITEM_PICK.findall(recommended):
        segments = [re.split(r"[：:]", s)[-1].strip() for s in by_number.get(number, "").split("|")]
        option = re.compile(r"[(（]?" + re.escape(label) + r"(?![A-Za-z0-9])", re.IGNORECASE)
        picked += [s for s in segments if option.match(s)]
    return " ".join(picked)


def decide(w):
    if w["gate_id"] and STUCK_GATE.fullmatch(w["gate_id"]):
        return ("human", "stuck")
    failed = LOGIC_MAP_FAILED.fullmatch(w["gate_id"] or "")
    if failed and int(failed.group(1)) >= LOGIC_MAP_FAILED_LIMIT:
        return ("human", "stuck")
    # 排在 type 前：approval 型的 push 題也交協調者，使用者在協調者 pane 按權限提示。
    # 合併類、等別張卡、type 不明、split 不交，往下照原規則
    merge_text = ((w.get("action") or "") + " " + (w.get("question") or "")).lower()
    # 協調者跑的就是建議欄，所以這裡連建議也比
    run_text = merge_text + " " + (w.get("recommended") or "").lower()
    if (w.get("needs") == "run" and w.get("by") == "coordinator" and not w.get("waits_on")
            and w["type"] != "type 不明" and w["gate_id"] != SPLIT_GATE
            and not any(k in run_text for k in MERGE_WORDS)):
        return ("coordinator", "run")
    if w.get("needs") == "run":
        return ("human", "run")
    if w["type"] == "等待授權":
        # 合併永遠由人按：action 不一定剛好寫成 merge（mr-merge、external 打合併 API），題目也要看
        if (w.get("action") or "").lower() == "merge" or is_mr_merge(merge_text):
            return ("human", "merge-grant")
        return ("human", "approval")
    if w["type"] == "終端機等待輸入":
        return ("human", "terminal")
    if w["type"] == "type 不明":
        return ("human", "type")
    q = w.get("question") or ""
    pick = w.get("recommended") or (w.get("options") or [None])[0]
    # gate 明寫 waits-on 才算等別張卡。要排在合併類規則前，不然會被它吃掉
    if w.get("waits_on"):
        return ("park", w["waits_on"])
    decision_text = q + " " + (pick or "")
    if is_mr_merge(decision_text) or (MERGE_WORD.search(decision_text) and MERGE_AUTH.search(decision_text)):
        return ("human", "merge")
    rec = w.get("recommended") or ""
    if LEVEL3.search(" ".join((q, rec, chosen_option(rec, w.get("options") or []), item_choices(rec, w.get("items") or [])))):
        return ("human", "level3")
    if not pick:
        return ("human", "no-pick")
    if any(k in (w.get("recommended") or "") for k in HUMAN_WORDS) or any(k in q for k in HUMAN_QUESTION):
        return ("human", "hands")
    return ("answer", pick) if w.get("recommended") else ("human", "no-rec")
