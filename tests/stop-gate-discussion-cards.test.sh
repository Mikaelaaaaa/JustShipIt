#!/usr/bin/env bash
# 討論卡（派工指示含「做到 propose 完成就停」）propose 完、一個 task 都沒勾時，Stop hook 跟其他卡一樣擋，叫它在同一個 pane 接 apply（design D8）。
# 驗收：openspec/changes/coordinate-discussion-cards/design.md D8
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
C="$R/openspec/changes/talk"; mk_change "$R" talk
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf -- '- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$C/tasks.md"
printf '## 一句話\n\n討論\n\n## 派工指示\n\n- 2026-11-17T10:00 做到 propose 完成就停（留在待指派），不要 apply\n' > "$C/inbox.md"
rm -rf "$OPSX_STATE_DIR/stop-chain"
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null)" || true
assert_eq "$(printf '%s' "$out" | jq -r '.decision // "allow"')" block "帶指示、0 個勾了、沒有 gate 要擋: $out"
printf '%s' "$out" | jq -r '.reason' | grep -q '/opsx-workflow:apply' || fail "理由要叫接 /opsx-workflow:apply: $out"
echo "stop-gate-discussion-cards ok"
