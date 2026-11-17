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
echo "pr-skill-no-mr ok"
