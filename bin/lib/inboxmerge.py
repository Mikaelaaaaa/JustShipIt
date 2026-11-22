"""目標卡 inbox.md 的 `## 併入：<時間> <來源>` 段：opsx new 追加、opsx split-out 拆回獨立的卡。

用法：
    $OPSX_PY -I inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <evidence> <type> <一句話>
        追加一段，印這段拿到的 id。id 是新卡原本會拿到的 slug；目標裡已經有同一個 id 時依序加 -2、-3。
        鎖內發現目標已有 tasks.md 或已拆就不寫，退出 4。
    $OPSX_PY -I inboxmerge.py card <卡目錄> <id>
        印那一段拆回獨立卡時的 inbox.md（一行形狀跟 opsx new 寫的同形，縮排形狀還原來源整份內文）。找不到退出 2。
    $OPSX_PY -I inboxmerge.py remove <卡目錄> <id>
        刪掉那一段，其餘位元組不動。找不到退出 2。
    $OPSX_PY -I inboxmerge.py ids <卡目錄>
        一行印一個這張卡現有的併入 id（opsx drop 用來拒絕還有併入項目的卡）。
    $OPSX_PY -I inboxmerge.py split-out <卡目錄> <id> <repo 根>
        同一個卡鎖內讀那一段、算好拆掉後的目標全文（照 `- carried:` 撤回目標 frontmatter、用其餘帶 frontmatter 的段照 carry 規則重併、
        刪「- 併進」證據行、刪那一段）、用 common.sh 的 new_shell 建殼、一次寫回目標；印新殼 slug。
        找不到那段退出 2；段或 `- carried:` 格式不對退出 1；兩者都不建殼。
    $OPSX_PY -I inboxmerge.py evidence <卡目錄> <行>
        卡鎖內把一行插進 `## 證據` 段最後一行非空內容之後（opsx merge-card）。沒有證據段退出 1。
    $OPSX_PY -I inboxmerge.py carry <目標卡目錄> <來源 inbox 檔> <來源 slug> <併入段 id>
        來源卡的 kind_of_work / impact / evidence / priority 覆寫併進目標卡 frontmatter（opsx merge-card，來源捨棄成功之後；來源 inbox 已複製出來）：
        kind_of_work 取較高，impact 取聯集，evidence 依 " ; " 去重接在後面，priority 取較高。改了什麼以 `- carried:` 記進那段併入。
    $OPSX_PY -I inboxmerge.py carry-check <目標卡目錄> <來源 inbox 檔> <來源 slug>
        同上但不寫檔：只驗欄位合格與目標有 frontmatter（opsx merge-card，捨棄來源之前）。
    $OPSX_PY -I inboxmerge.py summary-check <來源 inbox 檔> <來源 slug>
        來源內文沒有 `## 一句話` 或那段沒有非空行就退出 1（opsx merge-card，捨棄來源之前；這樣的段拆不回來）。
    $OPSX_PY -I inboxmerge.py drop <卡目錄> <理由> -- <歸檔指令…>
        卡鎖內重查併入段（有就退出 1）、寫 outcome: declined 與 ## 捨棄理由、跑歸檔指令，鎖到指令結束才放。指令失敗退出 3。
兩個 agent 可能同時併進同一張卡：鎖在卡目錄上（inbox.md 會被原子替換換掉 inode，鎖它本身擋不住），鎖內重讀再改。
一段併入從標題到下一個 `## ` 或檔尾為止。specs/card-auto-merge「同檔案併入」「拆出來」。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import priority  # noqa: E402
import safefile  # noqa: E402

HEAD = re.compile(r"^## ")
FRONTMATTER = re.compile(r"\A---\n(.*?\n)---\n", re.S)
MERGED = re.compile(r"^## 併入：")
MERGED_HEAD = re.compile(r"^## 併入：(\S+) (\S+)\s*$")
ID_LINE = re.compile(r"^- id: (\S+)\s*$")
FIELD = re.compile(r"^- (id|kind_of_work|evidence|type|area|carried): (.*)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}")
INDENT = "  "
SUMMARY_HEAD = re.compile(r"^## 一句話\s*$")   # 跟 collect.sh 讀一般卡一句話的規則一樣容許尾端空白
ATTACH_HEAD = re.compile(r"^## 附件\s*$")
# 跟 str.splitlines(keepends=True) 一樣保留行尾，但只認 \n：U+2028、U+0085、\x0c 是行內字元，寫入端照收
LINE = re.compile(r"[^\n]*\n|[^\n]+\Z")
PRIORITY_KEYS = ("priority", "priority_reason", "priority_auto")
CARRIED_KEYS = ("kind_of_work",) + PRIORITY_KEYS


SPLIT_INTO = re.compile(r"^split_into:\s*(.*?)\s*(#.*)?$")
SPLIT_EMPTY = re.compile(r"^(\[ *\]|\"\"|''|~|null)?$")


class SectionNotFound(LookupError):
    pass


class TargetStarted(Exception):
    """併入目標在 opsx new 判斷之後已開工（有 tasks.md）或已拆：這段不寫，opsx new 改建殼。"""


def split_into(text: str) -> str:
    """frontmatter 的 split_into 值，空值算沒有；判斷跟 stage.sh 的 st_split_into 一致。"""
    lines = text.split("\n")
    if not lines or not lines[0].startswith("---"):
        return ""
    for line in lines[1:]:
        if line.startswith("---"):
            return ""
        m = SPLIT_INTO.match(line.rstrip("\r"))
        if m:
            return "" if SPLIT_EMPTY.match(m.group(1)) else m.group(1)
    return ""


def merged_ids(text: str) -> set:
    ids, inside = set(), False
    for line in text.split("\n"):
        if HEAD.match(line):
            inside = bool(MERGED.match(line))
            continue
        m = ID_LINE.match(line) if inside else None
        if m:
            ids.add(m.group(1))
    return ids


def free_id(base: str, taken: set) -> str:
    if base not in taken:
        return base
    n = 2
    while "%s-%d" % (base, n) in taken:
        n += 1
    return "%s-%d" % (base, n)


def section(mid: str, when: str, source: str, kind: str, evidence: str, kind_type: str, text: str) -> str:
    lines = ["## 併入：%s %s" % (when, source), "", "- id: " + mid, "- kind_of_work: " + kind]
    if evidence:
        lines.append("- evidence: " + evidence)
    lines += ["- type: " + kind_type, "", text, ""]
    return "\n".join(lines)


def ensure_open(card_dir: str, inbox_text: str) -> None:
    """目標卡還能收併入：沒有 tasks.md、沒有拆。"""
    if os.path.exists(os.path.join(card_dir, "tasks.md")):
        raise TargetStarted("%s 已有 tasks.md，不併" % card_dir)
    if split_into(inbox_text):
        raise TargetStarted("%s 已拆（split_into: %s），不併" % (card_dir, split_into(inbox_text)))


def open_check(card_dir: str) -> None:
    """opsx merge-card 在捨棄來源之前先問：目標還收不收。"""
    with open(os.path.join(card_dir, "inbox.md"), encoding="utf-8") as f:
        ensure_open(card_dir, f.read())


def append(card_dir: str, base: str, when: str, source: str, kind: str, evidence: str, kind_type: str, text: str) -> str:
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            cur = f.read()
        # opsx new 在鎖外判斷階段，這裡鎖內再查一次，免得併進剛開工或剛拆的卡。
        # tasks.md 由 agent 用 Write 寫，取不到這把鎖；晚到的併入由 Stop hook 的 check_merged 補查（hooks/openspec-stop-gate.sh）
        ensure_open(card_dir, cur)
        mid = free_id(base, merged_ids(cur))
        if cur and not cur.endswith("\n"):
            cur += "\n"
        if cur and not cur.endswith("\n\n"):
            cur += "\n"
        safefile.write_atomic(inbox, cur + section(mid, when, source, kind, evidence, kind_type, text))
    return mid


def append_full(card_dir: str, source_inbox: str, source_slug: str, when: str) -> str:
    """來源卡整份 inbox（frontmatter、一句話、證據）以 ## 併入： 段併進目標；每行縮排兩格，標題與欄位樣式的行就切不斷這一段、也不會多出假 id。
    frontmatter 一起存，拆回時 impact、priority 這些欄位不會掉。"""
    with open(source_inbox, encoding="utf-8") as f:
        text = f.read()
    fm, _ = priority.frontmatter(text)
    got = facts(source_slug, text)
    indented = "\n".join(("  " + x) if x else x for x in text.strip("\n").split("\n"))
    return append(card_dir, source_slug, when, fm.get("source") or "me", got["kind"], got["evidence"], fm.get("type") or "待定", indented)


def find(text: str, mid: str) -> tuple:
    """含 `- id: <mid>` 的併入段，回傳 (起始行, 結束行之後)，行號以 LINE 切行計。"""
    lines = LINE.findall(text)
    heads = [i for i, x in enumerate(lines) if HEAD.match(x)] + [len(lines)]
    hits = [(a, b) for a, b in zip(heads, heads[1:]) if MERGED.match(lines[a]) and mid in merged_ids("".join(lines[a:b]))]
    if not hits:
        raise SectionNotFound("找不到含 `- id: %s` 的 `## 併入：` 段" % mid)
    if len(hits) > 1:
        raise ValueError("有 %d 段併入的 id 都是 %s，分不出要拆哪一段" % (len(hits), mid))
    return hits[0]


def unindent(rest: list, mid: str) -> str:
    """append_full 寫的內文（每個非空行縮排兩格）還原成來源 inbox 內文；段尾空行不算。"""
    while rest and rest[-1] == "":
        rest = rest[:-1]
    for x in rest:
        if x and not x.startswith(INDENT):
            raise ValueError("縮排的併入段有一行沒縮排兩格（id %s）：%s" % (mid, x))
    return "\n".join(x[len(INDENT):] for x in rest)


def summary(body: str, mid: str) -> str:
    """還原內文裡 `## 一句話` 段的第一個非空行，給看板那一列用；跟 collect.sh 的 one_liner 取法一樣。"""
    lines = body.split("\n")
    head = next((i for i, x in enumerate(lines) if SUMMARY_HEAD.match(x)), None)
    if head is None:
        raise ValueError("縮排的併入段沒有 ## 一句話（id %s）" % mid)
    for x in lines[head + 1:]:
        if HEAD.match(x):
            break
        if x.strip():
            return x.strip()
    raise ValueError("縮排的併入段 ## 一句話 是空的（id %s）" % mid)


def summary_check(source_inbox: str, source_slug: str) -> None:
    """opsx merge-card 捨棄來源之前先驗：來源內文（去掉 frontmatter）有拆得回來的 `## 一句話`，規則跟讀縮排段的 summary 一樣。"""
    with open(source_inbox, encoding="utf-8") as f:
        summary(FRONTMATTER.sub("", f.read(), count=1), source_slug)


def parse(block: list) -> dict:
    """一段併入的行（不含換行）拆成欄位；形狀不對就 raise 指出哪一行。
    欄位後空行接的第一行縮排兩格是 append_full 寫的縮排形狀（多回一個 body：還原的來源內文），否則是 section 寫的一行形狀。"""
    m = MERGED_HEAD.match(block[0])
    if not m:
        raise ValueError("併入段標題不是「## 併入：<時間> <來源>」：%s" % block[0])
    if not DATE.match(m.group(1)):
        raise ValueError("併入段標題的時間不是 ISO 日期開頭：%s" % m.group(1))
    out = {"when": m.group(1), "source": m.group(2)}
    if len(block) < 2 or block[1] != "":
        raise ValueError("併入段標題後要空一行：%s" % block[0])
    i = 2
    while i < len(block) and block[i] != "":
        f = FIELD.match(block[i])
        if not f:
            raise ValueError("併入段的欄位行看不懂：%s" % block[i])
        out[f.group(1)] = f.group(2)
        i += 1
    for key in ("id", "kind_of_work"):
        if key not in out:
            raise ValueError("併入段少了 - %s:（標題 %s）" % (key, block[0]))
    # 新段寫 - type:，舊段（自動併入看 area 的時期）寫 - area:
    if "type" not in out and "area" not in out:
        raise ValueError("併入段要有 - type: 或 - area:（標題 %s）" % block[0])
    rest = block[i + 1:]
    if rest and rest[0].startswith(INDENT):
        out["body"] = unindent(rest, out["id"])
        out["text"] = summary(out["body"], out["id"])
        return out
    if not rest or rest[0] == "" or any(x != "" for x in rest[1:]):
        raise ValueError("併入段欄位後要是空行加一行一句話（id %s）" % out["id"])
    out["text"] = rest[0]
    return out


def sections(text: str) -> list:
    """每段 `## 併入：` 依檔案順序回 (標題行, parse 的結果或它丟的 ValueError)；看板列項目、報格式錯誤用。"""
    lines = [x.rstrip("\n") for x in LINE.findall(text)]
    heads = [i for i, x in enumerate(lines) if HEAD.match(x)] + [len(lines)]
    out = []
    for a, b in zip(heads, heads[1:]):
        if not MERGED.match(lines[a]):
            continue
        try:
            got = parse(lines[a:b])
            got.pop("body", None)   # 看板只列一句話；一行形狀沒有 body
            got.pop("carried", None)   # 只給 split-out 撤回用；一行形狀與舊段沒有
            out.append((lines[a], got))
        except ValueError as e:
            out.append((lines[a], e))
    return out


def card_body(fields: dict) -> str:
    # merge-card 連 frontmatter 存的段原樣拆回；之前寫的縮排段沒有 frontmatter，由欄位重建
    if "body" in fields and fields["body"].startswith("---"):
        return fields["body"] + "\n"
    kind_type = fields["type"] if "type" in fields else "待定"   # 舊段沒有 type
    lines = ["---", "type: " + kind_type, "source: " + fields["source"], "found: " + fields["when"][:10], "related:", "kind_of_work: " + fields["kind_of_work"]]
    if "evidence" in fields:
        lines.append("evidence: " + fields["evidence"])
    if "body" in fields:
        return "\n".join(lines + ["---", "", fields["body"], ""])
    lines += ["---", "", "## 一句話", "", fields["text"], "", "## 證據", "", ""]
    return "\n".join(lines)


def _card_unlocked(card_dir: str, mid: str) -> str:
    with open(os.path.join(card_dir, "inbox.md"), encoding="utf-8") as f:
        cur = f.read()
    start, end = find(cur, mid)
    fields = parse([x.rstrip("\n") for x in LINE.findall(cur)[start:end]])
    # 附件跟來源卡一起歸檔了，新殼帶不回來；拆出來連結會斷，所以不拆
    if "body" in fields and any(ATTACH_HEAD.match(x) for x in fields["body"].split("\n")):
        raise ValueError("縮排的併入段有 ## 附件（id %s），附件隨來源卡歸檔在 %s/archive/*-%s/attachments/，拆出帶不回來，請手動處理"
                         % (mid, os.path.dirname(os.path.abspath(card_dir)), mid))
    return card_body(fields)


def card(card_dir: str, mid: str) -> str:
    with safefile.CardLock(card_dir):
        return _card_unlocked(card_dir, mid)


def _remove_unlocked(card_dir: str, mid: str) -> None:
    inbox = os.path.join(card_dir, "inbox.md")
    with open(inbox, encoding="utf-8") as f:
        cur = f.read()
    start, end = find(cur, mid)
    lines = LINE.findall(cur)
    safefile.write_atomic(inbox, "".join(lines[:start] + lines[end:]))


def remove(card_dir: str, mid: str) -> None:
    with safefile.CardLock(card_dir):
        _remove_unlocked(card_dir, mid)


def carried(raw: str, mid: str) -> dict:
    """- carried: 的一行 JSON 解析成記錄並驗形狀（carry 寫的形狀，見 carry）；不對就 raise，訊息指名段 id 與欄位。"""
    try:
        rec = json.loads(raw)
    except json.JSONDecodeError as e:
        raise ValueError("併入段 %s 的 - carried: 不是 JSON：%s" % (mid, raw)) from e
    if not isinstance(rec, dict):
        raise ValueError("併入段 %s 的 - carried: 要是 JSON 物件：%s" % (mid, raw))
    extra = sorted(set(rec) - {"impact", "evidence", "set", "before"})
    if extra:
        raise ValueError("併入段 %s 的 - carried: 有不認得的欄位 %s" % (mid, "、".join(extra)))
    for k in ("impact", "evidence"):
        if k in rec and not (isinstance(rec[k], list) and all(isinstance(x, str) for x in rec[k])):
            raise ValueError("併入段 %s 的 - carried: 的 %s 要是字串陣列：%s" % (mid, k, json.dumps(rec[k], ensure_ascii=False)))
    for k in ("set", "before"):
        if k in rec and not isinstance(rec[k], dict):
            raise ValueError("併入段 %s 的 - carried: 的 %s 要是物件：%s" % (mid, k, json.dumps(rec[k], ensure_ascii=False)))
    written, before = rec.get("set", {}), rec.get("before", {})
    if set(written) != set(before):
        raise ValueError("併入段 %s 的 - carried: 的 set 與 before 鍵要相同：set 有 [%s]，before 有 [%s]"
                         % (mid, "、".join(sorted(written)), "、".join(sorted(before))))
    for k in written:
        if k not in CARRIED_KEYS:
            raise ValueError("併入段 %s 的 - carried: 的 set 不能有 %s，只能是 %s" % (mid, k, "、".join(CARRIED_KEYS)))
        for side, v in (("set", written[k]), ("before", before[k])):
            if v is not None and not (isinstance(v, str) and "\n" not in v):
                raise ValueError("併入段 %s 的 - carried: 的 %s.%s 要是不含換行的字串或 null：%s"
                                 % (mid, side, k, json.dumps(v, ensure_ascii=False)))
    return rec


def undo(rec: dict, text: str) -> dict:
    """carried 驗過的記錄換成 rewrite_frontmatter 的 updates：拿掉仍在的 impact 值與 evidence 片段（拿空就刪鍵），
    kind_of_work 只在現值仍等於當初寫入值時改回改前的值（null 是刪鍵）；priority 那組鍵要每個都仍等於寫入值才整組改回；人改過的不動。"""
    fm, _ = priority.frontmatter(text)
    updates = {}
    impact = [x.strip() for x in (fm.get("impact") or "").split(",") if x.strip()]
    kept = [x for x in impact if x not in rec.get("impact", [])]
    if kept != impact:
        updates["impact"] = ", ".join(kept) or None
    parts = [p for p in (fm.get("evidence") or "").split(" ; ") if p]
    kept = [p for p in parts if p not in rec.get("evidence", [])]
    if kept != parts:
        updates["evidence"] = " ; ".join(kept) or None
    written = rec.get("set", {})
    if "kind_of_work" in written and fm.get("kind_of_work") == written["kind_of_work"]:
        updates["kind_of_work"] = rec["before"]["kind_of_work"]
    # 三個鍵一起才是合格的覆寫：只撤一部分會留下沒理由的 priority，或把人拿掉的 priority_auto 加回來
    group = [k for k in written if k in PRIORITY_KEYS]
    if all(fm.get(k) == written[k] for k in group):
        updates.update({k: rec["before"][k] for k in group})
    return updates


def _reverted_unlocked(card_dir: str, mid: str, top: str) -> str:
    """拆掉 mid 之後目標 inbox.md 的全文，不寫檔：刪那一段；縮排段再照 - carried: 改回 frontmatter、用其餘段重併（remerged），
    刪 ## 證據 裡「- 併進：<repo>/<id> · 」那行。一行形狀（opsx new 寫的）沒有 carry 也沒有證據行，只刪段；
    沒有 - carried: 的舊縮排段只刪證據行，提醒人看 frontmatter。"""
    inbox = os.path.join(card_dir, "inbox.md")
    with open(inbox, encoding="utf-8") as f:
        cur = f.read()
    start, end = find(cur, mid)
    lines = LINE.findall(cur)
    fields = parse([x.rstrip("\n") for x in lines[start:end]])
    text = "".join(lines[:start] + lines[end:])
    if "body" not in fields:
        return text
    if "carried" in fields:
        text = rewrite_frontmatter(text, undo(carried(fields["carried"], mid), text), inbox)
        text = remerged(text, os.path.basename(card_dir), inbox)
    else:
        print("split-out: 併入段 %s 是舊段，沒有 - carried: 記錄，%s 的 frontmatter 沒撤回，請檢查 kind_of_work、impact、evidence、priority"
              % (mid, inbox), file=sys.stderr)
    prefix = "- 併進：%s/%s · " % (os.path.basename(top), mid)
    lines = text.split("\n")
    hit = None
    if "## 證據" in lines:
        for i in range(lines.index("## 證據") + 1, len(lines)):
            if HEAD.match(lines[i]):
                break
            if lines[i].startswith(prefix):
                hit = i
                break
    if hit is None:
        print("split-out: %s 的 ## 證據 找不到「%s」開頭的行，請手動確認" % (inbox, prefix), file=sys.stderr)
    else:
        del lines[hit]
    return "\n".join(lines)


def split_out(card_dir: str, mid: str, top: str) -> None:
    """同一個卡鎖內讀併入段、算好撤回 merge-card 改動並刪段後的目標全文、建新殼、一次寫回目標。
    段或 - carried: 格式不對時在建殼前就失敗。新殼建好就先印它的 slug：之後寫回失敗時 split-out.sh 要告訴人哪張殼已建。"""
    common = os.path.join(os.path.dirname(os.path.abspath(__file__)), "common.sh")
    with safefile.CardLock(card_dir):
        shell = _card_unlocked(card_dir, mid)
        after = _reverted_unlocked(card_dir, mid, top)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".md") as body:
            body.write(shell)
            body.flush()
            p = subprocess.run(["bash", "-c", 'source "$1"; new_shell "$2" "$3" "$4" "$5"', "opsx-split-out", common, top, mid, body.name,
                                os.path.basename(card_dir)], env=dict(os.environ, OPSX_PY=sys.executable),
                               stdout=subprocess.PIPE, text=True)
        if p.returncode != 0:
            raise ValueError("建殼失敗：new_shell 退出 %d（上面是原因）" % p.returncode)
        print(p.stdout.strip(), flush=True)
        safefile.write_atomic(os.path.join(card_dir, "inbox.md"), after)


def evidence(card_dir: str, line: str) -> None:
    """在卡鎖內把 line 插在 `## 證據` 段最後一行非空內容之後（段內沒有非空行就接在標題後空一行之後，跟 sync.py 的 append_to_section 同位置）。"""
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        with open(inbox, encoding="utf-8") as f:
            lines = f.read().split("\n")
        if "## 證據" not in lines:
            raise ValueError("%s 沒有 ## 證據 段" % inbox)
        sec = lines.index("## 證據")
        last = None
        for i in range(sec + 1, len(lines)):
            if HEAD.match(lines[i]):
                break
            if lines[i].strip():
                last = i
        if last is None:
            lines[sec + 1:sec + 1] = ["", line]
        else:
            lines.insert(last + 1, line)
        safefile.write_atomic(inbox, "\n".join(lines))


def rewrite_frontmatter(text: str, updates: dict, where: str) -> str:
    """frontmatter 裡 updates 的 key 改成同一行的 key: value（原本巢狀的縮排續行一併拿掉）；原本沒有的接在結尾 --- 前。
    值是 None 的 key 整個拿掉，原本沒有就不加。
    where 是檔案路徑，沒有 frontmatter（第一行不是 ---，或沒有結尾 ---）時訊息指名它。"""
    lines = text.split("\n")
    end = next((i for i, x in enumerate(lines[1:], 1) if x.strip() == "---"), None)
    if lines[0].strip() != "---" or end is None:
        raise ValueError("%s 沒有 frontmatter（第一行要是 ---，並且有結尾的 ---）" % where)
    out, seen, skipping = [lines[0]], set(), False
    for x in lines[1:end]:
        if x[:1] in (" ", "\t") and x.strip():
            if not skipping:
                out.append(x)
            continue
        key = x.partition(":")[0].strip()
        skipping = key in updates
        if skipping:
            if updates[key] is not None:
                out.append("%s: %s" % (key, updates[key]))
            seen.add(key)
        else:
            out.append(x)
    out += ["%s: %s" % (k, v) for k, v in updates.items() if k not in seen and v is not None]
    return "\n".join(out + lines[end:])


def facts(slug: str, text: str) -> dict:
    """{kind, impact 清單, evidence, priority, reason}；欄位不合格丟 ValueError，訊息指名卡與欄位。"""
    try:
        got = priority.facts_of(slug, text)
    except priority.PriorityError as e:
        raise ValueError(str(e)) from e
    fm, nested = priority.frontmatter(text)
    ev = fm.get("evidence") or (priority.nested_impact(slug, nested["impact"])[1] if "impact" in nested else "")
    return {"kind": got["kind"], "impact": got["impact"], "evidence": ev, "priority": got["priority"], "reason": got["priority_reason"]}


def with_carried(text: str, mid: str, record: dict) -> str:
    """record 以 `- carried: <一行 JSON>` 插在 mid 那段併入欄位列最後一行之後。"""
    lines = LINE.findall(text)
    start, end = find(text, mid)
    blank = next((i for i in range(start + 2, end) if lines[i] == "\n"), None)
    if blank is None:
        raise ValueError("併入段 %s 的欄位列後面沒有空行，記不了 - carried:" % mid)
    lines.insert(blank, "- carried: %s\n" % json.dumps(record, ensure_ascii=False))
    return "".join(lines)


def merged_updates(t: dict, s: dict, source_slug: str) -> dict:
    """carry 的合併規則：目標事實 t 併進來源事實 s（facts 的形狀）要寫進目標 frontmatter 的 updates，不讀寫檔。"""
    updates = {}
    if s["kind"] == "incident" and t["kind"] != "incident":
        updates["kind_of_work"] = "incident"
    impact = t["impact"] + [x for x in s["impact"] if x not in t["impact"]]
    parts = [x for x in dict.fromkeys(p for e in (t["evidence"], s["evidence"]) for p in e.split(" ; ")) if x]
    evidence = " ; ".join(parts)
    if impact != t["impact"]:
        updates["impact"] = ", ".join(impact)
    if evidence != t["evidence"] or "impact" in updates:   # 目標原本用巢狀寫法時，evidence 要跟著 impact 一起改成同一行
        updates["evidence"] = evidence
    effective = t["priority"] or priority.rule_level("incident" if "kind_of_work" in updates else t["kind"], impact, None, None)[0]
    if s["priority"] and priority.LEVELS.index(s["priority"]) < priority.LEVELS.index(effective):
        updates.update({"priority": s["priority"], "priority_reason": "併自 %s：%s" % (source_slug, s["reason"]),
                        "priority_auto": None})
    return updates


def undone_facts(slug: str, text: str) -> dict:
    """撤回後、重併前的目標事實（merged_updates 用到的 kind、impact、evidence、priority）。
    不經 facts_of 驗：共用的 evidence 片段剛被撤掉時 impact 會暫時沒有 evidence，要等其餘段重併補回。"""
    fm, nested = priority.frontmatter(text)
    if "impact" in nested:
        try:
            impact, ev = priority.nested_impact(slug, nested["impact"])
        except priority.PriorityError as e:
            raise ValueError(str(e)) from e
    else:
        impact, ev = [x.strip() for x in (fm.get("impact") or "").split(",") if x.strip()], ""
    return {"kind": fm.get("kind_of_work") or "planned", "impact": impact, "evidence": fm.get("evidence") or ev,
            "priority": fm.get("priority")}


def remerged(text: str, slug: str, where: str) -> str:
    """目標裡其餘帶 frontmatter 的併入段，依檔案順序照 carry 的規則重併進 text 的 frontmatter；不寫 - carried:。
    一行形狀與沒有 frontmatter 的舊縮排段不參與。"""
    lines = [x.rstrip("\n") for x in LINE.findall(text)]
    heads = [i for i, x in enumerate(lines) if HEAD.match(x)] + [len(lines)]
    for a, b in zip(heads, heads[1:]):
        if not MERGED.match(lines[a]):
            continue
        got = parse(lines[a:b])
        if "body" in got and got["body"].startswith("---"):
            text = rewrite_frontmatter(text, merged_updates(undone_facts(slug, text), facts(got["id"], got["body"]), got["id"]), where)
    return text


def carry(target_dir: str, source_inbox: str, source_slug: str, mid: str | None) -> None:
    """來源卡的事實欄位併進目標卡 frontmatter：kind_of_work 取較高（incident 高於 planned），impact 取聯集，
    evidence 依 " ; " 分段去重後接在後面，來源的 priority 覆寫比目標高（或目標沒有）就連同理由帶過去。
    來源沒有事實（planned、沒有 impact、沒有 evidence、沒有覆寫）就不解析目標，frontmatter 一個位元組都不動。
    等級由 opsx priority 從併完的欄位算。priority 覆寫只在比目標的有效等級（目標的覆寫，沒有就用併完的 kind 與 impact 算的等級）高時才帶過去。
    shortcut: 有效等級不看 workplan 的 milestone 位置，覆寫可能壓過目標因 milestone 得到的較高等級；併卡的來源與目標都在收件匣時沒差，到進了 workplan 的卡才要升級成用 priority.levels(top)
    改了什麼在同一把鎖內以 `- carried:` 記進併入段 mid（split-out 照它撤回）：{"impact": [加的值], "evidence": [加的片段],
    "set": {單值鍵: 寫入值}, "before": {單值鍵: 改前的值，沒有是 null}}，沒改的鍵不寫，什麼都沒改是 {}。
    mid 是 None 時只驗兩張卡的欄位合格、目標有 frontmatter（opsx merge-card 在捨棄來源之前呼叫），不寫檔。"""
    inbox = os.path.join(target_dir, "inbox.md")
    with open(source_inbox, encoding="utf-8") as f:
        s = facts(source_slug, f.read())
    if s["kind"] == "planned" and not (s["impact"] or s["evidence"] or s["priority"]):
        if mid is None:
            return
        with safefile.CardLock(target_dir):
            with open(inbox, encoding="utf-8") as f:
                text = f.read()
            safefile.write_atomic(inbox, with_carried(text, mid, {}))
        return
    with safefile.CardLock(target_dir):
        with open(inbox, encoding="utf-8") as f:
            text = f.read()
        t = facts(os.path.basename(target_dir), text)
        updates = merged_updates(t, s, source_slug)
        new = rewrite_frontmatter(text, updates, inbox)
        if mid is None:
            return
        fm, _ = priority.frontmatter(text)
        record = {}
        if "impact" in updates:
            record["impact"] = [x for x in s["impact"] if x not in t["impact"]]
        parts = updates["evidence"].split(" ; ") if "evidence" in updates else []
        added = [p for p in parts if p and p not in t["evidence"].split(" ; ")]
        if added:
            record["evidence"] = added
        single = {k: v for k, v in updates.items() if k not in ("impact", "evidence") and fm.get(k) != v}
        if single:
            record["set"] = single
            record["before"] = {k: fm.get(k) for k in single}
        safefile.write_atomic(inbox, with_carried(new, mid, record))


def drop(card_dir: str, reason: str, argv: list) -> int:
    """在卡鎖內重查併入段、寫 outcome 與捨棄理由、跑 argv（歸檔），到 argv 結束才放鎖。argv 失敗回 3。"""
    inbox = os.path.join(card_dir, "inbox.md")
    with safefile.CardLock(card_dir):
        if os.path.exists(inbox):
            with open(inbox, encoding="utf-8") as f:
                ids = sorted(merged_ids(f.read()))
            if ids:
                raise ValueError("還有併入的項目（%s），先用 opsx split-out 拆出來再捨棄" % " ".join(ids))
        with safefile.open_append(os.path.join(card_dir, ".openspec.yaml")) as f:
            f.write("outcome: declined\n")
        with safefile.open_append(inbox) as f:
            f.write("\n## 捨棄理由\n\n%s\n" % reason)
        return 0 if subprocess.run(argv).returncode == 0 else 3


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    want = {"append": 9, "append-full": 5, "open-check": 2, "summary-check": 3, "card": 3, "remove": 3, "ids": 2, "evidence": 3, "split-out": 4, "carry": 5, "carry-check": 4}
    ok = len(args) >= 5 and args[3] == "--" if cmd == "drop" else cmd in want and len(args) == want[cmd]
    if not ok:
        sys.exit("用法：inboxmerge.py append <卡目錄> <基本 id> <ISO 時間> <來源> <kind_of_work> <evidence> <type> <一句話> | append-full <目標卡目錄> <來源 inbox 檔> <來源 slug> <ISO 時間> | open-check <目標卡目錄> | summary-check <來源 inbox 檔> <來源 slug> | card <卡目錄> <id> | remove <卡目錄> <id> | ids <卡目錄> | evidence <卡目錄> <行> | carry <目標卡目錄> <來源 inbox 檔> <來源 slug> <併入段 id> | carry-check <目標卡目錄> <來源 inbox 檔> <來源 slug> | split-out <卡目錄> <id> <repo 根> | drop <卡目錄> <理由> -- <歸檔指令…>")
    try:
        if cmd == "append":
            print(append(*args[1:]))
        elif cmd == "append-full":
            print(append_full(*args[1:]))
        elif cmd == "open-check":
            open_check(args[1])
        elif cmd == "summary-check":
            summary_check(*args[1:])
        elif cmd == "split-out":
            split_out(*args[1:])
        elif cmd == "evidence":
            evidence(*args[1:])
        elif cmd == "carry":
            carry(*args[1:])
        elif cmd == "carry-check":
            carry(*args[1:], None)
        elif cmd == "drop":
            sys.exit(drop(args[1], args[2], args[4:]))
        elif cmd == "card":
            sys.stdout.write(card(*args[1:]))
        elif cmd == "ids":
            with open(os.path.join(args[1], "inbox.md"), encoding="utf-8") as f:
                for mid in sorted(merged_ids(f.read())):
                    print(mid)
        else:
            remove(*args[1:])
    except FileNotFoundError as e:
        print("inboxmerge: 目標卡不見了：%s" % e, file=sys.stderr)
        sys.exit(1)
    except SectionNotFound as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(2)
    except TargetStarted as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(4)
    except (ValueError, OSError) as e:
        print("inboxmerge: %s" % e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
