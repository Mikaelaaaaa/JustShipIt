#!/usr/bin/env bash
# parked 的卡只被 gate 的 waits-on 指名的那張 merged 喚醒（通知人回 gate）；對不到任何 PR 時照任何新 merged 的 PR 喚醒。
# 驗收：openspec/changes/me-20261111-1824/specs/coordinate-waits-on-wake/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

wp() { # <x-pr 的 status> <y-pr 的 status>：每個 PR 各一個 feature，才不會被當成 session 代管
  cat > "$R/openspec/workplan.yaml" <<EOF
features:
  - name: fx
    status: active
    depends-on: []
    prs:
      - name: x-pr
        branch: feat/x-pr/u
        status: $1
        depends-on: []
        changes:
          - name: x-pr
            status: done
  - name: fy
    status: active
    depends-on: []
    prs:
      - name: y-pr
        branch: feat/y-pr/u
        status: $2
        depends-on: []
        changes:
          - name: y-pr
            status: done
  - name: fa
    status: active
    depends-on: []
    prs:
      - name: card-a
        branch: feat/card-a/u
        status: pending
        depends-on: []
        changes:
          - name: card-a
            status: pending
EOF
}
mkcard card-a
printf '{"demo/card-a":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"
parked() { printf '{"_parked":{"demo/card-a":{"at":"2026-11-10T10:00:00+08:00","gate":"g9","merged":[]%s}},"_redispatched":{}}' "$1" > "$MEMO"; }
waiting() { # <waits_on JSON 值>
  cards '[{"slug":"card-a","section":"待處理","open_gates":[{"id":"g9","opened_at":null}],"waiting":{"type":"等待決定","waits_on":'"$1"',"gate_id":"g9","question":"等 x-pr","recommended":null,"options":["等"]}}]'
}

# 停下時記下 waits-on
wp pending pending
printf '{}' > "$DISP"; rm -f "$MEMO"
cards '[{"slug":"card-a","section":"待處理","dispatch":'"$D"',"agent_status":"idle","waiting":{"type":"等待決定","waits_on":"x-pr","gate_id":"g9","question":"等 x-pr","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _parked demo/card-a | grep -c "'waits_on': 'x-pr'")" 1 "parked 要記 waits_on：$(cat "$MEMO")"
printf '{"demo/card-a":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"

# 無關的 PR 合併：不喚醒
wp pending merged; parked ',"waits_on":"x-pr"'; waiting '"x-pr"'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "y-pr 合了不該喚醒等 x-pr 的卡：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx answer')" 0 "也不該答 gate"
# 喚醒只剩通知：沒喚醒就不能通知人回 gate，也不能記成已答
assert_eq "$(count '^notification show')" 0 "y-pr 合了不該通知人回等 x-pr 的 gate：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(jq -r '._parked."demo/card-a".answered // "none"' "$MEMO")" none "沒喚醒不該記成已答：$(cat "$MEMO")"

# 喚醒＝通知人回 gate：gate 由人答，這裡不答、gate 還開著也不派
woken() { # <說明>
  assert_eq "$(count '^opsx (answer|dispatch)')" 0 "$1：不答也不派：$(cat "$OPSX_FAKE_LOG")"
  assert_grep '^notification show \[demo/card-a\] gate g9 ' "$OPSX_FAKE_LOG"
}

# 等的那張合併：喚醒
wp merged merged; parked ',"waits_on":"x-pr"'; waiting '"x-pr"'
round || fail "rc: $(cat "$FX/out")"
woken "等的那張合併"
# 通知後 gate 沒人答，下一輪照樣等：不答、不派、不記成已答、不重送通知
waiting '"x-pr"'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx (answer|dispatch)')" 0 "gate 還開著，下一輪也不答不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^notification show')" 0 "下一輪不重送通知：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(jq -r '._parked."demo/card-a".answered // "none"' "$MEMO")" none "人沒答不記成已答：$(cat "$MEMO")"

# 等的那張在停下前就已合併（parked 記錄的 merged 已含它）：waits-on 的條件已滿足，要喚醒
wp merged pending; printf '{"_parked":{"demo/card-a":{"at":"2026-11-10T10:00:00+08:00","gate":"g9","merged":["x-pr"],"waits_on":"x-pr"}},"_redispatched":{}}' > "$MEMO"; waiting '"x-pr"'
round || fail "rc: $(cat "$FX/out")"
woken "停下前就已合併"

# waits-on 對不到任何 PR：照任何新合併的 PR 喚醒，記 ??
wp pending merged; parked ',"waits_on":"nope"'; waiting '"nope"'
round || fail "rc: $(cat "$FX/out")"
woken "waits-on 對不到 PR"
grep '??' "$LOG" | grep -q 'nope' || fail "要記 ?? 並點名 nope：$(cat "$LOG")"

# 沒有 waits-on（舊的 parked 記錄）：任何新合併的 PR 都喚醒
wp pending merged; parked ''; waiting 'null'
round || fail "rc: $(cat "$FX/out")"
woken "沒有 waits-on"

# 人答了 gate（collect 給「待指派」、沒有 open gate）：照派卡規則重派，不答
wp merged merged; parked ',"waits_on":"x-pr"'
cards '[{"slug":"card-a","section":"待指派","dispatch":null}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx answer')" 0 "人答過的 gate 不再答：$(cat "$OPSX_FAKE_LOG")"
assert_grep '^opsx dispatch card-a ' "$OPSX_FAKE_LOG"

# collect 把只等別張卡的 parked 卡分在進行中：等的那張合併，照樣通知人回 gate
wp merged merged; parked ',"waits_on":"x-pr"'
cards '[{"slug":"card-a","section":"進行中","open_gates":[{"id":"g9","opened_at":null}],"waiting":{"type":"等待決定","waits_on":"x-pr","gate_id":"g9","question":"等 x-pr","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
woken "parked 的卡在進行中"

# collect 把只等別張卡的 parked 卡分在等待中：等的那張合併，照樣通知人回 gate
wp merged merged; parked ',"waits_on":"x-pr"'
cards '[{"slug":"card-a","section":"等待中","hold":"等 x-pr 合併","open_gates":[{"id":"g9","opened_at":null}],"waiting":{"type":"等待決定","waits_on":"x-pr","gate_id":"g9","question":"等 x-pr","recommended":null,"options":["等"]}}]'
round || fail "rc: $(cat "$FX/out")"
woken "parked 的卡在等待中"

# report 待你決定不是 gate：不停 pane、不走 handle_gate；照 head sha 通知一次（CI 在 babysit 停下後才轉綠時 Stop hook 沒推過）
wp pending pending; rm -f "$MEMO"; printf '{}' > "$DISP"
REPORT_CARD='[{"slug":"card-a","section":"待處理","dispatch":'"$D"',"agent_status":"idle","mr":{"url":"https://gitlab.example.com/a/r/-/merge_requests/9","head_sha":"abc1234def","state":"ready","stuck":null,"error":null,"merged_at":null},"waiting":{"type":"report 待你決定","waits_on":null,"gate_id":null,"needs":null,"action":null,"question":"邏輯表有沒經過決定的項目沒處理","recommended":null,"options":["開啟 pane"]}}]'
cards "$REPORT_CARD"
round || fail "rc: $(cat "$FX/out")"
# 通知照 waiting.question 寫出擋住的原因，只剩邏輯表沒處理的項時不叫人去看 report.md
assert_grep '^notification show \[demo/card-a\] report 待你決定 .*--body 邏輯表有沒經過決定的項目沒處理：' "$OPSX_FAKE_LOG"
assert_eq "$(count '^opsx (stop|answer|dispatch)')" 0 "report 待你決定不停 pane、不答、不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count 'gate None')" 0 "不當成 gate 通知：$(cat "$OPSX_FAKE_LOG")"
grep -q "card-a.*gate" "$LOG" && fail "不走 handle_gate：$(cat "$LOG")"
assert_grep '^notification show \[demo/card-a\] report 待你決定 .*merge_requests/9' "$OPSX_FAKE_LOG"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count 'report 待你決定')" 0 "同一個 head sha 不重送：$(cat "$OPSX_FAKE_LOG")"
printf '{"demo/card-a":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"

# apply 前有活 pane 的卡在待指派：沒有 tasks.md，協調者不派（design D10）
wp pending pending; rm -f "$MEMO"
mkdir -p "$R/openspec/changes/card-g"
printf '{"demo/card-g":{"mode":"autopilot","agent":"claude","pane":"w1:p7","drive_pid":null}}' > "$DISP"
cards '[{"slug":"card-g","stage":"grill","section":"待指派","dispatch":{"mode":"autopilot","agent":"claude","pane":"w1:p7"},"agent_status":"working"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "有活 pane 的 grill 卡在待指派不派：$(cat "$OPSX_FAKE_LOG")"
printf '{"demo/card-a":{"mode":"stopped","agent":"claude","pane":"w1:p9","drive_pid":null}}' > "$DISP"

# 沒有 parked 記錄的進行中卡不派
wp merged merged; rm -f "$MEMO"
cards '[{"slug":"card-a","section":"進行中"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "沒 parked 的進行中卡不派：$(cat "$OPSX_FAKE_LOG")"
echo "coordinate-waits-on-wake ok"
