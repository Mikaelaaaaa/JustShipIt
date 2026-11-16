#!/usr/bin/env bash
# skills/lead/SKILL.md：協調者的職責與五塊回報格式。specs/opsx-lead/spec.md「協調者 skill 寫明職責與五塊回報格式」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
F="$OPSX_ROOT/skills/lead/SKILL.md"
assert_file "$F"

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
# 只讀「## 怎麼問 gate」到下一個 ## 標題，別段的字不算
ASK="$(sed -n '/^## 怎麼問 gate/,/^## Report format/p' "$F" | sed '$d')"
[ -n "$ASK" ] || fail "找不到「## 怎麼問 gate」段，或它不在 ## Report format 前面"
n_duties="$(line_of '## Duties')"; n_ask="$(line_of '## 怎麼問 gate')"
[ "$n_ask" -gt "$n_duties" ] || fail "「## 怎麼問 gate」要在 ## Duties 後面"
for s in 'AskUserQuestion' '(Recommended)' '最多 4 題' '卡名' '例子' '--grant' \
  'opsx answer' '原文' 'Other' '重講' '不代答' \
  'sketch' 'cards' '沒裝' 'enabledPlugins' 'opsx init --global'; do
  case "$ASK" in *"$s"*) ;; *) fail "怎麼問 gate 段缺：$s" ;; esac
done
# needs: run 的 gate 給指令、不跳卡
printf '%s\n' "$ASK" | grep -F 'needs: run' | grep -qF '指令' || fail "怎麼問 gate 段要寫 needs: run 的 gate 給指令"
# 不替使用者選
case "$ASK" in *自動採用*) fail "怎麼問 gate 段不能有「自動採用」" ;; esac
# 提到 compare 的每一行都是在說不用它選
printf '%s\n' "$ASK" | grep -F 'compare' | grep -vF '不用' && fail "怎麼問 gate 段提到 compare 的行都要含「不用」"
# 職責 2 指向這段
printf '%s\n' "$DUTIES" | grep '^2\. ' | grep -qF '怎麼問 gate' || fail "職責 2 要指向「怎麼問 gate」段"

# frontmatter 的 name 是 lead（/opsx-workflow:lead）
assert_eq "$(sed -n 2p "$F")" "name: lead" "frontmatter name"
echo ok
