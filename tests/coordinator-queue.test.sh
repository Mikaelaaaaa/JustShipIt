#!/usr/bin/env bash
# bin/lib/coordq.py：事件送協調者前看輸入框，有字排隊，空了合成一則送出。
# 驗收：openspec/changes/me-20261116-1130/specs/opsx-coordinate/spec.md「協調者輸入框有字時事件排隊，空了合成一則送出」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_COORDINATOR_UP=1
PY="$(cat "$OPSX_STATE_DIR/python")"
Q="$OPSX_STATE_DIR/coordinator-queue"
SAMPLE="$OPSX_ROOT/tests/fakes/herdr-samples/agent-read.txt"
reset() { : > "$OPSX_FAKE_LOG"; rm -f "$Q" "$Q".sending.*; unset OPSX_TEST_AGENT_READ OPSX_TEST_AGENT_READ_FAIL OPSX_TEST_AGENT_GET_ERR OPSX_TEST_AGENT_GET_RAW OPSX_TEST_COORD_ERR; }
say() { "$PY" -I "$OPSX_ROOT/bin/lib/coordq.py" say "$OPSX_STATE_DIR" "$1" 2>"$FX/err"; }
flush() { "$PY" -I "$OPSX_ROOT/bin/lib/coordq.py" flush "$OPSX_STATE_DIR" 2>>"$FX/err"; }
prompts() { grep -c '^agent prompt opsx-coordinator ' "$OPSX_FAKE_LOG"; }
screen() { # <檔名> <輸入框那一行換成什麼>：從實跑樣本做出畫面，只換輸入框
  sed "s/^❯\$/$2/" "$SAMPLE" > "$FX/$1"; printf '%s' "$FX/$1"
}

# --- 輸入框空時直接送（正例） ---
reset
assert_eq "$(say '[c] 停住：等人答 gate')" sent "空輸入框的結果"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator [c] 停住：等人答 gate" "原樣送一行"
assert_no_file "$Q"
assert_grep '^agent read w3:p7 ' "$OPSX_FAKE_LOG"

# --- 輸入框有字時排隊不送（反例） ---
reset; export OPSX_TEST_AGENT_READ="$(screen typed '❯ 幫我看一下')"
assert_eq "$(say '[c] 停住：等人答 gate')" queued "有字的結果"
assert_eq "$(prompts)" 0 "有字不送"
assert_eq "$(cat "$Q")" "[c] 停住：等人答 gate" "排進佇列一行"

# --- 判讀輸入框（Scenario Outline，正例＋反例） ---
look() { # <期望結果> <說明>：其餘條件由呼叫前設好的環境變數決定
  : > "$OPSX_FAKE_LOG"; rm -f "$Q"
  local got rc; got="$(say '[x] 一則')"; rc=$?
  assert_eq "$got" "$1" "$2"
  case "$1" in
    sent) assert_eq "$rc" 0 "$2 的 rc"; assert_eq "$(prompts)" 1 "$2 要送" ;;
    queued) assert_eq "$rc" 0 "$2 的 rc"; assert_eq "$(prompts)" 0 "$2 不送"; assert_eq "$(cat "$Q")" "[x] 一則" "$2 排進佇列" ;;
    unavailable) assert_eq "$rc" 1 "$2 的 rc"; assert_eq "$(prompts)" 0 "$2 不送"; assert_no_file "$Q" ;;
  esac
}
# 一般場景：實跑樣本（2026-11-16 協調者 pane w9:p2，--format ansi，輸入框空、裡面是 dim 的提示字）
EMPTY_ANSI="$OPSX_ROOT/tests/fakes/herdr-samples/coordinator-empty.ansi"
reset; OPSX_TEST_AGENT_READ="$EMPTY_ANSI" look sent "實跑樣本：輸入框只有 dim 的提示字"
# 有字的畫面是手寫的：使用者沒空在協調者打字取樣，照實跑空樣本把 dim 的提示字換成一般顏色的字，其餘位元組不動
perl -pe 's/\e\[2mPress up to edit queued messages/幫我看一下/' "$EMPTY_ANSI" > "$FX/typed.ansi"
grep -q '幫我看一下' "$FX/typed.ansi" || fail "手寫的有字樣本沒換到輸入框那一行"
reset; OPSX_TEST_AGENT_READ="$FX/typed.ansi" look queued "手寫樣本：❯ 後面有一般顏色的字"
# 舊版 Claude Code 的純文字樣本（沒有提示字）
reset; look sent "實跑樣本：只有 ❯"
reset; OPSX_TEST_AGENT_READ="$(screen typed '❯ 幫我看一下')" look queued "❯ 後面有字"
# 邊界場景
reset; OPSX_TEST_AGENT_READ="$(screen spaces '❯   ')" look sent "❯ 後面只有空白"
reset; { printf '❯ 舊的一句\n\n'; cat "$SAMPLE"; } > "$FX/old"; OPSX_TEST_AGENT_READ="$FX/old" look sent "上方對話有 ❯ 舊的一句，只看最後一個輸入框"
reset; printf 'Do you want to proceed?\n  1. Yes\n  2. No\n' > "$FX/dialog"; OPSX_TEST_AGENT_READ="$FX/dialog" look queued "沒有 ❯ 開頭的行"
reset; OPSX_TEST_AGENT_READ_FAIL=1 look queued "agent read 失敗"
reset; OPSX_TEST_AGENT_GET_RAW='{"result":{"agent":{"agent_status":"idle"}}}' look queued "agent get 讀不出 pane"
reset; OPSX_TEST_AGENT_GET_ERR=agent_not_found look unavailable "agent get 回 agent_not_found"
# herdr 本身叫不通（不是協調者不在）：不排隊，交回呼叫者照原本的方式重試，免得之後跟重試的那一則重複送
reset; got="$(OPSX_TEST_AGENT_GET_ERR=socket_unreachable say '[x] 一則')"; rc=$?
assert_eq "$got" error "agent get 其他錯誤的結果"; assert_eq "$rc" 1 "agent get 其他錯誤的 rc"
assert_eq "$(prompts)" 0 "agent get 其他錯誤不送"; assert_no_file "$Q"
reset; OPSX_TEST_AGENT_GET_RAW='{"result":{"agent":{"pane_id":"w3:p7","agent_status":"blocked"}}}' look unavailable "agent_status 是 blocked"
# 色碼裡的 2 不是 dim：38;2;r;g;b 是顏色，接在後面的字仍算使用者打的
reset; printf '\e[38;2;88;166;255m────\e[0m\n\e[38;2;138;144;149m❯ \e[0m\e[38;2;230;237;243m打到一半\e[0m\n\e[38;2;88;166;255m────\e[0m\n' > "$FX/color2"
OPSX_TEST_AGENT_READ="$FX/color2" look queued "38;2 顏色裡的 2 不當成 dim"
# dim 之後用 22 關掉：關掉之後的字算使用者打的
reset; printf '────\n\e[38;2;138;144;149m❯ \e[0m\e[2m提示\e[22m真的字\n────\n' > "$FX/undim"
OPSX_TEST_AGENT_READ="$FX/undim" look queued "22 關掉 dim 之後的字算有字"
# 輸入框有好幾行：第一行是 ❯ 開頭，後面接著打的字
reset; awk '{ print } /^❯$/ && !d { print "第二行"; d=1 }' "$SAMPLE" > "$FX/multi"; OPSX_TEST_AGENT_READ="$FX/multi" look queued "❯ 之後還有一行字"

# --- 輸入框空了把佇列合成一則送出（正例） ---
reset; printf '[a] 停住：等 reviewer\n[b] gate g1 要人看\n' > "$Q"
assert_eq "$(say '[c] 停住：等人答 gate')" sent
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator 排隊 3 則：[a] 停住：等 reviewer；[b] gate g1 要人看；[c] 停住：等人答 gate" "合成一則"
assert_no_file "$Q"
assert_eq "$(ls "$OPSX_STATE_DIR" | grep -c 'coordinator-queue.sending' || true)" 0 "沒有留下補送中的批次"

# 事件裡的換行換成空白：合成的一則永遠只有一行
reset; assert_eq "$(say "$(printf '[c] 第一行\n第二行')")" sent
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator [c] 第一行 第二行" "換行換成空白"

# --- 補送：佇列空時不讀畫面；有東西且輸入框空就送；有字就留著 ---
reset; flush || fail "空佇列 flush rc：$(cat "$FX/err")"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "佇列空時不叫 herdr"
reset; printf '[a] 停住：等 reviewer\n' > "$Q"; flush || fail "flush rc：$(cat "$FX/err")"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator [a] 停住：等 reviewer" "單則補送原樣送"
assert_no_file "$Q"
reset; printf '[a] 停住：等 reviewer\n' > "$Q"; OPSX_TEST_AGENT_READ="$(screen typed '❯ 幫我看一下')" flush || fail "有字 flush rc"
assert_eq "$(prompts)" 0 "有字不補送"; assert_eq "$(cat "$Q")" "[a] 停住：等 reviewer" "有字時佇列留著"

# --- 送出失敗時佇列不變（反例） ---
reset; printf '[a] 停住：等 reviewer\n' > "$Q"; printf 'agent_prompt_stalled\n' > "$FX/stall"
out="$(OPSX_TEST_COORD_ERR="$FX/stall" say '[c] 停住：等人答 gate')"; rc=$?
assert_eq "$out" error "其他錯誤的結果"; assert_eq "$rc" 1 "其他錯誤 rc"
assert_grep agent_prompt_stalled "$FX/err"
assert_eq "$(cat "$Q")" "[a] 停住：等 reviewer" "佇列仍只有 [a]"
assert_eq "$(ls "$OPSX_STATE_DIR" | grep -c 'coordinator-queue.sending' || true)" 0 "失敗後沒有留下補送中的批次"
# 送的當下才發現協調者不在：批次放回佇列，這一則交回呼叫者
reset; printf '[a] 停住：等 reviewer\n' > "$Q"; printf 'agent_blocked\n' > "$FX/blk"
assert_eq "$(OPSX_TEST_COORD_ERR="$FX/blk" say '[c] 停住')" unavailable "送的當下卡住"
assert_eq "$(cat "$Q")" "[a] 停住：等 reviewer" "卡住時佇列不變"

# --- 補送中斷後下次撿回（正例） ---
reset; dead="$(bash -c 'echo $$')"
printf '[a] 停住：等 reviewer\n' > "$Q.sending.$dead"
assert_eq "$(say '[c] 停住：等人答 gate')" sent
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator 排隊 2 則：[a] 停住：等 reviewer；[c] 停住：等人答 gate" "撿回殘留批次"
assert_no_file "$Q.sending.$dead"
# 還活著的程序拿走的批次不撿
reset; printf '[a] 別人的\n' > "$Q.sending.$$"
assert_eq "$(say '[c] 一則')" sent
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator [c] 一則" "活著的程序的批次不碰"
assert_file "$Q.sending.$$"; rm -f "$Q.sending.$$"

# --- 同時補送每則恰好一次（反例） ---
reset; printf '[e1] 一\n[e2] 二\n[e3] 三\n[e4] 四\n[e5] 五\n' > "$Q"
flush & p1=$!; flush & p2=$!
wait "$p1" || fail "第一個 flush rc：$(cat "$FX/err")"
wait "$p2" || fail "第二個 flush rc：$(cat "$FX/err")"
grep '^agent prompt' "$OPSX_FAKE_LOG" > "$FX/sent"
for e in e1 e2 e3 e4 e5; do
  assert_eq "$(grep -o "\[$e\]" "$FX/sent" | wc -l | tr -d ' ')" 1 "$e 恰好送一次：$(cat "$FX/sent")"
done
assert_no_file "$Q"

# --- 同時補送：第一個補送拿著批次、送到一半時，第二個補送跑完整一次，不能再送同一批（R1.3） ---
# 換名才保證這點：讀完、送完才刪的話，第二個會讀到同一個佇列檔、重送一次
reset; printf '[h1] 一\n[h2] 二\n' > "$Q"; : > "$FX/hold"
OPSX_TEST_PROMPT_HOLD="$FX/hold" flush & p1=$!
n=0; until grep -q '^agent prompt' "$OPSX_FAKE_LOG" || [ "$n" -ge 100 ]; do sleep 0.1; n=$((n + 1)); done
grep -q '^agent prompt' "$OPSX_FAKE_LOG" || fail "第一個補送沒走到送出"
flush || fail "第二個 flush rc：$(cat "$FX/err")"
rm -f "$FX/hold"; wait "$p1" || fail "第一個 flush rc：$(cat "$FX/err")"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG")" 1 "第二個補送不能再送同一批：$(cat "$OPSX_FAKE_LOG")"
assert_no_file "$Q"

# --- 佇列只有空行：補送一次後不留補送中的批次，下一次不叫 herdr（R1.2） ---
reset; printf '\n\n' > "$Q"
flush || fail "空行佇列 flush rc：$(cat "$FX/err")"
assert_eq "$(ls "$OPSX_STATE_DIR" | grep -c 'coordinator-queue.sending' || true)" 0 "空批次不能留下補送中的檔"
: > "$OPSX_FAKE_LOG"; flush || fail "第二次 flush rc"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "沒有東西排隊時不叫 herdr"

# --- 寫入與補送互斥：有人拿著佇列的鎖時，寫入與補送都要等，鎖放掉才動（R1.1） ---
# 寫入者先開檔、補送再換名讀走，之後寫進去的那則會跟著批次檔被刪掉；兩邊都在同一把鎖底下才不會發生
hold_lock() { "$PY" -I -c 'import fcntl, sys, time; f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], "w").close(); time.sleep(float(sys.argv[3]))' "$OPSX_STATE_DIR/coordinator-queue.lock" "$FX/locked" "$1"; }
reset; rm -f "$FX/locked"; hold_lock 2 & pl=$!
n=0; until [ -e "$FX/locked" ] || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
OPSX_TEST_AGENT_READ="$FX/typed.ansi" say '[w] 鎖住時寫入' > /dev/null & pw=$!
sleep 1
assert_no_file "$Q"
wait "$pl"; wait "$pw" || fail "鎖放掉後寫入 rc：$(cat "$FX/err")"
assert_eq "$(cat "$Q")" "[w] 鎖住時寫入" "鎖放掉後才寫進佇列"
rm -f "$FX/locked"; hold_lock 2 & pl=$!
n=0; until [ -e "$FX/locked" ] || [ "$n" -ge 50 ]; do sleep 0.1; n=$((n + 1)); done
flush & pf=$!
sleep 1
assert_eq "$(prompts)" 0 "鎖住時補送不能取走佇列"
assert_file "$Q"
wait "$pl"; wait "$pf" || fail "鎖放掉後補送 rc：$(cat "$FX/err")"
assert_eq "$(grep '^agent prompt' "$OPSX_FAKE_LOG")" "agent prompt opsx-coordinator [w] 鎖住時寫入" "鎖放掉後補送送出"
assert_no_file "$Q"

# --- 命令列參數不對：非 0，不叫 herdr ---
reset; "$PY" -I "$OPSX_ROOT/bin/lib/coordq.py" say "$OPSX_STATE_DIR" >/dev/null 2>&1 && fail "say 少一則事件要非 0"
"$PY" -I "$OPSX_ROOT/bin/lib/coordq.py" nope "$OPSX_STATE_DIR" >/dev/null 2>&1 && fail "不認得的動詞要非 0"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "參數不對不叫 herdr"

echo ok
