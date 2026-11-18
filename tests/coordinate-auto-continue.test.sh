#!/usr/bin/env bash
# 換帳號後停在 Automatic continue stopped 的 pane：coordinate 送「繼續」，暫停中也送，同一個 pane 10 分鐘最多一次；
# 停住訊息在最後一個上限訊息之後的 pane 不算撞上限。
# 驗收：openspec/changes/me-20261118-1102/specs/opsx-coordinate/spec.md「停在 Automatic continue stopped 的 pane 送「繼續」」「用量上限到了就暫停」
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"
AR="$FX/agent-read.txt"; export OPSX_TEST_AGENT_READ="$AR"
ago() { python3 -I -c 'import datetime,sys; print((datetime.datetime.now().astimezone()-datetime.timedelta(minutes=int(sys.argv[1]))).isoformat(timespec="seconds"))' "$1"; }
STOP='Automatic continue stopped · send a prompt to continue'
conts() { count '^agent prompt c1 繼續$'; }
mkcard c1 q1
# q1 在 workplan 裡才是會自動派的卡（不在 workplan 是 P2，不自動派）
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: fq
    status: active
    depends-on: []
    prs:
      - name: q1
        branch: feat/q1/u
        status: pending
        depends-on: []
        changes:
          - name: q1
            status: pending
EOF
E='{"mode":"autopilot","agent":"claude","pane":"w5:pAP","drive_pid":null}'
printf '{"demo/c1":%s}' "$E" > "$DISP"
c1() { printf '{"slug":"c1","section":"進行中","dispatch":%s,"agent_status":"%s"}' "$E" "${1:-idle}"; }
cards "[$(c1)]"

# --- 換帳號後停住的 pane 收到繼續（正例） ---
rm -f "$MEMO"; printf '  ⎿  Interrupted\n%s\n' "$STOP" > "$AR"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(conts)" 1 "停住的 pane 送一次繼續：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(memo_get _continued w5:pAP)" ] || fail "memo 的 _continued 要記 w5:pAP：$(cat "$MEMO")"
grep ' ok ' "$LOG" | grep -q 'w5:pAP' || fail "log 要有一行 ok 含 pane id：$(cat "$LOG")"
assert_grep '^agent read w5:pAP --source visible --format ansi$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."demo/c1".last_prompt' "$DISP")" 繼續 "繼續經過送出後的輸入框檢查"

# --- 送繼續的節流：一般場景（3 分鐘、30 分鐘）；邊界（9 分 59 秒、10 分鐘）用判斷式驗，一輪的 now 在測試算時刻之後才取 ---
throttle() { # <幾分鐘前> <次數>
  printf '{"_continued":{"w5:pAP":"%s"}}' "$(ago "$1")" > "$MEMO"
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(conts)" "$2" "上次送繼續在 $1 分鐘前：$(cat "$OPSX_FAKE_LOG")"
}
throttle 3 0
throttle 30 1
python3 -I - "$OPSX_ROOT/bin/lib" <<'PY' || fail "continue_due 的邊界案例有錯"
import datetime, sys
sys.path.insert(0, sys.argv[1])
import coordinate
now = datetime.datetime(2026, 11, 18, 12, 0, 0, tzinfo=datetime.timezone(datetime.timedelta(hours=8)))
def at(secs):
    return (now - datetime.timedelta(seconds=secs)).isoformat(timespec="seconds")
cases = [(None, True), (at(180), False), (at(599), False), (at(600), True), (at(1800), True)]
bad = [(last, want) for last, want in cases if coordinate.continue_due(last, now) != want]
for b in bad:
    print("壞案例：", b)
sys.exit(1 if bad else 0)
PY

# --- 用量上限暫停中也送繼續（正例），不派卡 ---
printf '{"_usage_limit":{"seen_at":"%s","resets_at":"%s"}}' "$(ago 10)" "$(ago -180)" > "$MEMO"
printf '%s\n' "$STOP" > "$AR"
cards "[$(c1),{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(conts)" 1 "暫停中也送繼續：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch')" 0 "暫停中不派卡"

# --- 沒有停住訊息不送（反例） ---
rm -f "$MEMO"; printf 'Usage limit reached · continuing automatically at 7pm\n' > "$AR"
cards "[$(c1)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(conts)" 0 "只有上限訊息不送繼續"

# --- working、unknown 的卡不讀畫面，不送 ---
rm -f "$MEMO"; printf '%s\n' "$STOP" > "$AR"
cards "[$(c1 working)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(conts)" 0 "working 不送繼續"

# --- 停住訊息在上限訊息之後不算上限（正例）：照常派卡 ---
rm -f "$MEMO"; printf 'Usage limit reached · limit resets 7pm\n%s\n' "$STOP" > "$AR"
cards "[$(c1),{\"slug\":\"q1\"}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _usage_limit seen_at)" "" "停住訊息在後不記暫停：$(cat "$MEMO")"
assert_eq "$(count '^opsx dispatch q1 ')" 1 "停住訊息在後照常派卡：$(cat "$LOG")"

# --- 上限訊息在停住訊息之後仍算上限（反例） ---
rm -f "$MEMO"; printf '%s\nUsage limit reached again · limit resets 7pm\n' "$STOP" > "$AR"
round || fail "rc: $(cat "$FX/out")"
[ -n "$(memo_get _usage_limit seen_at)" ] || fail "上限訊息在後要記暫停：$(cat "$MEMO")"
assert_eq "$(count '^opsx dispatch')" 0 "上限訊息在後不派卡"

# --- 不在任何 dispatch 條目的 pane 從 _continued 拿掉 ---
printf '{"_continued":{"w9:gone":"%s"}}' "$(ago 3)" > "$MEMO"; printf 'ok\n' > "$AR"
cards "[$(c1)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _continued w9:gone)" "" "pane 不在了就拿掉：$(cat "$MEMO")"

# --- --dry：只記 DRY，不送 ---
rm -f "$MEMO"; printf '%s\n' "$STOP" > "$AR"
round --dry || fail "rc: $(cat "$FX/out")"
assert_eq "$(conts)" 0 "--dry 不送"
assert_grep 'DRY herdr agent prompt c1 繼續$' "$FX/out"
echo ok
