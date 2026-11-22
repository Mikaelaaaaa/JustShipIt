#!/usr/bin/env bash
# Stop hook：dispatch 把卡標成 stopped（人按了停止）時放行，不擋、不計次、不開「卡在接」gate；其他模式照擋。
# 驗收：specs/stop-gate/spec.md（dispatch 標 stopped 的卡放行）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI)"
mkdir -p "$R/openspec/changes/archive"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 1. x\n\n- [x] 1.1 a\n- [ ] 1.2 b\n' > "$C/tasks.md"
mode() { printf '{"Acmecorp-AI/eval-core":{"mode":"%s","pane":"w1:p1"}}' "$1" > "$OPSX_STATE_DIR/dispatch.json"; }
mkdir -p "$FX/cbin"
printf '#!/usr/bin/env bash\nexec bash "%s/tests/fakes/herdr" "$@"\n' "$OPSX_ROOT" > "$FX/cbin/herdr"; chmod +x "$FX/cbin/herdr"
stop() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | PATH="$FX/cbin:$PATH" OPSX_FAKE_LOG="$FX/coord.log" OPSX_TEST_COORDINATOR_UP=1 bash "$H/openspec-stop-gate.sh" 2>/dev/null; }
blocked() { [ "$(printf '%s' "$1" | jq -r '.decision // "allow"')" = block ]; }

# 標 stopped：連停 5 次（超過 MAX_BLOCKS）都放行，不寫 gates.md、不留擋停次數
mode stopped
for i in 1 2 3 4 5; do
  out="$(stop)"; assert_eq "$?" 0 "stopped 第 $i 次以 0 結束"
  [ -z "$out" ] || fail "stopped 第 $i 次要放行：$out"
done
assert_no_file "$C/gates.md"
assert_no_file "$OPSX_STATE_DIR/stop-chain/Acmecorp-AI-eval-core"

# 反例：autopilot 照擋，原因是 tasks.md 還有沒勾的 task
mode autopilot
out="$(stop)"; blocked "$out" || fail "autopilot 要照擋：$out"
printf '%s' "$out" | jq -r '.reason' | grep -q 'task 沒勾' || fail "擋停原因要提到沒勾的 task：$out"
echo ok
