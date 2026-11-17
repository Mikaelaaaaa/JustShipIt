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
  '建議合併順序' \
  '| # | 卡 | 問什麼 | 你的回答 |' \
  '| 卡 | 為什麼我做不到 | 指令 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '一到三行' '最後一行' 'logic-map.md' 'report.md' \
  '表格外' '一行一條' '絕對路徑' 'path:line'; do
  case "$REPORT" in *"$s"*) ;; *) fail "Report format 缺：$s" ;; esac
done
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
for s in 'explore' '不問' '要不要開卡'; do
  case "$NEWCARD" in *"$s"*) ;; *) fail "開卡職責缺：$s — $NEWCARD" ;; esac
done
SELFDO="$(printf '%s\n' "$DUTIES" | grep '^[0-9]*\. ' | grep -F 'push' | grep -F '類型 4')"
[ -n "$SELFDO" ] || fail "Duties 缺「做得到的自己做，做不到照類型 4 給指令」的職責"
case "$SELFDO" in *MR*) ;; *) fail "自己做的職責缺 MR — $SELFDO" ;; esac
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
  || fail "「## 回報資料從哪來」要在 ## 怎麼問 gate（$n_ask）與 ## Report format（$n_report）之間，現在在 $n_src"
for s in 'opsx collect' 'jq' 'logic_map' '.progress' 'dispatched' '每收到一則事件' '類型 6' '類型 2' \
  '沒派出去' '類型 3' 'design.md' 'explore.md' 'grill.md' '「沒寫」'; do
  case "$SRC" in *"$s"*) ;; *) fail "回報資料從哪來段缺：$s" ;; esac
done
# 狀態不從 status.json 拼；不自己排計時器
printf '%s\n' "$SRC" | grep -F 'status.json' | grep -qF '不' || fail "回報資料從哪來段要寫明狀態不從 status.json 拼"
printf '%s\n' "$SRC" | grep -F '/loop' | grep -F 'CronCreate' | grep -qF '不' || fail "回報資料從哪來段要寫明不用 /loop 或 CronCreate 自己排"
# 職責 1 指向這段
printf '%s\n' "$DUTIES" | grep '^1\. ' | grep -qF '回報資料從哪來' || fail "職責 1 要指向「回報資料從哪來」段"

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
