#!/usr/bin/env bash
# 派出去的卡停在等背景工作／背景 subagent 超過 7200 秒、agent 閒著、沒有 open gate：協調者在卡的 gates.md 開一個 stale-wait gate，同一次停住只開一次。
# 驗收：openspec/changes/agent-20261112-1222/specs/stale-wait-gate/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

G="$R/openspec/changes/card-a/gates.md"
mkcard card-a
printf '{"demo/card-a":{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":null}}' > "$DISP"

ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(seconds=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
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
assert_grep '^選項: 繼續等 (Recommended) | 停掉背景工作再接站$' "$G"
assert_grep "^已確認: 停住紀錄時間 $AT" "$G"
assert_grep '^證據: .*/stop-said/demo-card-a$' "$G"
assert_not_grep '^waits-on' "$G"
grep '??' "$LOG" | grep -q "$(gate_id "$AT")" || fail "要記 ?? 並點名 gate：$(cat "$LOG")"
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
bad = [(card, want, got) for card, want in cases if (got := coordinate.stale_wait_gate(card, now)) != want]
for b in bad:
    print("壞案例：", b)
sys.exit(1 if bad else 0)
PY

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
assert_grep "DRY 開 gate $(gate_id "$AT")" "$LOG"
echo "coordinate-stale-wait ok"
