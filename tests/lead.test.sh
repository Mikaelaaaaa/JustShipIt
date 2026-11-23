#!/usr/bin/env bash
# opsx lead：用假 herdr 驗開協調者的呼叫與參數。specs/opsx-lead/spec.md。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DISPATCH_RETRY_SLEEP=0
S="$OPSX_STATE_DIR/coordinator-settings.json"
mkdir -p "$FX/repo"; cd "$FX/repo"

# --- 不在 herdr 報錯：不碰 herdr ---
out="$(HERDR_ENV="" opsx lead 2>&1)"; [ $? -ne 0 ] || fail "不在 herdr 要非 0：$out"
case "$out" in *herdr*) ;; *) fail "錯誤訊息要說 herdr：$out" ;; esac
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "不在 herdr 不該叫 herdr"

# --- HERDR_ENV 有值但沒有 HERDR_WORKSPACE_ID：報錯，不碰 herdr ---
out="$(HERDR_ENV=1 HERDR_WORKSPACE_ID="" opsx lead 2>&1)"; [ $? -ne 0 ] || fail "沒有 workspace id 要非 0：$out"
case "$out" in *HERDR_WORKSPACE_ID*) ;; *) fail "錯誤訊息要點名 HERDR_WORKSPACE_ID：$out" ;; esac
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒有 workspace id 不該叫 herdr"

export HERDR_ENV=1 HERDR_WORKSPACE_ID=w5

# --- 多給參數：退出 2 ---
assert_rc 2 opsx lead "$FX/repo" extra

# --- 設定檔不存在：叫人跑 init --global，不開 tab ---
out="$(opsx lead 2>&1)"; [ $? -ne 0 ] || fail "沒有設定檔要非 0：$out"
case "$out" in *"opsx init --global"*) ;; *) fail "要叫人跑 opsx init --global：$out" ;; esac
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"

printf '{"sandbox":{}}\n' > "$S"

# --- 在 fake herdr 下開協調者 ---
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(opsx lead 2>&1)"; assert_eq "$?" 0 "lead rc：$out"
assert_grep "^tab create --workspace w5 --cwd $(pwd -P) --label opsx-coordinator" "$OPSX_FAKE_LOG"
assert_grep "^agent start opsx-coordinator --kind claude --pane w1:pE -- --settings $S --add-dir $OPSX_STATE_DIR\$" "$OPSX_FAKE_LOG"
assert_not_grep 'permission-mode' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt opsx-coordinator /opsx-workflow:lead$' "$OPSX_FAKE_LOG"
assert_grep '^agent focus opsx-coordinator$' "$OPSX_FAKE_LOG"
assert_eq "$(grep -c '^agent focus' "$OPSX_FAKE_LOG")" 1 "焦點只切一次"
# 順序：開 tab、起 agent、送第一句、切焦點
grep -oE '^(tab create|agent start|agent prompt|agent focus)' "$OPSX_FAKE_LOG" | tr '\n' '|' > "$FX/order"
assert_eq "$(cat "$FX/order")" "tab create|agent start|agent prompt|agent focus|" "呼叫順序"
# 起好就記下協調者 session（specs/opsx-lead「coordinate 與 opsx lead 記下協調者 session」）
assert_eq "$(cat "$OPSX_STATE_DIR/coordinator.json")" '{"session_id": "sess-1"}' "lead 要記下協調者 session"
rm -f "$OPSX_STATE_DIR/coordinator.json"
# herdr 還沒給 session id：印警告、不寫檔、仍以 0 結束
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_AGENT_GET_RAW='{"result":{"agent":{"pane_id":"w3:p7"}}}' opsx lead 2>&1)"
assert_eq "$?" 0 "記不到 session id 仍要 0：$out"
case "$out" in *"下一輪會補記"*) ;; *) fail "記不到要警告：$out" ;; esac
assert_no_file "$OPSX_STATE_DIR/coordinator.json"

# --- 給 repo 路徑 ---
mkdir -p "$FX/other"; : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(opsx lead "$FX/other" 2>&1)"; assert_eq "$?" 0 "lead <path> rc：$out"
assert_grep "^tab create --workspace w5 --cwd $(cd "$FX/other" && pwd -P) " "$OPSX_FAKE_LOG"
assert_rc 2 opsx lead "$FX/nope"

# --- 協調者已在跑：印它在哪，不開第二個 ---
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_COORDINATOR_UP=1 opsx lead 2>&1)"; assert_eq "$?" 0 "已在跑要退出 0：$out"
case "$out" in *w3:p7*) ;; *) fail "要印出它的 pane：$out" ;; esac
case "$out" in *w3:t2*) ;; *) fail "要印出它的 tab：$out" ;; esac
assert_grep '^agent get opsx-coordinator$' "$OPSX_FAKE_LOG"
assert_not_grep '^tab create' "$OPSX_FAKE_LOG"
assert_not_grep '^agent start' "$OPSX_FAKE_LOG"
# 上面幾次 lead 起協調者時記了指紋，之後參數與設定都沒變：只說已在跑
case "$out" in *關掉*) fail "指紋一致不該叫人關掉：$out" ;; esac

# --- 協調者的指紋：啟動時記下；已在跑時參數或設定變了、或沒有記錄，要說哪樣並叫人關掉重開 ---
F="$OPSX_STATE_DIR/coordinator-launch.cksum"
rm -f "$F"; : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(opsx lead 2>&1)"; assert_eq "$?" 0 "lead rc：$out"
assert_file "$F"
# 兩行要對得上這次真的帶給 agent start 的參數和設定檔內容，不然參數改了指紋也不會變
started="$(sed -n 's/^agent start opsx-coordinator .* -- //p' "$OPSX_FAKE_LOG")"
[ -n "$started" ] || fail "fake herdr 記錄裡找不到 agent start 的參數"
assert_eq "$(grep '^args ' "$F")" "args $(printf '%s' "$started" | cksum)" "args 行要是實際啟動參數的 cksum"
assert_eq "$(grep '^settings ' "$F")" "settings $(cksum < "$S")" "settings 行要是設定檔內容的 cksum"
cp "$F" "$FX/launch.orig"
cp "$S" "$FX/settings.orig"
stale_ok() { # <情境> <要有的字> <不該有的字>
  : > "$OPSX_FAKE_LOG"
  out="$(OPSX_TEST_COORDINATOR_UP=1 opsx lead 2>&1)"; assert_eq "$?" 0 "$1 要退出 0：$out"
  case "$out" in *w3:p7*) ;; *) fail "$1：要印出它的 pane：$out" ;; esac
  case "$out" in *"$2"*) ;; *) fail "$1：要說 $2：$out" ;; esac
  case "$out" in *關掉*"opsx lead"*) ;; *) fail "$1：要叫人關掉再跑 opsx lead：$out" ;; esac
  [ -z "$3" ] || case "$out" in *"$3"*) fail "$1：不該說 $3：$out" ;; esac
  assert_not_grep '^tab create' "$OPSX_FAKE_LOG"
  assert_not_grep '^agent start' "$OPSX_FAKE_LOG"
}
# 參數寫死在 lead.sh，測試換不了，改記下的那一行模擬「起它時的參數跟現在不同」
sed 's/^args .*/args 0 0/' "$FX/launch.orig" > "$F"
stale_ok "啟動參數變了" 啟動參數 coordinator-settings.json
cp "$FX/launch.orig" "$F"; printf '{"sandbox":{"x":1}}\n' > "$S"
stale_ok "設定變了" coordinator-settings.json 啟動參數
sed 's/^args .*/args 0 0/' "$FX/launch.orig" > "$F"
stale_ok "兩樣都變" 啟動參數 ""
case "$out" in *coordinator-settings.json*) ;; *) fail "兩樣都變要兩樣都說：$out" ;; esac
cp "$FX/settings.orig" "$S"; rm -f "$F"
stale_ok "沒有指紋檔" 啟動記錄 ""
# 名字被占用那條不比對指紋：另一個是剛起的
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_START_FAIL=agent_name_taken opsx lead 2>&1)"; assert_eq "$?" 0 "name taken 要退出 0：$out"
case "$out" in *啟動記錄*|*關掉*) fail "名字被占用不該比對指紋：$out" ;; esac
# 指紋檔寫不進去：警告一行，協調者照常開好
mkdir "$F"; : > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(opsx lead 2>&1)"; assert_eq "$?" 0 "指紋寫不進去仍要 0：$out"
case "$out" in *指紋*) ;; *) fail "指紋寫不進去要警告：$out" ;; esac
assert_grep '^agent start opsx-coordinator ' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt opsx-coordinator /opsx-workflow:lead$' "$OPSX_FAKE_LOG"
rmdir "$F"
# 第一句送不進去時協調者已經用這次的設定起來，指紋要已換成這次的，不能留著上一次的
sed 's/^settings .*/settings 0 0/' "$FX/launch.orig" > "$F"
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
echo agent_not_ready > "$FX/coord-err"
out="$(OPSX_TEST_COORD_ERR="$FX/coord-err" opsx lead 2>&1)"; [ $? -ne 0 ] || fail "第一句送不進去要非 0：$out"
assert_eq "$(grep '^settings ' "$F")" "settings $(cksum < "$S")" "第一句失敗也要記下這次的指紋"
# 設定檔讀不出來算不出指紋：刪掉舊的，下次走「沒有啟動記錄」，不留空檔或舊檔
cp "$FX/launch.orig" "$F"; chmod 000 "$S"
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(opsx lead 2>&1)"; assert_eq "$?" 0 "算不出指紋仍要 0：$out"
chmod 644 "$S"
case "$out" in *指紋*) ;; *) fail "算不出指紋要警告：$out" ;; esac
assert_no_file "$F"

# --- start 回 agent_name_taken（兩個 lead 同時跑；或 get 查不到但其實在跑）：已在跑不是錯誤 ---
# 關掉剛開的 tab、印出另一個在哪、退出 0；不能叫人關掉那個 pane（那就是正在跑的協調者）
name_taken_ok() { # <情境>
  echo "$out" | grep -q 'pane_id=w9:p1' || fail "$1：要印出同名 agent 在哪：$out"
  case "$out" in *已在跑*) ;; *) fail "$1：要說協調者已在跑：$out" ;; esac
  case "$out" in *關掉那個*) fail "$1：不能叫人關掉正在跑的協調者：$out" ;; esac
  assert_grep '^tab close w1:tB$' "$OPSX_FAKE_LOG"
  assert_not_grep '^agent prompt' "$OPSX_FAKE_LOG"
}
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_START_FAIL=agent_name_taken opsx lead 2>&1)"; assert_eq "$?" 0 "name taken 要退出 0：$out"
name_taken_ok "兩個 lead 同時跑"
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_AGENT_GET_ERR=socket_unreachable OPSX_TEST_START_FAIL=agent_name_taken opsx lead 2>&1)"; assert_eq "$?" 0 "get 失敗加 name taken 要退出 0：$out"
name_taken_ok "get 失敗但協調者在跑"

# --- 查協調者失敗時照常開：agent get 的真錯誤碼與輸出都沒樣本，查不到或讀不出位置就交給 agent start 的名字唯一性 ---
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_AGENT_GET_ERR=socket_unreachable opsx lead 2>&1)"; assert_eq "$?" 0 "agent get 失敗仍要開：$out"
assert_grep '^tab create' "$OPSX_FAKE_LOG"
assert_grep '^agent start opsx-coordinator ' "$OPSX_FAKE_LOG"
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_AGENT_GET_RAW='{"result":{"agent":{"name":"opsx-coordinator"}}}' opsx lead 2>&1)"; assert_eq "$?" 0 "get 成功但讀不出位置仍要開：$out"
assert_grep '^tab create' "$OPSX_FAKE_LOG"
assert_grep '^agent start opsx-coordinator ' "$OPSX_FAKE_LOG"

# --- tab create 沒回 tab id：報錯（不然失敗時關不掉剛開的 tab） ---
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
out="$(OPSX_TEST_TAB_NO_TAB=1 opsx lead 2>&1)"; [ $? -ne 0 ] || fail "沒有 tab id 要非 0：$out"
assert_not_grep '^agent start' "$OPSX_FAKE_LOG"

# --- 第一句送不進去：非 0，叫人在那個 pane 自己打 /opsx-workflow:lead ---
: > "$OPSX_FAKE_LOG"; rm -f "$OPSX_FAKE_LOG.coordinator-up"
echo agent_not_ready > "$FX/coord-err"
out="$(OPSX_TEST_COORD_ERR="$FX/coord-err" opsx lead 2>&1)"; [ $? -ne 0 ] || fail "第一句送不進去要非 0：$out"
case "$out" in *"/opsx-workflow:lead"*w1:pE*|*w1:pE*"/opsx-workflow:lead"*) ;; *) fail "要叫人在 pane w1:pE 打 /opsx-workflow:lead：$out" ;; esac

echo ok
