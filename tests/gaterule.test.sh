#!/usr/bin/env bash
# 一個 gate 留給人、停 pane 或照建議答的純函式：規則由上往下取第一個符合的，不看 repo，有建議的決定題回 answer。
# 驗收：specs/gate-rule/spec.md（代不代答由一個純函式判斷）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

decide() { # <waiting 的 JSON，缺的欄位補成決定題的空值> → decide 的結果
  OPSX_W="$1" OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
w = {"gate_id": "g1", "type": "等待決定", "action": None, "question": "", "recommended": None, "options": [], "waits_on": None}
w.update(json.loads(os.environ["OPSX_W"]))
print(gaterule.decide(w))'
}

# 結果不依 repo 而不同：decide 只收 waiting 一個參數，沒有 repo 可看
assert_eq "$(OPSX_LIB="$OPSX_ROOT/bin/lib" python3 -I -c '
import inspect, os, sys
sys.path.insert(0, os.environ["OPSX_LIB"]); import gaterule
print(list(inspect.signature(gaterule.decide).parameters), hasattr(gaterule, "ANSWER_REPO"))')" "['w'] False" "decide 不收 repo、沒有 ANSWER_REPO"

assert_eq "$(decide '{"gate_id": "drive-apply-3", "recommended": "用 A"}')" "('human', 'stuck')" "卡住的 gate"
assert_eq "$(decide '{"gate_id": "卡在接 /review #2", "recommended": "用 A"}')" "('human', 'stuck')" "Stop hook 卡住的 gate"
assert_eq "$(decide '{"needs": "run", "recommended": "用 A"}')" "('human', 'run')" "needs run"
# 協調者代跑的題（Scenario Outline，正例）：by 排在 type、合併字與 hands 判斷前
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "recommended": "chmod +x hooks/reload.sh"}')" "('coordinator', 'run')" "代跑：決定題"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "needs": "run", "by": "coordinator", "recommended": "cd /x/wt && git push gitlab feat/a/mikaela-lin"}')" "('coordinator', 'run')" "代跑：授權題"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "needs": "run", "by": "coordinator", "recommended": "push 前先 fetch 一次"}')" "('coordinator', 'run')" "代跑：授權題，by 排在授權判斷前"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "recommended": "你在終端機跑 opsx stop x"}')" "('coordinator', 'run')" "代跑：建議含要人動手的字"
# 只有 by 沒有 needs run 不算代跑，照一般決定題答；卡住的 gate 標了 by 仍留給人（反例）
assert_eq "$(decide '{"by": "coordinator", "recommended": "用 A"}')" "('answer', '用 A')" "只有 by"
assert_eq "$(decide '{"gate_id": "drive-apply-3", "needs": "run", "by": "coordinator", "recommended": "用 A"}')" "('human', 'stuck')" "卡住的 gate 標了 by"
# 合併類、等別張卡、type 不明、split 標了 by 仍照原規則（design D7、D8）
assert_eq "$(decide '{"type": "等待授權", "action": "mr-merge", "needs": "run", "by": "coordinator", "recommended": "glab mr merge 12"}')" "('human', 'run')" "合併 action 標了 by"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "question": "要 Merge 嗎", "recommended": "glab mr merge 12"}')" "('human', 'run')" "題目含合併字標了 by"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "question": "CI 綠了，收尾", "recommended": "glab mr merge 42"}')" "('human', 'run')" "建議含合併字標了 by（design D14）"
assert_eq "$(decide '{"needs": "run", "by": "coordinator", "waits_on": "other-card", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "waits-on 標了 by"
assert_eq "$(decide '{"type": "type 不明", "needs": "run", "by": "coordinator", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "type 不明標了 by"
assert_eq "$(decide '{"gate_id": "split", "needs": "run", "by": "coordinator", "recommended": "chmod +x x.sh"}')" "('human', 'run')" "split 標了 by"
assert_eq "$(decide '{"type": "等待授權", "action": "deploy", "question": "要部署嗎"}')" "('human', 'approval')" "清單外的 action：授權題排在 level3 前"
assert_eq "$(decide '{"type": "等待授權", "action": null, "question": "要做嗎"}')" "('human', 'approval')" "沒寫 action"
# 授權題只在 MR 合併時是 merge-grant（Scenario Outline，正例＋反例）
assert_eq "$(decide '{"type": "等待授權", "action": "mr-merge", "question": "要合併嗎"}')" "('human', 'merge-grant')" "授權：mr-merge"
assert_eq "$(decide '{"type": "等待授權", "action": "merge", "question": "可以合了嗎"}')" "('human', 'merge-grant')" "授權：hook 第三級的 action 名 merge"
assert_eq "$(decide '{"type": "等待授權", "action": "external", "question": "要合併這個 MR 嗎"}')" "('human', 'merge-grant')" "授權：雙訊號"
assert_eq "$(decide '{"type": "等待授權", "action": "external", "question": "glab api PUT merge_requests/12/merge"}')" "('human', 'merge-grant')" "授權：forge API 路徑的 merge_requests"
assert_eq "$(decide '{"type": "等待授權", "action": "Merge", "question": "可以合了嗎"}')" "('human', 'merge-grant')" "授權：action merge 不分大小寫"
assert_eq "$(decide '{"type": "等待授權", "action": "external", "question": "打 Merge API"}')" "('human', 'merge-grant')" "授權：forge 的 merge API，不分大小寫"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "question": "要 push 嗎"}')" "('human', 'approval')" "授權：push"
assert_eq "$(decide '{"type": "等待授權", "action": "edit", "question": "要不要合併兩個設定檔"}')" "('human', 'approval')" "授權：講的不是 MR 合併"
assert_eq "$(decide '{"type": "終端機等待輸入", "question": "y/n?"}')" "('human', 'terminal')" "終端機等待輸入"
assert_eq "$(decide '{"type": "type 不明", "recommended": "用 A"}')" "('human', 'type')" "type 不明"
assert_eq "$(decide '{"waits_on": "card-x", "recommended": "等 card-x 合併後繼續"}')" "('park', 'card-x')" "waits-on 排在合併類之前"
assert_eq "$(decide '{"options": ["先合併 MR 再說"]}')" "('human', 'merge')" "沒建議時看第一個選項講不講 MR 合併"
assert_eq "$(decide '{"question": "選哪個"}')" "('human', 'no-pick')" "沒選項沒建議"
assert_eq "$(decide '{"question": "選哪個", "recommended": "你在 sandbox 外跑"}')" "('human', 'hands')" "建議要人動手"
assert_eq "$(decide '{"question": "這只有你能做", "recommended": "用 A"}')" "('human', 'hands')" "題目說只有你能做"
# 以前其他 repo 留給人的一般決定題，現在照建議答
assert_eq "$(decide '{"question": "要不要上真機驗", "recommended": "用 A"}')" "('answer', '用 A')" "真機題"
assert_eq "$(decide '{"question": "可以 push 嗎", "recommended": "用 A"}')" "('answer', '用 A')" "授權字題"
# 所有 repo 的決定題照建議答（Scenario Outline，正例）：每列一個斷言，repo 欄不進 decide
assert_eq "$(decide '{"gate_id": "g1", "question": "範圍要不要收窄？", "recommended": "A。收窄"}')" "('answer', 'A。收窄')" "opsx-workflow g1"
assert_eq "$(decide '{"gate_id": "split", "recommended": "照這個拆法", "options": ["照這個拆法", "改拆法", "不拆"]}')" "('answer', '照這個拆法')" "opsx-workflow split"
assert_eq "$(decide '{"gate_id": "g1", "question": "範圍要不要收窄？", "recommended": "A。收窄"}')" "('answer', 'A。收窄')" "Agentory-AI g1"
assert_eq "$(decide '{"gate_id": "split", "recommended": "照這個拆法", "options": ["照這個拆法", "改拆法", "不拆"]}')" "('answer', '照這個拆法')" "Agentory-AI split"
assert_eq "$(decide '{"gate_id": "logic-map-undecided-r1", "recommended": "1A 2A", "options": ["1A 2A", "1B 2B"]}')" "('answer', '1A 2A')" "Agentory-AI 邏輯表 ⚠"
assert_eq "$(decide '{"gate_id": "0303-prompt", "question": "0303 刪 skills 時改過的 prompt 要不要留", "recommended": "照現在"}')" "('answer', '照現在')" "Agentory-CS 0303-prompt"
assert_eq "$(decide '{"gate_id": "g1", "recommended": "用 A"}')" "('answer', '用 A')" "邊界：opsx-workflow-fork 不看 repo 名"
assert_eq "$(decide '{"gate_id": "g2", "recommended": "等 CI 綠再重跑 review"}')" "('answer', '等 CI 綠再重跑 review')" "邊界：單獨的 CI 不算改 CI"
assert_eq "$(decide '{"gate_id": "split", "recommended": "一張主 change", "options": ["照這個拆法", "改拆法", "不拆"]}')" "('answer', '一張主 change')" "一張主 change 的 split gate 照建議答"
# 留給人的題在每個 repo 都一樣（Scenario Outline，反例）：Agentory-AI 與 opsx-workflow 各列
assert_eq "$(decide '{"gate_id": "drive-apply-3", "recommended": "用 A"}')" "('human', 'stuck')" "Agentory-AI drive-apply-3"
assert_eq "$(decide '{"gate_id": "stale-wait-20261120101500", "recommended": "用 A"}')" "('human', 'stuck')" "Agentory-AI stale-wait"
assert_eq "$(decide '{"question": "選哪個", "options": ["B", "C"]}')" "('human', 'no-rec')" "Agentory-AI 選項 B、C 沒有建議（no-pick 一類，理由代碼帶出有選項）"
assert_eq "$(decide '{"needs": "run", "recommended": "用 A"}')" "('human', 'run')" "Agentory-AI needs run"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "recommended": "准"}')" "('human', 'approval')" "Agentory-AI 授權 push 建議准"
assert_eq "$(decide '{"type": "等待授權", "action": "mr-merge"}')" "('human', 'merge-grant')" "Agentory-AI 授權 mr-merge"
assert_eq "$(decide '{"type": "type 不明", "recommended": "用 A"}')" "('human', 'type')" "Agentory-AI type 不明"
assert_eq "$(decide '{"waits_on": "card-x"}')" "('park', 'card-x')" "Agentory-AI waits_on"
assert_eq "$(decide '{"recommended": "重試 glab mr merge 12"}')" "('human', 'merge')" "Agentory-AI 重試 glab mr merge"
assert_eq "$(decide '{}')" "('human', 'no-pick')" "Agentory-AI 沒有建議也沒有選項"
assert_eq "$(decide '{"recommended": "你在 sandbox 外跑"}')" "('human', 'hands')" "Agentory-AI 你在 sandbox 外跑"
assert_eq "$(decide '{"question": "選哪個", "options": ["B", "C"]}')" "('human', 'no-rec')" "opsx-workflow 選項 B、C 沒有建議"
assert_eq "$(decide '{"type": "等待授權", "action": "push", "recommended": "准"}')" "('human', 'approval')" "opsx-workflow 授權 push 建議准"
# 有第二張主 change 的 split gate 不寫建議、選項不標 Recommended（explore 拆卡段，me-20261122-1148 D9），協調者不代答
assert_eq "$(decide '{"gate_id": "split", "options": ["照這個拆法", "改拆法", "不拆"]}')" "('human', 'no-rec')" "兩張主 change 的 split gate 交人"
# 要人動手的字只比建議：沒有建議時第一個選項不是建議（D4）
assert_eq "$(decide '{"question": "怎麼拆", "options": ["你自己拆", "照 A 拆"]}')" "('human', 'no-rec')" "沒建議、第一個選項含你，不算要你動手"
# 第三級、花錢、對外的決定題留給人（Scenario Outline，反例）
assert_eq "$(decide '{"question": "下一步？", "recommended": "部署到 spark1"}')" "('human', 'level3')" "level3：部署"
assert_eq "$(decide '{"question": "要不要現在 deploy？", "recommended": "deploy monitoring"}')" "('human', 'level3')" "level3：deploy"
assert_eq "$(decide '{"question": "分支怎麼處理？", "recommended": "force-push 覆蓋"}')" "('human', 'level3')" "level3：force-push"
assert_eq "$(decide '{"question": "舊資料怎麼辦？", "recommended": "drop table legacy_faq"}')" "('human', 'level3')" "level3：drop table"
assert_eq "$(decide '{"question": "lint 怎麼過？", "recommended": "改 .gitlab-ci.yml 跳過 lint"}')" "('human', 'level3')" "level3：.gitlab-ci"
assert_eq "$(decide '{"question": "要不要改 CI 設定？", "recommended": "照建議改"}')" "('human', 'level3')" "level3：改 CI 設定"
assert_eq "$(decide '{"question": "key 放哪？", "recommended": "寫進 sops 加密檔"}')" "('human', 'level3')" "level3：sops"
assert_eq "$(decide '{"question": "要不要加 .env 變數？", "recommended": "加 FOO_URL 到 .env.gcp-dev"}')" "('human', 'level3')" "level3：.env"
assert_eq "$(decide '{"question": "要不要升級方案？", "recommended": "付費升級"}')" "('human', 'level3')" "level3：付費"
assert_eq "$(decide '{"question": "要不要通知客戶？", "recommended": "發信對客戶說明"}')" "('human', 'level3')" "level3：發信對客戶"
assert_eq "$(decide '{"question": "要不要在 issue 留言？", "recommended": "issue comment 附連結"}')" "('human', 'level3')" "level3：issue comment"
assert_eq "$(decide '{"question": "下一步？", "recommended": "Deploy to prod"}')" "('human', 'level3')" "level3 邊界：大小寫不分"
assert_eq "$(decide '{"question": "要放 Secret 嗎", "recommended": "放"}')" "('human', 'level3')" "level3 邊界：字詞在題目裡也算"
assert_eq "$(decide '{"question": "下一步？", "recommended": "改 CI 跳過這步"}')" "('human', 'level3')" "level3 邊界：opsx-workflow 一樣交人"
# 刪資料、強推與打 tag 的說法也是第三級
assert_eq "$(decide '{"question": "舊欄位怎麼處理？", "recommended": "寫 migration ALTER TABLE faq DROP COLUMN legacy"}')" "('human', 'level3')" "level3：drop column"
assert_eq "$(decide '{"question": "測試庫怎麼清？", "recommended": "drop database test_db"}')" "('human', 'level3')" "level3：drop database"
assert_eq "$(decide '{"question": "舊 schema？", "recommended": "DROP SCHEMA legacy CASCADE"}')" "('human', 'level3')" "level3：drop schema"
assert_eq "$(decide '{"question": "髒資料？", "recommended": "DELETE FROM faq WHERE id > 10"}')" "('human', 'level3')" "level3：delete from"
assert_eq "$(decide '{"question": "build 目錄？", "recommended": "rm -rf dist 再重 build"}')" "('human', 'level3')" "level3：rm -rf"
assert_eq "$(decide '{"question": "工作區亂了？", "recommended": "git reset --hard origin/main"}')" "('human', 'level3')" "level3：reset --hard"
assert_eq "$(decide '{"question": "legacy 欄位？", "recommended": "刪欄位"}')" "('human', 'level3')" "level3：刪欄位"
assert_eq "$(decide '{"question": "舊表？", "recommended": "刪除表 faq_old"}')" "('human', 'level3')" "level3：刪除表"
assert_eq "$(decide '{"question": "舊分支？", "recommended": "刪分支 feat/x"}')" "('human', 'level3')" "level3：刪分支"
assert_eq "$(decide '{"question": "要發版嗎？", "recommended": "git tag v1.2.0"}')" "('human', 'level3')" "level3：git tag"
assert_eq "$(decide '{"question": "要發版嗎？", "recommended": "打 tag 觸發 CD"}')" "('human', 'level3')" "level3：打 tag"
assert_eq "$(decide '{"question": "tag 推上去？", "recommended": "git push --tags"}')" "('human', 'level3')" "level3：push --tags"
assert_eq "$(decide '{"question": "要不要直接改 prod 的設定？", "recommended": "改"}')" "('human', 'level3')" "level3：prod"
assert_eq "$(decide '{"question": "下一步？", "recommended": "推到prod"}')" "('human', 'level3')" "level3 邊界：prod 前面接中文"
assert_eq "$(decide '{"question": "product 欄位要不要改名？", "recommended": "改成 product_name"}')" "('answer', '改成 product_name')" "level3 邊界：product 不是 prod"
assert_eq "$(decide '{"question": "要不要加 production 註解？", "recommended": "加"}')" "('answer', '加')" "level3 邊界：production 不是 prod"
# 合併字與授權字同時出現是在問要不要合併，交人
assert_eq "$(decide '{"question": "要授權合併嗎？", "recommended": "允許"}')" "('human', 'merge')" "合併加授權：要授權合併嗎"
assert_eq "$(decide '{"question": "Ready to merge?", "recommended": "yes"}')" "('human', 'merge')" "合併加授權：Ready to merge"
assert_eq "$(decide '{"question": "下一步？", "recommended": "允許 merge"}')" "('human', 'merge')" "合併加授權：建議裡的允許 merge"
assert_eq "$(decide '{"question": "forge 拒絕合併（pipeline 紅），要怎麼做？", "recommended": "重跑 pipeline 後重試合併"}')" "('answer', '重跑 pipeline 後重試合併')" "合併字沒有授權字照建議答"
assert_eq "$(decide '{"question": "already 處理過的列要不要合併？", "recommended": "合併"}')" "('answer', '合併')" "合併加授權邊界：already 不是 ready"
# logic-map-failed 的「無 Agent 工具」gate 要人在看板動手
assert_eq "$(decide '{"gate_id": "logic-map-failed-1", "question": "產表失敗：無 Agent 工具", "recommended": "你在看板派一個 claude pane 重產", "options": ["你在看板派一個 claude pane 重產", "這張不要表，直接放行"]}')" "('human', 'hands')" "logic-map-failed 無 Agent 工具：要人動手"
# level3 排在 merge 之後、no-pick 之前；waits-on 仍先於它
assert_eq "$(decide '{"question": "deploy 前先合併 MR？", "recommended": "先合併 MR"}')" "('human', 'merge')" "merge 先於 level3"
assert_eq "$(decide '{"question": "要不要 deploy？"}')" "('human', 'level3')" "level3 先於 no-pick"
assert_eq "$(decide '{"waits_on": "card-x", "recommended": "card-x 進 main 後再部署"}')" "('park', 'card-x')" "waits-on 先於 level3"
# MR 合併的決定題留給人（Scenario Outline，正例）
assert_eq "$(decide '{"question": "CI 綠了，下一步？", "recommended": "重試 glab mr merge 12"}')" "('human', 'merge')" "MR 合併：glab 指令"
assert_eq "$(decide '{"question": "要不要先合併 MR？", "recommended": "先合併 MR 再說"}')" "('human', 'merge')" "MR 合併：合併 MR"
assert_eq "$(decide '{"question": "下一步？", "recommended": "合進 main"}')" "('human', 'merge')" "MR 合併：合進 main"
assert_eq "$(decide '{"question": "下一步？", "recommended": "去板上按合併"}')" "('human', 'merge')" "MR 合併：按合併"
assert_eq "$(decide '{"question": "下一步？", "recommended": "Merge PR !12"}')" "('human', 'merge')" "MR 合併邊界：大小寫與 !號碼"
assert_eq "$(decide '{"question": "下一步？", "recommended": "gh pr merge 7 --squash"}')" "('human', 'merge')" "MR 合併邊界：gh 指令"
assert_eq "$(decide '{"question": "下一步？", "recommended": "merge into main"}')" "('human', 'merge')" "MR 合併邊界：英文寫法"
assert_eq "$(decide '{"question": "要合併這個 MR 嗎？", "recommended": "合併"}')" "('human', 'merge')" "雙訊號：合併字與 MR 中間隔字"
assert_eq "$(decide '{"question": "下一步？", "recommended": "合併到 main"}')" "('human', 'merge')" "雙訊號：合併到 main"
assert_eq "$(decide '{"question": "PR #12 要 merge 嗎", "recommended": "要"}')" "('human', 'merge')" "雙訊號：#號碼"
assert_eq "$(decide '{"question": "下一步？", "recommended": "merge the MR"}')" "('human', 'merge')" "雙訊號：merge the MR"
assert_eq "$(decide '{"question": "下一步？", "recommended": "merge pull request 12"}')" "('human', 'merge')" "雙訊號：pull request"
assert_eq "$(decide '{"question": "下一步？", "recommended": "merge into master"}')" "('human', 'merge')" "雙訊號：master"
assert_eq "$(decide '{"question": "下一步？", "recommended": "merge the PRs"}')" "('human', 'merge')" "雙訊號：複數 PRs"
# 不是 MR 合併的合併字不擋（Scenario Outline，反例）
assert_eq "$(decide '{"question": "要不要把兩個 helper 合併？", "recommended": "合併成一個 helper"}')" "('answer', '合併成一個 helper')" "程式碼合併照建議答"
assert_eq "$(decide '{"question": "照這個拆法建殼？", "recommended": "相近的主題合併到同一個 session"}')" "('answer', '相近的主題合併到同一個 session')" "session 分組照建議答"
assert_eq "$(decide '{"question": "下一步？", "recommended": "重試 merge"}')" "('answer', '重試 merge')" "沒有 MR 語境的 merge 照建議答"
assert_eq "$(decide '{"question": "兩張卡要不要合併？", "recommended": "合併卡片"}')" "('answer', '合併卡片')" "卡片合併照建議答"
assert_eq "$(decide '{"question": "衝突怎麼處理？", "recommended": "git merge origin/main 再解衝突"}')" "('answer', 'git merge origin/main 再解衝突')" "分支合併照建議答"
# decide 回的每個 human 理由代碼都要在 coordinate.py 的 GATE_HUMAN 有文字，漏了 handle_gate 會拋 KeyError、整輪失敗。
# terminal 由 handle_gate 在查表前自己處理，不查 GATE_HUMAN
missing_human_text() { # <gaterule.py> <coordinate.py> → 沒有文字的理由代碼，空白分隔；全有時印空行
  python3 -I -c '
import ast, sys
rule, coord = (ast.parse(open(p, encoding="utf-8").read()) for p in sys.argv[1:3])
codes = {n.elts[1].value for n in ast.walk(rule)
         if isinstance(n, ast.Tuple) and len(n.elts) == 2
         and all(isinstance(e, ast.Constant) and isinstance(e.value, str) for e in n.elts) and n.elts[0].value == "human"}
table = next(n.value for n in coord.body if isinstance(n, ast.Assign) and any(getattr(t, "id", None) == "GATE_HUMAN" for t in n.targets))
keys = {k.value for k in table.keys}
print(" ".join(sorted(codes - keys - {"terminal"})))' "$1" "$2"
}
assert_eq "$(missing_human_text "$OPSX_ROOT/bin/lib/gaterule.py" "$OPSX_ROOT/bin/lib/coordinate.py")" "" "每個 human 理由代碼在 GATE_HUMAN 都有文字"
# 自檢：GATE_HUMAN 少了 level3 時要抓得到
NO_TEXT="$FX/coordinate-no-level3.py"
grep -v '"level3":' "$OPSX_ROOT/bin/lib/coordinate.py" > "$NO_TEXT"
assert_eq "$(missing_human_text "$OPSX_ROOT/bin/lib/gaterule.py" "$NO_TEXT")" "level3" "GATE_HUMAN 漏 level3 時要抓到"
# import 全在檔頂（~/.claude/CLAUDE.md §5）：docstring 之後，第一個非 import 敘述之前
assert_eq "$(python3 -I -c '
import ast, sys
body = ast.parse(open(sys.argv[1], encoding="utf-8").read()).body
if isinstance(body[0], ast.Expr): body = body[1:]
kinds = [isinstance(n, (ast.Import, ast.ImportFrom)) for n in body]
print(kinds.count(True) == kinds[:kinds.index(False)].count(True))' "$OPSX_ROOT/bin/lib/gaterule.py")" True "gaterule.py 的 import 要在檔頂"
echo ok
