#!/usr/bin/env bash
# SessionStart：協調者每次啟動把 opsx-coordinator 掛回自己的 pane；身分檔由 coordinate 與 opsx lead 寫，hook 只讀。
# specs/opsx-lead/spec.md 的「SessionStart 不寫身分檔」「resume 後把名字掛回新 pane」「名字被別的 pane 佔著不搶」。
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
reset() {
  : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
  unset OPSX_TEST_COORDINATOR_UP OPSX_TEST_COORD_PANE OPSX_TEST_COORD_STATUS OPSX_TEST_RENAME_FAIL OPSX_TEST_AGENT_GET_ERR OPSX_TEST_AGENT_GET_RAW
}
remember() { printf '{"session_id":"%s","pane":"%s"}\n' "$1" "$2" > "$J"; }
context() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext'; }

# --- SessionStart 不寫身分檔：不是協調者的 session 不呼叫 herdr ---
reset; remember s1 w3:p7; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w1:p2
out="$(start w1:p2 s2 startup)"; assert_eq "$?" 0 "別的 session rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "別的 session 不叫 herdr"
assert_eq "$(cat "$J")" '{"session_id":"s1","pane":"w3:p7"}' "身分檔不變"

# --- 沒有身分檔：就算名字在自己的 pane 也不寫、不叫 herdr ---
reset; rm -f "$J"; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w3:p7 s1 startup)"; assert_eq "$?" 0 "沒有身分檔 rc"
assert_no_file "$J"; assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒有身分檔不叫 herdr"

# --- 不在 herdr pane 裡不呼叫 herdr ---
reset; remember s1 w9:p8
out="$(start "" s1 resume)"; assert_eq "$?" 0 "不在 herdr rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "不在 herdr 不叫 herdr"

# --- 身分檔讀不懂：說出來，不叫 herdr ---
reset; printf 'not json' > "$J"
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "壞身分檔 rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "壞身分檔不叫 herdr"
case "$out" in *coordinator.json*) ;; *) fail "要說身分檔壞了：$out" ;; esac

# --- resume 後把名字掛回新 pane（Outline：resume / startup / clear / compact）；hook 不寫身分檔 ---
for src in resume startup clear compact; do
  reset; remember s1 w9:p8
  out="$(start w9:pM s1 "$src")"; assert_eq "$?" 0 "$src rc"
  assert_grep '^agent rename w9:pM opsx-coordinator$' "$OPSX_FAKE_LOG"
  assert_eq "$(cat "$J")" '{"session_id":"s1","pane":"w9:p8"}' "${src}：hook 不寫身分檔"
done

# --- 名字已在自己 pane 上不重掛 ---
reset; remember s1 w3:p7; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7
out="$(start w3:p7 s1 resume)"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"

# --- 佔著的 pane 狀態決定搶不搶（Outline：working / idle / blocked / done 不搶，unknown 改名） ---
for st in working idle blocked done; do
  reset; remember s1 w9:p8; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7 OPSX_TEST_COORD_STATUS="$st"
  out="$(start w9:pM s1 resume)"
  assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
  case "$(context "$out")" in *w3:p7*opsx-coordinator*|*opsx-coordinator*w3:p7*) ;; *) fail "${st}：context 要寫出佔著的 pane：$out" ;; esac
done
reset; remember s1 w9:p8; export OPSX_TEST_COORDINATOR_UP=1 OPSX_TEST_COORD_PANE=w3:p7 OPSX_TEST_COORD_STATUS=unknown
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "佔著的 pane 沒在跑 agent rc"
assert_grep '^agent rename w9:pM opsx-coordinator$' "$OPSX_FAKE_LOG"

# --- 沒給 pane id 時說查不到，不說兩個協調者 ---
reset; remember s1 w9:p8; export OPSX_TEST_AGENT_GET_RAW='{"result":{"agent":{"agent_status":"idle"}}}'
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "沒給 pane id rc"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
ctxt="$(context "$out")"
case "$ctxt" in *查不到*) ;; *) fail "沒給 pane id 要說查不到：$out" ;; esac
case "$ctxt" in *兩個協調者*) fail "沒給 pane id 不說兩個協調者：$out" ;; esac

# --- agent get 回的不是 JSON：hook 以 0 結束、不改名 ---
reset; remember s1 w9:p8; export OPSX_TEST_AGENT_GET_RAW='not json'
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "agent get 不是 JSON rc"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"

# --- rename 失敗時說出 herdr 的錯（錯誤碼跟 agent get 的 agent_not_found 不同，才分得出是哪一步） ---
reset; remember s1 w9:p8; export OPSX_TEST_RENAME_FAIL=rename_denied
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "rename 失敗 hook 仍以 0 結束"
case "$(context "$out")" in *rename_denied*) ;; *) fail "context 要帶 rename 的錯誤碼：$out" ;; esac

# --- herdr 叫不通（agent get 回別的錯）：不改名、hook 以 0 結束、說出錯誤 ---
reset; remember s1 w9:p8; export OPSX_TEST_AGENT_GET_ERR=socket_unavailable
out="$(start w9:pM s1 resume)"; assert_eq "$?" 0 "herdr 叫不通 rc"
assert_not_grep '^agent rename' "$OPSX_FAKE_LOG"
case "$out" in *socket_unavailable*) ;; *) fail "context 要帶 herdr 的錯：$out" ;; esac

# --- hooks.json 掛在 SessionStart ---
jq -e '.hooks.SessionStart[].hooks[] | select(.command | contains("opsx-coordinator-attach.sh"))' "$H/hooks.json" >/dev/null || fail "hooks.json 的 SessionStart 要掛 opsx-coordinator-attach.sh"
echo ok
