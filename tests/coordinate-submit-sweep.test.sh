#!/usr/bin/env bash
# coordinate 每輪替閒著的 pane 看輸入框：框裡是 opsx 記下的 last_prompt 才補 Enter；用量上限暫停時不補。
# 叫醒同 feature 的下一個主 change（wake）送出後也看輸入框。
# 驗收：openspec/changes/me-20261118-1102/specs/prompt-submit-check/spec.md「coordinate 每輪替卡在框裡的 opsx 話補 Enter」
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"
SAMPLE="$OPSX_ROOT/tests/fakes/herdr-samples/agent-read.txt"
screen() { # <檔名> <輸入框那一行換成什麼>：從實跑樣本做出畫面，只換輸入框
  sed "s/^❯\$/$2/" "$SAMPLE" > "$FX/$1"; printf '%s' "$FX/$1"
}
ahead() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()+datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
enters() { count '^pane send-keys w5:pAG enter$'; }
mkcard c1 c2
# card <agent_status> <條目多出的欄位>：c1 派在 w5:pAG
card() {
  E='{"mode":"autopilot","agent":"claude","pane":"w5:pAG","drive_pid":null'"$2"'}'
  printf '{"demo/c1":%s}' "$E" > "$DISP"
  cards '[{"slug":"c1","section":"進行中","dispatch":'"$E"',"agent_status":"'"$1"'"}]'
}
# row <last_prompt 欄位> <狀態> <畫面檔> <send-keys 次數> <說明>
row() {
  rm -f "$MEMO"; card "$2" "$1"; export OPSX_TEST_AGENT_READ="$3"
  round || fail "$5 rc: $(cat "$FX/out")"
  assert_eq "$(enters)" "$4" "$5：$(cat "$OPSX_FAKE_LOG")"
}
# last_prompt 是 3 分鐘前送的，還在 10 分鐘內
AT="$(ahead -3)"
LP=',"last_prompt":"跑完了","last_prompt_at":"'"$AT"'"'
lp_of() { jq -r --arg k "$1" '.[$k].last_prompt // "（沒有）"' "$DISP"; }
at_of() { jq -r --arg k "$1" '.[$k].last_prompt_at // "（沒有）"' "$DISP"; }

# --- 閒著的 pane 框裡是 opsx 送的話（正例）：補了 Enter 再看一次，框空了才清 last_prompt ---
export OPSX_TEST_AGENT_READ_ONCE="$FX/once"
cp "$(screen ours '❯ 跑完了')" "$FX/once"
row "$LP" idle "$SAMPLE" 1 "idle、框裡是 last_prompt"
grep ' ok ' "$LOG" | grep -q 'w5:pAG' || fail "log 要有一行 ok 含 pane id：$(cat "$LOG")"
assert_eq "$(count '^agent read w5:pAG --source visible')" 2 "補了 Enter 再讀一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(lp_of demo/c1)" "（沒有）" "補了 Enter 框空了就清掉 last_prompt"
assert_eq "$(at_of demo/c1)" "（沒有）" "last_prompt_at 一起清"
# 送到之後人在框裡打了一樣的字：last_prompt 已清，不再補
export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
round || fail "第二輪 rc: $(cat "$FX/out")"
assert_eq "$(enters)" 0 "last_prompt 清掉後，人打的同一句不送出：$(cat "$OPSX_FAKE_LOG")"
# 補了 Enter 字仍在框裡：last_prompt 留著，記一行 ?? 含 pane id
row "$LP" done "$(screen ours '❯ 跑完了')" 1 "done 也補"
assert_eq "$(lp_of demo/c1)" 跑完了 "補了仍在框裡，last_prompt 留著"
grep ' ?? ' "$LOG" | grep -q 'w5:pAG' || fail "補了仍在框裡要記一行 ?? 含 pane id：$(cat "$LOG")"

# --- last_prompt 超過 10 分鐘：不補，last_prompt 與時刻一起清掉 ---
row ',"last_prompt":"跑完了","last_prompt_at":"'"$(ahead -30)"'"' idle "$(screen ours '❯ 跑完了')" 0 "30 分鐘前送的"
assert_eq "$(lp_of demo/c1)" "（沒有）" "過期的 last_prompt 清掉"
assert_eq "$(at_of demo/c1)" "（沒有）" "過期的 last_prompt_at 清掉"
row ',"last_prompt":"跑完了"' idle "$(screen ours '❯ 跑完了')" 0 "沒有送出時刻的算過期"
assert_eq "$(lp_of demo/c1)" "（沒有）" "沒有送出時刻的 last_prompt 清掉"

# --- 哪些 pane 不補 Enter：一般場景 ---
row "$LP" idle "$(screen typing '❯ 我在打字')" 0 "框裡是人打的字"
row "$LP" idle "$SAMPLE" 0 "框是空的"
row "$LP" working "$(screen ours '❯ 跑完了')" 0 "working"
assert_eq "$(count '^agent read w5:pAG --source visible')" 0 "working 不讀輸入框"
row "$LP" blocked "$(screen ours '❯ 跑完了')" 0 "blocked"
# --- 邊界場景 ---
row "" idle "$(screen ours '❯ 跑完了')" 0 "條目沒有 last_prompt"
printf 'Do you want to proceed?\n  1. Yes\n  2. No\n' > "$FX/dialog"
row "$LP" idle "$FX/dialog" 0 "畫面上沒有輸入框"

# --- 同一個 pane 一輪只讀一次：兩張卡共用 pane ---
rm -f "$MEMO"; export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
E='{"mode":"autopilot","agent":"claude","pane":"w5:pAG","drive_pid":null,"last_prompt":"跑完了","last_prompt_at":"'"$AT"'"}'
printf '{"demo/c1":%s,"demo/c2":%s}' "$E" "$E" > "$DISP"
cards '[{"slug":"c1","section":"進行中","dispatch":'"$E"',"agent_status":"idle"},{"slug":"c2","section":"進行中","dispatch":'"$E"',"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^agent read w5:pAG --source visible')" 2 "同一個 pane 一輪比對讀一次、補 Enter 後確認讀一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(enters)" 1 "同一個 pane 一輪補一次"

# --- session 條目記的 last_prompt 也掃：pane 的狀態取自派在那個 pane 的卡 ---
rm -f "$MEMO"; export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
SM='{"mode":"autopilot","agent":"claude","pane":"w5:pAG","herdr_name":"g","via":"@g","feature":"g","drive_pid":null}'
printf '{"demo/@g":{"mode":"autopilot","agent":"claude","pane":"w5:pAG","drive_pid":null,"last_prompt":"跑完了","last_prompt_at":"%s"},"demo/c1":%s}' "$AT" "$SM" > "$DISP"
cards '[{"slug":"c1","section":"進行中","dispatch":'"$SM"',"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(enters)" 1 "session 條目的 last_prompt 也要補 Enter：$(cat "$OPSX_FAKE_LOG")"

# --- 同 pane 的 session 條目記舊句、成員條目記新句：框裡是新句也要補 ---
rm -f "$MEMO"; export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
printf '{"demo/@g":{"mode":"autopilot","agent":"claude","pane":"w5:pAG","drive_pid":null,"last_prompt":"舊的那句","last_prompt_at":"%s"},"demo/c1":{"mode":"autopilot","agent":"claude","pane":"w5:pAG","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"last_prompt":"跑完了","last_prompt_at":"%s"}}' "$AT" "$AT" > "$DISP"
cards '[{"slug":"c1","section":"進行中","dispatch":'"$SM"',"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^agent read w5:pAG --source visible')" 2 "同 pane 多個條目仍只比對讀一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(enters)" 1 "成員條目的新句對得上要補：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(jq -r '."demo/@g".last_prompt' "$DISP")" 舊的那句 "沒對上的條目 last_prompt 留著"

# --- 共用 pane 的兩張卡一張 working 一張 idle：不補 ---
rm -f "$MEMO"; export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
printf '{"demo/c1":%s,"demo/c2":%s}' "$E" "$E" > "$DISP"
cards '[{"slug":"c1","section":"進行中","dispatch":'"$E"',"agent_status":"working"},{"slug":"c2","section":"進行中","dispatch":'"$E"',"agent_status":"idle"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(enters)" 0 "pane 上有卡在 working 就不補：$(cat "$OPSX_FAKE_LOG")"

# --- 用量上限暫停時不補（反例） ---
card idle "$LP"; export OPSX_TEST_AGENT_READ="$(screen ours '❯ 跑完了')"
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ahead -10)" "$(ahead 60)" > "$MEMO"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^pane send-keys')" 0 "暫停時不補 Enter：$(cat "$OPSX_FAKE_LOG")"

# --- 叫醒同 feature 的下一個主 change：送出後框裡還是那句就補 Enter，last_prompt 記在 session 條目 ---
cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: g
    depends-on: []
    prs:
      - name: m3
        branch: feat/m3/u
        status: pending
        depends-on: []
        changes:
          - name: t3
            status: pending
      - name: m4
        branch: feat/m4/u
        status: pending
        depends-on: [m3]
        changes:
          - name: t4
            status: pending
EOF
mkcard m3 m4; mkdir -p "$R/.claude/worktrees/g"
GM='{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null}'
wake() { # m3 已合併、m4 等著被叫醒
  rm -f "$MEMO"
  printf '{"demo/@g":{"workspace":"demo","workspace_id":"w1","tab":"w1:t9","pane":"w1:p9","agent":"claude","model":"claude-opus-5-5","mode":"autopilot","worktree":"%s","started_at":"2026-11-07T10:00:00+08:00","drive_pid":null},"demo/m3":{"mode":"autopilot","agent":"claude","pane":"w1:p9","herdr_name":"g","via":"@g","feature":"g","drive_pid":null,"branch":"feat/m3/u","worktree":"%s"}}' "$R/.claude/worktrees/g" "$R/.claude/worktrees/g" > "$DISP"
  cards '[{"slug":"m3","section":"進行中","stage":"babysit","dispatch":'"$GM"',"agent_status":"idle","mr":{"url":"https://github.com/o/r/pull/8","state":"state:MERGED","head_sha":"def","conditions":{},"merged_at":"2026-11-07T12:00:00Z"}},{"slug":"m4"}]'
  round || fail "rc: $(cat "$FX/out")"
  assert_grep '^agent prompt g \[m4\] /opsx-workflow:apply m4$' "$OPSX_FAKE_LOG"
  assert_eq "$(count '^pane send-keys w1:p9 enter$')" 1 "叫醒後框裡是送的那句要補 Enter：$(cat "$OPSX_FAKE_LOG")"
}
export OPSX_TEST_AGENT_READ="$SAMPLE" OPSX_TEST_AGENT_READ_ONCE="$FX/once"
cp "$(screen woke '❯ [m4] \/opsx-workflow:apply m4')" "$FX/once"
wake
assert_eq "$(jq -r '."demo/@g".last_prompt // "（沒有）"' "$DISP")" "（沒有）" "補了 Enter 送出去，session 條目的 last_prompt 清掉"
# 補了 Enter 仍在框裡：log 一行 ?? 含 pane id，last_prompt 留在 session 條目給 sweep
export OPSX_TEST_AGENT_READ="$(screen woke '❯ [m4] \/opsx-workflow:apply m4')"
wake
grep ' ?? ' "$LOG" | grep -q 'w1:p9' || fail "stuck 要記一行 ?? 含 pane id：$(cat "$LOG")"
assert_eq "$(jq -r '."demo/@g".last_prompt' "$DISP")" "[m4] /opsx-workflow:apply m4" "last_prompt 記在 session 條目"
echo ok
