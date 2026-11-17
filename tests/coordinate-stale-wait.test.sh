#!/usr/bin/env bash
# 派出去的卡停在等背景工作／背景 subagent 超過 7200 秒、agent 閒著、沒有 open gate：協調者在卡的 gates.md 開一個 stale-wait gate，同一次停住只開一次。
# 驗收：openspec/changes/agent-20261112-1222/specs/stale-wait-gate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

G="$R/openspec/changes/card-a/gates.md"
mkcard card-a
printf '{"demo/card-a":{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":null}}' > "$DISP"

ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(seconds=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
ahead() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()+datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
LIMIT="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import coordinate; print(coordinate.STALE_WAIT_SECONDS)' "$OPSX_ROOT/bin/lib")"
SUB="$R/openspec/changes/card-a/subs/sub-x"
# sub_status <worker> <step> <total> <秒數>：子 change 的 status.json，最後一次更新在 <秒數> 秒前
sub_status() { mkdir -p "$SUB"; printf '{"worker":"%s","step":%s,"total":%s,"at":"%s"}' "$1" "$2" "$3" "$(ago "$4")" > "$SUB/status.json"; }
gate_id() { local d="${1:0:19}"; echo "stale-wait-${d//[-T:]/}"; }
stale() { cat "$G" 2>/dev/null | grep -c '^## stale-wait-' || true; }
# card <原因> <秒數> <agent> [open_gates JSON]：寫一張已派出的卡，停住紀錄在 <秒數> 秒前
card() {
  AT="$(ago "$2")"
  cards '[{"slug":"card-a","section":"進行中","dispatch":'"$D"',"agent_status":"'"$3"'","open_gates":'"${4:-[]}"',"stopped":{"reason":"'"$1"'","at":"'"$AT"'"}}]'
}
# row <原因> <秒數> <agent> <要的 stale-wait gate 數>
row() {
  rm -f "$G"; card "$1" "$2" "$3"
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(stale)" "$4" "$1 / $2 秒 / $3：$(cat "$G" 2>/dev/null)"
}

# Examples: 一般
row "等背景工作（apply 站）" 9000 idle 1
assert_grep "^## $(gate_id "$AT")\$" "$G"
assert_grep '^type: decision$' "$G"
assert_grep '^status: open$' "$G"
assert_grep '^選項: 接著做（背景工作已不算在跑） (Recommended) | 停掉背景工作再接站$' "$G"
assert_not_grep '繼續等' "$G"
assert_grep "^問題: 卡停在等背景工作（apply 站）超過 $((LIMIT / 3600)) 小時" "$G"
assert_grep "^已確認: 停住紀錄時間 ${AT}；Stop hook 只在 Stop 時算 ${LIMIT} 秒上限" "$G"
assert_grep '^證據: .*/stop-said/demo-card-a$' "$G"
assert_not_grep '^waits-on' "$G"
grep '??' "$LOG" | grep -q "$(gate_id "$AT")" || fail "要記 ?? 並點名 gate：$(cat "$LOG")"
grep '??' "$LOG" | grep -q "超過 $((LIMIT / 3600)) 小時" || fail "?? 的時數要從 STALE_WAIT_SECONDS 算：$(cat "$LOG")"
row "等背景 subagent（apply 站）" 9000 idle 1
row "等背景工作（apply 站）" 9000 done 1
row "等 reviewer（review 站）" 9000 idle 0
row "等背景工作（apply 站）" 9000 working 0

# Examples: 邊界。一輪的 now 在測試算 at 之後才取，剛好 7200 秒只能直接拿判斷式驗
row "等背景工作（apply 站）" 7201 idle 1
python3 -I - "$OPSX_ROOT/bin/lib" <<'PY' || fail "stale_wait_gate 的邊界案例有錯"
import datetime, sys
sys.path.insert(0, sys.argv[1])
import coordinate
now = datetime.datetime(2026, 11, 17, 12, 0, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=8)))
def c(secs, reason="等背景工作（apply 站）", agent="idle"):
    at = (now - datetime.timedelta(seconds=secs)).isoformat(timespec="seconds")
    return {"dispatch": {"mode": "autopilot"}, "agent_status": agent, "open_gates": [], "stopped": {"reason": reason, "at": at}}
cases = [
    (c(7200), None),
    (c(7201), "stale-wait-20261117095959"),
    (c(9000, "等背景 subagent（apply 站）", "done"), "stale-wait-20261117093000"),
    (c(9000, "等 reviewer（review 站）"), None),
    (c(9000, agent="working"), None),
    ({**c(9000), "stopped": None}, None),
    ({**c(9000), "dispatch": None}, None),
    ({**c(9000), "open_gates": [{"id": "q1", "opened_at": None}]}, None),
]
bad = [(card, want, got) for card, want in cases if (got := coordinate.stale_wait_gate(card, now, "/nonexistent")) != want]
for b in bad:
    print("壞案例：", b)
sys.exit(1 if bad else 0)
PY

# 等背景 subagent：子 change 的 subagent 在上限內更新過 status.json 就是還在跑，不開；跟 hook 的 st_subagent_running 同一個時間基準
row_sub() { sub_status "$1" "$2" "$3" "$4"; row "等背景 subagent（apply 站）" 9000 idle "$5"; }
row_sub subagent-1 1 3 600 0
row_sub subagent-1 1 3 9000 1
row_sub subagent-1 3 3 600 1
row_sub claude 1 3 600 1
printf '{"worker":"subagent-1",' > "$SUB/status.json"
row "等背景 subagent（apply 站）" 9000 idle 1
# 不是 UTF-8 的 status.json 當不在跑，這輪協調不中斷
printf '\xff\xfe{"worker":"subagent-1"}' > "$SUB/status.json"
row "等背景 subagent（apply 站）" 9000 idle 1
# 「等背景工作」不看子 change
sub_status subagent-1 1 3 600
row "等背景工作（apply 站）" 9000 idle 1
rm -rf "$R/openspec/changes/card-a/subs"

# 用量上限暫停：不開
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 10)" "$(ahead 60)" > "$MEMO"
row "等背景工作（apply 站）" 9000 idle 0
rm -f "$MEMO"

# 這輪 check_args 剛 relaunch 過這個 pane：開頭讀到的 idle 已過時，不開，下一輪再看
mkdir -p "$OPSX_STATE_DIR/settings"; printf '{}' > "$OPSX_STATE_DIR/settings/demo-card-a-autopilot.json"
jq '(.result.process_info.foreground_processes[] | select(.argv0 == "claude") | .argv) = ["claude","--resume","abc"]' \
  "$OPSX_ROOT/tests/fakes/herdr-samples/process-info-claude.json" > "$FX/pi-lost.json"
rm -f "$G"; card "等背景工作（apply 站）" 9000 idle
OPSX_TEST_PROCESS_INFO="$FX/pi-lost.json" round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx relaunch card-a --repo $R\$" "$OPSX_FAKE_LOG"
assert_eq "$(stale)" 0 "同一輪 relaunch 過不開：$(cat "$G" 2>/dev/null)"
rm -f "$OPSX_STATE_DIR/settings/demo-card-a-autopilot.json" "$MEMO"

# 已答的 stale-wait gate 屬於舊的停住時間、卡現在是新的停住時間：開新 gate
OLD="$(gate_id "$(ago 20000)")"
card "等背景工作（apply 站）" 9000 idle
printf '## %s\ntype: decision\nstatus: answered\n答案: 接著做\n' "$OLD" > "$G"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(stale)" 2 "新的停住時間要開新 gate：$(cat "$G")"
assert_grep "^## $(gate_id "$AT")\$" "$G"

# 卡上已有 open gate q1：不開
rm -f "$G"; printf '## q1\ntype: decision\nstatus: open\n問題: 要哪個？\n' > "$G"
card "等背景工作（apply 站）" 9000 idle '[{"id":"q1","opened_at":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(stale)" 0 "已有 open gate 不該開：$(cat "$G")"

# 同一次停住連跑兩輪：只有 1 個
rm -f "$G"; card "等背景工作（apply 站）" 9000 idle
round || fail "rc: $(cat "$FX/out")"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(stale)" 1 "連跑兩輪只能有 1 個：$(cat "$G")"

# 這次停住的 stale-wait gate 已經 answered：不再開
card "等背景工作（apply 站）" 9000 idle
printf '## %s\ntype: decision\nstatus: answered\n答案: 繼續等\n' "$(gate_id "$AT")" > "$G"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(stale)" 1 "已回答的不再開：$(cat "$G")"
assert_not_grep '^status: open$' "$G"

# dry：只記 log 不寫
rm -f "$G"; card "等背景工作（apply 站）" 9000 idle
round --dry || fail "rc: $(cat "$FX/out")"
assert_no_file "$G"
assert_grep "DRY 開 gate $(gate_id "$AT").*超過 $((LIMIT / 3600)) 小時" "$LOG"
echo "coordinate-stale-wait ok"
