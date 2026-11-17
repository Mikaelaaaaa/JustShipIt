#!/usr/bin/env bash
# skills/pr 的 1b：處理「（workplan mr: <value>，但 <reason>）」。
# 驗收：openspec/changes/agent-20261116-1640/specs/no-mr-archive/spec.md「/pr 依原因處理 mr: none 的卡」；design D8、D9、D10
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

S="$OPSX_ROOT/skills/pr/SKILL.md"
B="$(grep '^1b\. ' "$S")"
[ -n "$B" ] || fail "skills/pr/SKILL.md 沒有 1b 那一段"
has() { case "$B" in *"$1"*) ;; *) fail "1b 缺「$1」" ;; esac; }
before() { # <先> <後>：1b 裡 <先> 出現在 <後> 前面
  local a="${B%%"$1"*}" b="${B%%"$2"*}"
  [ "${#a}" -lt "${#B}" ] && [ "${#b}" -lt "${#B}" ] && [ "${#a}" -lt "${#b}" ] || fail "1b 裡「$1」要在「$2」前面"
}

# D8：觸發字認任何 mr 值
has '（workplan mr: <value>，但 <reason>）'
# 不認得的值與沒寫 branch：不 fetch、直接寫 decision gate
before 'workplan 沒寫 branch' 'git fetch <primary remote>'
# D9 / D10：其他原因先 fetch 再重判，重判後才決定開 MR、刪 mr: none 或改走 archive
before 'git fetch <primary remote>' '刪掉 workplan 這個 PR 的 `mr: none`'
before 'git fetch <primary remote>' '/opsx-workflow:archive <slug>'
has 'type: decision'
# 重判後的兩種結果：count > 0 才開 MR、刪 mr: none；count = 0 才改走 archive
before 'count is above 0' '刪掉 workplan 這個 PR 的 `mr: none`'
before '刪掉 workplan 這個 PR 的 `mr: none`' 'count is 0'
before 'count is 0' '/opsx-workflow:archive <slug>'
# gate 答完照答案改 mr:，卡才不會在 pr 站重複開同一個 gate
has 'set that PR'"'"'s `mr:` to `none`'
has 'delete the `mr:` line'

# archive 第 5 步與 review Step 0 遇到 workplan.yaml: mr: 那行：寫 decision gate，不 split-out、不自己選（design D3、D12）
A="$(grep -n 'workplan.yaml: mr:' "$OPSX_ROOT/skills/archive/SKILL.md")"
case "$A" in *"type: decision"*) ;; *) fail "archive SKILL.md 要說 workplan.yaml: mr: 那行寫 decision gate: [$A]" ;; esac
R="$(grep 'workplan.yaml: mr:' "$OPSX_ROOT/skills/review/SKILL.md")"
case "$R" in *"type: decision"*) ;; *) fail "review SKILL.md 遇到 workplan.yaml: mr: 要寫 decision gate: [$R]" ;; esac
case "$R" in *'(`none`, or delete the line)'*) fail "review SKILL.md 不能讓 agent 自己選 none 或刪掉" ;; esac
echo "pr-skill-no-mr ok"
