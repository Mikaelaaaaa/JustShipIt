#!/usr/bin/env bash
# skills/lead/SKILL.md：協調者的職責與五塊回報格式。specs/opsx-lead/spec.md「協調者 skill 寫明職責與五塊回報格式」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$OPSX_ROOT/skills/lead/SKILL.md"
assert_file "$F"

# babysit 之後 MR 全綠卻沒標可以合併時 Stop hook 推的兩行（me-20261117-1421），協調者要查得到
grep -qF '停住：babysit 做完，邏輯表不是 MR 最新 head' "$F" || fail "skill 缺新推送：邏輯表不是 MR 最新 head"
grep -qF '停住：babysit 做完，report.md 有留給人決定的項目' "$F" || fail "skill 缺新推送：report.md 有留給人決定的項目"
! grep -qF 'only three states stay silent: the MR is ready (coordinate sends 可以合併)' "$F" || fail "MR ready 不再一律靜音"

# 五塊依序出現
line_of() { grep -nF -- "$1" "$F" | head -1 | cut -d: -f1; }
prev=0
for h in '① 要你處理' '② 可合併（依序）' '③ 進度' '④ 我處理掉的' '⑤ 最後一行'; do
  n="$(line_of "$h")"; [ -n "$n" ] || fail "缺區塊標題：$h"
  [ "$n" -gt "$prev" ] || fail "區塊順序錯：$h 在第 $n 行，前一塊在第 $prev 行"
  prev="$n"
done

# 每塊的欄名
for s in \
  '| # | 卡 | 問什麼 | 我的建議 | 詳情 |' \
  '→ 回『1 照建議』即可' \
  '| # | 功能 | PR | 卡 | 測試 | 邏輯表 | PR 連結 |' \
  '進度 HH:MM · <current_milestone>：剩 N 張 · 可合併 a · 測試中 b · 開發中 c · 等你 d · 還沒派 e' \
  '| 功能（session） | 卡 | 優先度 | 階段 | 卡在 |' \
  '| 卡 | 發生什麼 | 我怎麼處理 | 開卡 |' \
  '絕對路徑' 'path:line' '絕不合併' 'me-20261111-1315' 'logic-map.md' 'report.md'; do
  grep -qF -- "$s" "$F" || fail "skill 缺：$s"
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
for s in '同一件事' '只併小事' 'decisions.tsv' '④' 'kind_of_work' 'impact'; do
  case "$DEDUP" in *"$s"*) ;; *) fail "去重職責缺：$s — $DEDUP" ;; esac
done

# 怎麼問 gate（specs/opsx-lead「協調者用跳卡問 gate」「跳卡不代答」「有 sketch 外掛時先畫 cards」）：
# 只讀「## 怎麼問 gate」到下一個 ## 標題，別段的字不算；標題要夾在 ## Duties 與 ## Report format 之間
ASK="$(awk '/^## 怎麼問 gate/{f=1;next} f&&/^## /{exit} f' "$F")"
[ -n "$ASK" ] || fail "找不到「## 怎麼問 gate」段"
heading_of() { grep -n "^$1\$" "$F" | head -1 | cut -d: -f1; }
n_duties="$(heading_of '## Duties')"; n_ask="$(heading_of '## 怎麼問 gate')"; n_report="$(heading_of '## Report format')"
[ -n "$n_ask" ] && [ "$n_ask" -gt "$n_duties" ] && [ "$n_ask" -lt "$n_report" ] \
  || fail "「## 怎麼問 gate」要在 ## Duties（$n_duties）與 ## Report format（$n_report）之間，現在在 ${n_ask:-沒有}"
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

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
