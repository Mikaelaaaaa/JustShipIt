#!/usr/bin/env bash
# 討論卡（派工指示含「做到 propose 完成就停」）propose 完、一個 task 都沒勾時 Stop hook 放行；其他照擋。
# 驗收：openspec/changes/coordinate-discussion-cards/specs/coordinate-discussion-cards/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
C="$R/openspec/changes/talk"; mk_change "$R" talk
printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
N='做到 propose 完成就停（留在待指派），不要 apply'
sg() { rm -rf "$STOP_STATE"; printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
decision() { [ -z "$1" ] && { echo allow; return; }; printf '%s' "$1" | jq -r '.decision // "allow"'; }
inbox() { # [指示]：沒給就沒有 ## 派工指示 段
  printf '## 一句話\n\n討論\n' > "$C/inbox.md"
  [ -z "${1:-}" ] || printf '\n## 派工指示\n\n- 2026-11-17T10:00 %s\n\n## 其他\n\n- x\n' "$1" >> "$C/inbox.md"
}
tasks() { # <勾了幾個>：3 個 task
  local i; : > "$C/tasks.md"
  for i in 1 2 3; do
    if [ "$i" -le "$1" ]; then printf -- '- [x] 1.%s t\n' "$i"; else printf -- '- [ ] 1.%s t\n' "$i"; fi >> "$C/tasks.md"
  done
}
blocked_to_apply() { # <這一列的名字> <hook 輸出>
  assert_eq "$(decision "$2")" block "$1：要擋: $2"
  printf '%s' "$2" | jq -r '.reason' | grep -q '/opsx-workflow:apply' || fail "$1：理由要叫接 /opsx-workflow:apply: $2"
}

# --- propose 完的討論卡可以停（正例）---
inbox "$N"; tasks 0; rm -f "$C/gates.md"
out="$(sg)"; assert_eq "$(decision "$out")" allow "帶指示、0 個勾了要放行: $out"

# --- 已開始 apply 的討論卡照擋（反例）---
inbox "$N"; tasks 1; out="$(sg)"; blocked_to_apply "帶指示、勾了 1 個" "$out"
inbox; tasks 0; out="$(sg)"; blocked_to_apply "沒有派工指示段、0 個勾了" "$out"
inbox "$N"; tasks 2; out="$(sg)"; blocked_to_apply "帶指示、勾了 2 個" "$out"
# 指示寫在 ## 派工指示 段外面不算
printf '## 一句話\n\n%s\n\n## 派工指示\n\n- 2026-11-17T10:00 先看 review\n' "$N" > "$C/inbox.md"; tasks 0
out="$(sg)"; blocked_to_apply "指示在段外" "$out"
echo "stop-gate-discussion-cards ok"
