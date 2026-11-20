#!/usr/bin/env bash
# SessionStart：協調者每次啟動把 opsx-coordinator 掛回自己的 pane。specs/opsx-lead/spec.md 的三條 SessionStart Requirement。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/herdr.log"
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"
J="$OPSX_STATE_DIR/coordinator.json"
mkdir -p "$OPSX_STATE_DIR"

start() { # <pane 或空> <session_id> <source>
  printf '{"cwd":"%s","session_id":"%s","source":"%s","hook_event_name":"SessionStart"}' "$FX" "$2" "$3" \
    | HERDR_PANE_ID="$1" bash "$H/opsx-coordinator-attach.sh"
}
reset() { : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"; unset OPSX_TEST_COORDINATOR_UP OPSX_TEST_COORD_PANE OPSX_TEST_RENAME_FAIL; }
remember() { printf '{"session_id":"%s","pane":"%s","at":"2026-11-20T10:00:00+08:00"}\n' "$1" "$2" > "$J"; }
field() { jq -r ".$1" "$J"; }

# --- 首次啟動記下協調者 session（正例） ---
reset; rm -f "$J"; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w3:p7 s1 startup)"; assert_eq "$?" 0 "首次啟動 rc"
assert_eq "$(field session_id) $(field pane)" "s1 w3:p7" "記下協調者 session"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"

# --- 別的 pane 的 session 不記（反例） ---
reset; rm -f "$J"; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w1:p2 s9 startup)"
assert_no_file "$J"; assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"

# --- resume 時對不上的 session 不查名字也不記：只有 startup 才可能是剛起的協調者 ---
reset; rm -f "$J"; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w3:p7 s1 resume)"
assert_no_file "$J"; assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "resume 且沒有身分檔不叫 herdr"

# --- 不在 herdr pane 裡不呼叫 herdr（反例） ---
reset; remember s1 w9:p8
out="$(start "" s1 resume)"; assert_eq "$?" 0 "不在 herdr rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "不在 herdr 不叫 herdr"

# --- resume 後把名字掛回新 pane（Outline：resume / startup / clear / compact） ---
for src in resume startup clear compact; do
  reset; remember s1 w9:p8
  out="$(start w9:pM s1 "$src")"; assert_eq "$?" 0 "$src rc"
  assert_grep '^agent rename w9:pM opsx-coordinator$' "$OPSX_FAKE_LOG"
  assert_eq "$(field session_id) $(field pane)" "s1 w9:pM" "${src}：pane 更新成新的"
done

# --- 不是協調者的 session 不改名（反例） ---
reset; remember s1 w9:p8
out="$(start w1:p2 s2 resume)"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
assert_eq "$(field session_id) $(field pane)" "s1 w9:p8" "身分檔不變"

# --- 名字已在自己 pane 上不重掛（反例） ---
reset; remember s1 w3:p7; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w3:p7 s1 resume)"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"

# --- 名字被別的 pane 佔著不搶（正例） ---
reset; remember s1 w9:p8; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w9:pM s1 resume)"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
ctxt="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctxt" in *w3:p7*opsx-coordinator*|*opsx-coordinator*w3:p7*) ;; *) fail "context 要寫出佔著的 pane：$out" ;; esac
assert_eq "$(field pane)" "w9:p8" "佔著時身分檔不變"

# --- rename 失敗時說出 herdr 的錯（反例） ---
reset; remember s1 w9:p8; export OPSX_TEST_RENAME_FAIL=1
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "rename 失敗 hook 仍以 0 結束"
ctxt="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctxt" in *agent_not_found*) ;; *) fail "context 要帶 herdr 的錯誤碼：$out" ;; esac
assert_eq "$(field pane)" "w9:p8" "rename 失敗 pane 不變"

# --- herdr 叫不通（agent get 回別的錯）：不改名、hook 以 0 結束、說出錯誤 ---
reset; remember s1 w9:p8; export OPSX_TEST_AGENT_GET_ERR=socket_unavailable
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "herdr 叫不通 rc"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
case "$out" in *socket_unavailable*) ;; *) fail "context 要帶 herdr 的錯：$out" ;; esac
unset OPSX_TEST_AGENT_GET_ERR

# --- 身分檔壞掉：不改名，說出來 ---
reset; printf 'not json' > "$J"
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "壞身分檔 rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "壞身分檔不叫 herdr"
case "$out" in *coordinator.json*) ;; *) fail "要說身分檔壞了：$out" ;; esac

# --- hooks.json 掛在 SessionStart ---
jq -e '.hooks.SessionStart[].hooks[] | select(.command | contains("opsx-coordinator-attach.sh"))' "$H/hooks.json" >/dev/null || fail "hooks.json 的 SessionStart 要掛 opsx-coordinator-attach.sh"
echo ok
