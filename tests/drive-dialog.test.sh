#!/usr/bin/env bash
# pane 停在 Claude Code 的信任或權限對話框時，drive 寫 dialog-<n>（needs: run、pane id），不寫 drive-<站>-<n>。
# 驗收：openspec/changes/me-20261117-1421-3/specs/opsx-drive/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FAKES="$OPSX_ROOT/tests/fakes"; mkdir -p "$FX/fakebin"
for f in herdr glab; do printf '#!/usr/bin/env bash\nexec bash "%s/%s" "$@"\n' "$FAKES" "$f" > "$FX/fakebin/$f"; chmod +x "$FX/fakebin/$f"; done
export PATH="$FX/fakebin:$PATH"
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=20

R="$(mk_repo Acmecorp-CS)"; C="$R/openspec/changes/retry-backoff"; mkdir -p "$C" "$OPSX_STATE_DIR"
KL="$FX/kick.log"; : > "$KL"
cat > "$FX/fakebin/opsx" <<EOF
#!/usr/bin/env bash
if [ "\$1" = coordinate ]; then OPSX_FAKE_LOG="$KL" exec bash "$FAKES/opsx" "\$@"; fi
exec bash "$OPSX_ROOT/bin/opsx" "\$@"
EOF
chmod +x "$FX/fakebin/opsx"
printf 'schema: opsx\nkind: bug-fix\n' > "$C/.openspec.yaml"
reset() {
  printf '## 1\n\n- [ ] 1.1 a\n  - 驗收：R1\n  - 測試：t.py\n' > "$C/tasks.md"; rm -f "$C/gates.md" "$C/status.json" "$C/report.md"
  printf '{"Acmecorp-CS/retry-backoff":{"mode":"drive","pane":"w1:p7","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
  : > "$OPSX_FAKE_LOG"; : > "$KL"; : > "$FX/perr"; : > "$FX/werr"
}
# 假 agent 收到指令不動；drive 等 agent 開工時把卡從 dispatch.json 拿掉，drive 就結束
: > "$FX/noop.sh"; export OPSX_TEST_ON_PROMPT="$FX/noop.sh" OPSX_TEST_PROMPT_ERR="$FX/perr" OPSX_TEST_WAIT_ERR="$FX/werr"
cat > "$FX/on_wait.sh" <<EOF
case "\$*" in *"--until working"*) printf '{}' > "$OPSX_STATE_DIR/dispatch.json" ;; esac
EOF
export OPSX_TEST_ON_WAIT="$FX/on_wait.sh"
TRUST='Adding a new directory: /Users/x/.local/state/opsx   This session hasn'"'"'t worked here before. Is this a directory you created or one you trust?   ❯ No, exit    Yes, add it'

gate_block() { awk -v id="## $1" '/^## /{on = ($0 == id)} on' "$C/gates.md"; }

# 認得的畫面：Examples 一般場景與邊界場景每一列
row() { # <畫面文字> <gate id 或 無> <種類 或 無>
  reset; export OPSX_TEST_PANE_TEXT="$1"
  out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive rc（$1）: ${out}"
  if [ "$2" = 無 ]; then assert_no_file "$C/gates.md"; return; fi
  assert_grep "^## $2\$" "$C/gates.md"
  case "$2" in
    dialog-*)
      assert_not_grep '^## drive-' "$C/gates.md"
      gate_block "$2" | grep -q '^needs: run$' || fail "$2 要有 needs: run: $(cat "$C/gates.md")"
      gate_block "$2" | grep -q '^status: open$' || fail "$2 要 open: $(cat "$C/gates.md")"
      gate_block "$2" | grep '^問題:' | grep -qF "w1:p7" || fail "問題要有 pane id: $(cat "$C/gates.md")"
      gate_block "$2" | grep '^問題:' | grep -qF "$3" || fail "問題要有種類 $3（$1）: $(cat "$C/gates.md")"
      gate_block "$2" | grep '^建議:' | grep -qF "到 pane w1:p7 按 Yes" || fail "建議要叫人到 pane 按 Yes: $(cat "$C/gates.md")"
      assert_grep 'opsx coordinate --kick' "$KL" ;;
    *) assert_not_grep '^## dialog-' "$C/gates.md" ;;
  esac
}
row "$TRUST" dialog-1 信任
row "Do you trust this folder?" dialog-1 信任
row "Do you want to proceed?   ❯ 1. Yes" dialog-1 權限
row "Do you want to make this edit to tasks.md?" dialog-1 權限
row "one you trust? ... Do you want to proceed?" dialog-1 信任
row "I trust the tests now" drive-apply-1 無
row "pane 尾巴" drive-apply-1 無
row "1 shell still running" 無 無

# 舊的 dialog-1 答過了：再遇到時寫 dialog-2
reset; export OPSX_TEST_PANE_TEXT="$TRUST"
printf '## dialog-1\ntype: decision\nneeds: run\nstatus: answered\nanswer: ok\n' > "$C/gates.md"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive rc: ${out}"
assert_grep '^## dialog-2$' "$C/gates.md"
gate_block dialog-2 | grep -q '^status: open$' || fail "dialog-2 要 open: $(cat "$C/gates.md")"

# herdr 回 agent_blocked、畫面是對話框：寫 dialog-1 再等
reset; export OPSX_TEST_PANE_TEXT="Do you want to proceed?"; printf 'agent_blocked\n' > "$FX/werr"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive blocked rc: ${out}"
assert_grep '^## dialog-1$' "$C/gates.md"
gate_block dialog-1 | grep -q '^needs: run$' || fail "blocked 的 dialog-1 要有 needs: run: $(cat "$C/gates.md")"
assert_grep 'agent wait retry-backoff --until working' "$OPSX_FAKE_LOG"

# agent_blocked 但不是對話框：不寫 gate
reset; export OPSX_TEST_PANE_TEXT="pane 尾巴"; printf 'agent_blocked\n' > "$FX/werr"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive blocked rc: ${out}"
assert_no_file "$C/gates.md"

# 已有 open 的 dialog-1：agent_blocked 再來也不重寫
reset; export OPSX_TEST_PANE_TEXT="$TRUST"; printf 'agent_blocked\n' > "$FX/werr"
printf '## dialog-1\ntype: decision\nneeds: run\nstatus: open\n' > "$C/gates.md"
out="$(opsx drive retry-backoff --repo "$R" 2>&1)"; assert_eq "$?" 0 "drive dup rc: ${out}"
assert_eq "$(grep -c '^## dialog-' "$C/gates.md")" 1 "dialog gate 不重寫: $(cat "$C/gates.md")"

# gaterule：dialog-1 是要人跑的題，drive-apply-1 仍是卡住題
got="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import gaterule
w = {"gate_id": "dialog-1", "needs": "run", "type": "等待決定"}
s = {"gate_id": "drive-apply-1", "needs": None, "type": "等待決定"}
print(gaterule.decide(w), gaterule.decide(s))' "$OPSX_ROOT/bin/lib")"
assert_eq "$got" "('human', 'run') ('human', 'stuck')" "gaterule 判斷"
echo "drive-dialog ok"
