#!/usr/bin/env bash
# skills/lead/SKILL.md：協調者的職責與六種回報類型。specs/opsx-lead/spec.md「協調者 skill 寫明職責與六種回報類型」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$OPSX_ROOT/skills/lead/SKILL.md"
assert_file "$F"

# 類型 1 到 6 依序出現在 ## Report format 之後
line_of() { grep -nF -- "$1" "$F" | head -1 | cut -d: -f1; }
prev="$(line_of '## Report format')"; [ -n "$prev" ] || fail "缺 ## Report format"
for h in '### 類型 1：進度' '### 類型 2：可以合併' '### 類型 3：要你決定' '### 類型 4：要你在終端機跑' '### 類型 5：我處理掉的' '### 類型 6：事件回應'; do
  n="$(line_of "$h")"; [ -n "$n" ] || fail "缺回報類型：$h"
  [ "$n" -gt "$prev" ] || fail "回報類型順序錯：$h 在第 $n 行，前一個在第 $prev 行"
  prev="$n"
done

# 各類型的欄名與固定字（spec 的 Examples 表每一列），只看 ## Report format 段
REPORT="$(sed -n '/^## Report format/,$p' "$F")"
for s in \
  '| 區塊 | 待處理 | 進行中 | 待指派 | 收件匣 |' \
  '| 功能 | 卡 | 階段 | 卡在 |' \
  '| 程式名 | 誰設定 | 業務上是什麼 | 被擋時記成 |' \
  '| 你是誰 | 結果 |' \
  '| 節點 | 白話 |' \
  '| # | 卡 | 問什麼 | 你的回答 |' \
  '| 卡 | 為什麼我做不到 | 指令 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '一到三行' '最後一行' 'logic-map.md' 'report.md' \
  '表格外' '一行一條' '絕對路徑' 'path:line'; do
  case "$REPORT" in *"$s"*) ;; *) fail "Report format 缺：$s" ;; esac
done
# 沒有邏輯表的卡：那幾欄寫「還沒有邏輯表」（design D6）
T2="$(awk '/^### 類型 2：/{f=1;next} f&&/^### 類型 /{exit} f' "$F")"
case "$T2" in *'還沒有邏輯表'*) ;; *) fail "類型 2 要寫沒有邏輯表時那幾欄寫「還沒有邏輯表」" ;; esac
# 沒有 pipeline 寫「沒有 CI」（design D11）；邏輯表的 head 取自 report.md「## 邏輯表」那行（design D13）
for s in '沒有 CI' '`pipeline_status`' '`## 邏輯表`' '`mr.head_sha`' '前 7 碼' '邏輯表沒產出'; do
  case "$T2" in *"$s"*) ;; *) fail "類型 2 缺：$s" ;; esac
done
# 使用者 2026-11-19 範例的段落格式（spec「可合併回報的段落欄位都在」兩張 Examples 表每一列）
for s in 'first line of 類型 2' '只有 !101' 'git merge-tree' '[me-20260105-1010 邏輯表](file:///home/dev/' \
  '沒看過程式的人' '直接貼' '寫「無」' '差的 commit 改了什麼' 'references/mergeable-report.md'; do
  case "$T2" in *"$s"*) ;; *) fail "類型 2 缺：$s" ;; esac
done
# 合併順序在第一段之前、⚠ 之前；段間 --- 夾在 ### 1. 與 ### 2. 之間（spec「合併順序不放最後（反例）」、分隔列）
t2_line() { printf '%s\n' "$T2" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
order="$(t2_line '合併順序是 !101 → !102')"; s1="$(t2_line '### 1. !101')"; s2="$(t2_line '### 2. !102')"; warn="$(t2_line '**⚠**')"
[ -n "$order" ] && [ -n "$s1" ] && [ -n "$s2" ] && [ -n "$warn" ] || fail "類型 2 缺合併順序例句、### 1.、### 2. 或 **⚠**"
[ "$order" -lt "$s1" ] && [ "$order" -lt "$warn" ] || fail "合併順序要在第一段與 ⚠ 之前（順序 $order、### 1. $s1、⚠ $warn）"
printf '%s\n' "$T2" | sed -n "$((warn + 1)),$((s2 - 1))p" | grep -qx -- '---' || fail "### 1. 段結束到 ### 2. 之間要有 ---"
case "$T2" in *'建議合併順序'*) fail "類型 2 不能再把建議合併順序放最後" ;; esac
# 沒有邏輯表那條：只動測試檔才照 diff 寫功能說明與邏輯圖，其他卡照 D6 寫還沒有邏輯表（spec「沒有邏輯表時照 diff 寫邏輯圖」正反例）
NOMAP="$(printf '%s\n' "$T2" | grep -F 'no logic map')"
for s in 'only test files' '功能說明' '邏輯圖' '照 diff 寫' '還沒有邏輯表' '卡的 report'; do
  case "$NOMAP" in *"$s"*) ;; *) fail "沒有邏輯表那條缺：$s — $NOMAP" ;; esac
done
# 產表失敗只在狀態寫邏輯表沒產出，照 diff 寫與否仍看只改測試（design D5）
case "$NOMAP" in *'or 產表失敗'*) fail "產表失敗不能一律歸成其他沒邏輯表的卡（design D5）" ;; esac
# 只有合 main：看 PR 自己的 commit 與解衝突的改動，不用會混進 main 的 <sha>..<head>
for s in '--first-parent --no-merges' '--remerge-diff'; do
  case "$T2" in *"$s"*) ;; *) fail "類型 2 判斷只合 main 要用：$s" ;; esac
done
case "$T2" in *'git log --oneline <sha>..<head>'*) fail "類型 2 不能再用會混進 main commit 的 git log --oneline <sha>..<head>" ;; esac
# 邏輯表落後且 PR 自己改了程式：四塊都照最新程式改
case "$T2" in *'邏輯圖, 條件表重點, 舉例 and ⚠'*'照最新程式改'*) ;; *) fail "邏輯表落後時邏輯圖、條件表重點、舉例、⚠ 都要照最新程式改" ;; esac
# reference 範例存在、不帶真實資料（spec「reference 範例不帶真實資料（反例）」）
R="$OPSX_ROOT/skills/lead/references/mergeable-report.md"
assert_file "$R"
# 禁用字樣拼接寫，免得這個檔自己被 readme-landing 的追蹤檔掃描命中
grep -niE 'ts''g-navigator|/Users/|agen''tory' "$R" && fail "reference 不能帶真實網址、家目錄路徑或內部專案名"
grep -qF '照 diff 寫' "$R" || fail "reference 要有沒有邏輯表、照 diff 寫的那段"
grep -qF '邏輯表是舊 head' "$R" || fail "reference 的落後 head 範例要用跟 SKILL.md 一樣的「邏輯表是舊 head」"
grep -qF 'PR 自己改了程式' "$R" || fail "reference 的落後規則要跟 SKILL.md 一樣看 PR 自己有沒有改程式"
# 類型 6 也照沒事不回報（design D36）
T6="$(awk '/^### 類型 6：/{f=1;next} f&&/^### /{exit} f' "$F")"
case "$T6" in *'沒事不回報'*) ;; *) fail "類型 6 要照沒事不回報（design D36）" ;; esac
# 類型 1 的區塊欄只寫 repo，milestone 另寫（design D12）
T1="$(awk '/^### 類型 1：/{f=1;next} f&&/^### /{exit} f' "$F")"
case "$T1" in *'區塊 is the repo only'*) ;; *) fail "類型 1 要寫區塊欄只寫 repo" ;; esac
printf '%s\n' "$T1" | grep -E '^\| [^|]* · [^|]* \| [0-9]' && fail "類型 1 計數表的區塊欄不能寫 repo · milestone"
printf '%s\n' "$T1" | grep -E '^\| [^|]*（[^|]*） \| [0-9]' && fail "類型 1 計數表的區塊欄只寫 repo 名，不帶括號別名（design D14）"
case "$T1" in *'沒設 milestone'*) ;; *) fail "類型 1 要寫 milestone 是 null 時寫「沒設 milestone」（design D15）" ;; esac
# 最後一行是每份回覆的共用規則，不只類型 1（design D7）
RULES="$(sed -n '/^## Report format/,/^### 類型 1：/p' "$F")"
case "$RULES" in *'最後一行'*) ;; *) fail "Report format 共用規則要有最後一行的規則" ;; esac
for s in '絕不合併' 'me-20261111-1315'; do
  grep -qF -- "$s" "$F" || fail "skill 缺：$s"
done
# 例子是虛構的：沒有內部網域、沒有家目錄路徑
for s in 'tsg-navigator' '/Users/'; do
  grep -qF -- "$s" "$F" && fail "skill 不能帶真實資料：$s"
done
# 舊的五塊區塊名不再出現
for s in 'block ①' 'block ④' 'Block ①' '① 要你處理' '⑤ 最後一行'; do
  grep -qF -- "$s" "$F" && fail "skill 還提到舊區塊名：$s"
done

# 可合併只看 agent 的回報（review 完、相關測試綠、跟 main 無衝突）；多張一起合時只用 git merge-tree 查依序疊起來無衝突，不重跑全套
# 只看職責 4 那一段（從「4. 」到「5. 」），表格註解裡的字不算
D4="$(sed -n '/^4\. /,/^5\. /p' "$F")"
[ -n "$D4" ] || fail "找不到職責 4"
for s in 'reports review done' 'Do not rerun the suite yourself' 'git merge-tree --write-tree' 'git commit-tree'; do
  case "$D4" in *"$s"*) ;; *) fail "職責 4 缺：$s" ;; esac
done
case "$D4" in *"run the full suite"*|*"rerun the suite against"*) fail "職責 4 不能叫協調者自己重跑全套：$D4" ;; esac
# 可以合併以 mr.state ready 為準，agent 回報是附加條件（design D10）
for s in '`mr.state` is `ready`' 'agent 還在改' 'agent 已停，還沒回報 review 完' '`## 測試`' 'Ledger'; do
  case "$D4" in *"$s"*) ;; *) fail "職責 4 缺：$s" ;; esac
done

# 去重是協調者的職責（specs/card-auto-merge「協調者 skill 寫明去重」）：Duties 裡有一條含 opsx merge-card 與同一件事，不受只併小事限制
DUTIES="$(sed -n '/^## Duties/,/^## Report format/p' "$F")"
DEDUP="$(printf '%s\n' "$DUTIES" | grep -F 'opsx merge-card')"
[ -n "$DEDUP" ] || fail "Duties 缺 opsx merge-card 的去重職責"
for s in '同一件事' '只併小事' 'decisions.tsv' '類型 5' 'kind_of_work' 'impact'; do
  case "$DEDUP" in *"$s"*) ;; *) fail "去重職責缺：$s — $DEDUP" ;; esac
done

# 討論出要改的直接開卡、做得到的自己做（specs/opsx-lead「協調者討論出要改的直接開卡、做得到的自己做」）
NEWCARD="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F 'opsx new' | grep -vF 'opsx merge-card')"
[ -n "$NEWCARD" ] || fail "Duties 缺 opsx new 開卡的職責"
for s in 'explore' '不問「要不要開卡」'; do
  case "$NEWCARD" in *"$s"*) ;; *) fail "開卡職責缺：$s — $NEWCARD" ;; esac
done
SELFDO="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F 'push' | grep -F '類型 4')"
[ -n "$SELFDO" ] || fail "Duties 缺「做得到的自己做，做不到照類型 4 給指令」的職責"
for s in 'MR' 'approval gate' 'gates.md' 'the gate comes first' 'not an approval' 'before you give the command'; do
  case "$SELFDO" in *"$s"*) ;; *) fail "自己做的職責缺：$s — $SELFDO" ;; esac
done
# 派工指示 P0（design D36）：清待處理、代答 opsx-workflow 的題、needs: run 自己跑；掃 pane；四欄流量控管
CLEAR="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F '待處理' | grep -F 'opsx answer')"
[ -n "$CLEAR" ] || fail "Duties 缺清待處理的職責"
for s in 'opsx-workflow' 'Recommended' '自動採用' 'needs: run' '怎麼問 gate'; do
  case "$CLEAR" in *"$s"*) ;; *) fail "清待處理職責缺：$s — $CLEAR" ;; esac
done
PANES="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F 'opsx relaunch')"
for s in 'idle' 'done' 'herdr pane read' 'enter' '繼續'; do
  case "$PANES" in *"$s"*) ;; *) fail "掃 pane 職責缺：$s — $PANES" ;; esac
done
FLOW="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F 'opsx dispatch')"
for s in '待處理' '進行中' '待指派' '收件匣' 'propose' 'depends-on'; do
  case "$FLOW" in *"$s"*) ;; *) fail "流量控管職責缺：$s — $FLOW" ;; esac
done
# 職責 2 只轉其他 repo 的題，不再寫「Every gate is the user's」
printf '%s\n' "$DUTIES" | grep '^2\. ' | grep -qF "Every gate is the user's" && fail "職責 2 要改成只轉 opsx-workflow 以外的題"
# 絕不合併留在最後一條
LAST="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | tail -1)"
case "$LAST" in *'絕不合併'*) ;; *) fail "最後一條職責要是絕不合併 — $LAST" ;; esac

# 怎麼問 gate（specs/opsx-lead「協調者用跳卡問 gate」「跳卡不代答」「有 sketch 外掛時先畫 cards」）：
# 只讀「## 怎麼問 gate」到下一個 ## 標題，別段的字不算；標題要夾在 ## Duties 與 ## Report format 之間
ASK="$(awk '/^## 怎麼問 gate/{f=1;next} f&&/^## /{exit} f' "$F")"
[ -n "$ASK" ] || fail "找不到「## 怎麼問 gate」段"
heading_of() { grep -n "^$1\$" "$F" | head -1 | cut -d: -f1; }
n_duties="$(heading_of '## Duties')"; n_ask="$(heading_of '## 怎麼問 gate')"; n_report="$(heading_of '## Report format')"
[ -n "$n_ask" ] && [ "$n_ask" -gt "$n_duties" ] && [ "$n_ask" -lt "$n_report" ] \
  || fail "「## 怎麼問 gate」要在 ## Duties（${n_duties}）與 ## Report format（${n_report}）之間，現在在 ${n_ask:-沒有}"
for s in 'AskUserQuestion' 'recommended option first' '(Recommended)' '最多 4 題' '卡名' '例子' \
  'opsx answer' '原文' 'Other' '重講' '不代答' \
  'without the `(Recommended)`' 'at most 12 characters' \
  '--grant' 'test-path' 'mode: stopped' 'approve option' '不准' 'Before each `opsx answer`' 'stderr' \
  'desktop' \
  'sketch' 'cards' '沒裝' 'enabledPlugins' 'opsx init --global' 'user settings' 'card pane'; do
  case "$ASK" in *"$s"*) ;; *) fail "怎麼問 gate 段缺：$s" ;; esac
done
# needs: run 的 gate 不進跳卡、給指令
NR="$(printf '%s\n' "$ASK" | grep -F 'needs: run')"
case "$NR" in *'stays out of the pop-up'*指令*) ;; *) fail "needs: run 那行要寫 stays out of the pop-up 並給指令：$NR" ;; esac
case "$NR" in *'goes in the pop-up'*) fail "needs: run 的 gate 不能進跳卡：$NR" ;; esac
# 跳卡回來後重讀 open gate：只問能進跳卡的（不是 needs: run、不是 waits-on），子 change 的 gate 也讀、用 --sub 回
RR="$(printf '%s\n' "$ASK" | grep -F 'status: open')"
for s in 'needs: run' 'waits-on' 'subs/' '--sub'; do
  case "$RR" in *"$s"*) ;; *) fail "重讀 open gate 那行缺：$s — $RR" ;; esac
done
# 不替使用者選
case "$ASK" in *自動採用*) fail "怎麼問 gate 段不能有「自動採用」" ;; esac
# compare 在段裡只出現一次，就是「不用 compare 選」那一處
assert_eq "$(printf '%s\n' "$ASK" | grep -o 'compare' | wc -l | tr -d ' ')" 1 "怎麼問 gate 段 compare 只能出現一次"
case "$ASK" in *'不用 `compare` to choose'*) ;; *) fail "怎麼問 gate 段要寫「不用 \`compare\` to choose」" ;; esac
# 職責 2 指向這段
printf '%s\n' "$DUTIES" | grep '^2\. ' | grep -qF '怎麼問 gate' || fail "職責 2 要指向「怎麼問 gate」段"
printf '%s\n' "$DUTIES" | grep '^2\. ' | grep -qF '類型 3' || fail "職責 2 要指向類型 3"

# 回報資料從哪來（specs/opsx-lead「協調者回報的資料來自 opsx collect」）：只讀「## 回報資料從哪來」到下一個 ## 標題，
# 段要夾在 ## 怎麼問 gate 與 ## Report format 之間
SRC="$(awk '/^## 回報資料從哪來/{f=1;next} f&&/^## /{exit} f' "$F")"
[ -n "$SRC" ] || fail "找不到「## 回報資料從哪來」段"
n_src="$(heading_of '## 回報資料從哪來')"
[ "$n_src" -gt "$n_ask" ] && [ "$n_src" -lt "$n_report" ] \
  || fail "「## 回報資料從哪來」要在 ## 怎麼問 gate（${n_ask}）與 ## Report format（${n_report}）之間，現在在 ${n_src}"
# jq 程式碼區塊與散文分開斷言：欄位要在程式碼裡，散文裡的同名字不算
JQ="$(printf '%s\n' "$SRC" | awk '/^```/{f=!f;next} f')"
PROSE="$(printf '%s\n' "$SRC" | awk '/^```/{f=!f;next} !f')"
[ -n "$JQ" ] || fail "回報資料從哪來段缺 jq 程式碼區塊"
for s in 'opsx collect > "$TMPDIR/opsx-collect.json"' 'select(.archived | not)' 'dispatched: (.dispatch != null)' \
  'pane: .dispatch.pane' 'open_gates' 'gate_id' 'waits_on' 'needs' 'action' 'agent_status' 'path' 'head_sha' 'pipeline_status' \
  "jq -c '.progress'" "jq -c '.errors'"; do
  case "$JQ" in *"$s"*) ;; *) fail "jq 程式碼區塊缺：$s" ;; esac
done
for s in 'logic_map' '每收到一則事件' '類型 6' '類型 2' \
  '沒派出去' '類型 3' 'design.md' 'explore.md' 'grill.md' '「沒寫」' \
  'type 不明' 'subs/' '一輪' 'since your last report'; do
  case "$PROSE" in *"$s"*) ;; *) fail "回報資料從哪來段缺：$s" ;; esac
done
# 反向規則與關鍵規則比對整句，換成別的句子不算
for s in '狀態不從 status.json 拼' '不用 /loop 或 CronCreate' \
  'A card can merge when `mr.state` is `ready`' \
  '類型 2 covers only the cards whose 可以合併 event is in this round'"'"'s input' \
  '沒事不回報'; do
  case "$PROSE" in *"$s"*) ;; *) fail "回報資料從哪來段缺整句：$s" ;; esac
done
# 可合併的判斷跟 coordinate 送「可以合併」一樣看 mr.state，不看 progress_class；同名卡重開時只取活的那張
LM="$(printf '%s\n' "$PROSE" | grep -F '.logic_map')"
case "$LM" in *'mr.state'*'ready'*) ;; *) fail "取 logic_map 那行要以 mr.state ready 判斷 — $LM" ;; esac
case "$LM" in *progress_class*) fail "取 logic_map 那行不能用 progress_class 判斷 — $LM" ;; esac
case "$LM" in *'(.archived | not)'*) ;; *) fail "取 logic_map 那行要排除已歸檔的同名卡 — $LM" ;; esac
# 計數：.progress 只取 milestone，四個數依 section 數
printf '%s\n' "$PROSE" | grep -F '.progress' | grep -qF 'milestone' || fail "取 .progress 那行要寫只取 milestone"
printf '%s\n' "$PROSE" | grep -F '.progress' | grep -qF 'section' || fail "計數要寫依 section 數"
# 沒派出去的卡的 gate：每個 open gate 都看，等的卡合了沒看 workplan，needs: run 進類型 4
GATES="$(printf '%s\n' "$PROSE" | grep -F '沒派出去')"
for s in 'open_gates' 'gates.md' 'waits_on' 'workplan' 'archived' 'needs' '類型 4' 'type 不明'; do
  case "$GATES" in *"$s"*) ;; *) fail "沒派出去的卡的 gate 那行缺：$s — $GATES" ;; esac
done
case "$GATES" in *'opsx-workflow'*'duty 9'*) ;; *) fail "沒派出去的卡的 gate：opsx-workflow 的照職責 9 代答（design D36）— $GATES" ;; esac
case "$GATES" in *'live list'*) fail "等的卡合了沒不能看活卡清單 — $GATES" ;; esac
# .errors 的 glab/gh 是讀不到，不是快取；寫類型 2 前用 opsx mr 重讀
ERR="$(printf '%s\n' "$PROSE" | grep -F '.errors')"
case "$ERR" in *'讀不到'*'opsx mr'*) ;; *) fail ".errors 那行要寫讀不到並用 opsx mr 重讀 — $ERR" ;; esac
case "$ERR" in *cache*|*快取*) fail ".errors 那行不能說成快取 — $ERR" ;; esac
# 重讀也讀不到的卡不進類型 2，只在最後一行寫（design D32）；state none 的卡只在要回報時重讀（design D33）
case "$ERR" in *'leave the card out of 類型 2'*'最後一行'*) ;; *) fail ".errors 那行要寫讀不到的卡不進類型 2、寫在最後一行 — $ERR" ;; esac
case "$ERR" in *"in 類型 2's 狀態"*) fail ".errors 那行不能把讀不到寫進類型 2 的狀態 — $ERR" ;; esac
case "$ERR" in *'asks for a report'*) ;; *) fail ".errors 那行要寫 state none 的卡只在使用者要回報時重讀 — $ERR" ;; esac
case "$ERR" in *'`mr.url`'*'`none`'*) ;; *) fail ".errors 那行要寫有 mr.url 但 state none 的卡也重讀（design D27）— $ERR" ;; esac
case "$ERR" in *'類型 6'*) ;; *) fail ".errors 那行要寫重讀後不是 ready 的卡移出類型 2、用類型 6 報（design D19）— $ERR" ;; esac
case "$GATES" in *'blocks-from:'*) ;; *) fail "沒派出去的卡的 gate 那行要跳過 blocks-from 還沒到站的題（design D21）— $GATES" ;; esac
# agent_status 每個值的意思
AS="$(printf '%s\n' "$PROSE" | grep -F 'agent_status')"
for s in '`idle` 已停' '`done` 已停' '`working` 還在改' '`blocked` 等輸入' '`unknown` pane 不在' '`null` 讀不到' '沒派'; do
  case "$AS" in *"$s"*) ;; *) fail "agent_status 那行缺：$s — $AS" ;; esac
done
# 職責 1 指向這段
printf '%s\n' "$DUTIES" | grep '^1\. ' | grep -qF '回報資料從哪來' || fail "職責 1 要指向「回報資料從哪來」段"

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
