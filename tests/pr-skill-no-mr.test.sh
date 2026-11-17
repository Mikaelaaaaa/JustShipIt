#!/usr/bin/env bash
# skills/pr 處理「workplan mr: none，但 …」的步驟。
# 驗收：openspec/changes/agent-20261116-1640/specs/no-mr-archive/spec.md「/pr 依原因處理 mr: none 的卡」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

S="$OPSX_ROOT/skills/pr/SKILL.md"
assert_grep 'workplan mr: none，但' "$S"
assert_grep '刪掉 workplan 這個 PR 的 `mr: none`' "$S"
assert_grep 'git fetch <primary remote>' "$S"
assert_grep 'decision gate' "$S"
echo "pr-skill-no-mr ok"
