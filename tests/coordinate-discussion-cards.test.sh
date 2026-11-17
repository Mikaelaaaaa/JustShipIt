#!/usr/bin/env bash
# 討論卡（派工指示含「做到 propose 完成就停」）：coordinate 從收件匣派到 explore、propose 完收 pane、照等級規則再派 apply。
# 驗收：openspec/changes/coordinate-discussion-cards/specs/coordinate-discussion-cards/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"

N='做到 propose 完成就停（留在待指派），不要 apply'
# card_dir <slug> <P1|P2> [tasks.md 內容]：P1 用 frontmatter 覆寫；P2 是不在 workplan 的 planned 卡。沒給 tasks 就沒有 tasks.md
card_dir() {
  local d="$R/openspec/changes/$1"
  rm -rf "$d"; mkdir -p "$d"
  if [ "$2" = P1 ]; then printf -- '---\npriority: P1\npriority_reason: 測試\n---\n' > "$d/inbox.md"; else : > "$d/inbox.md"; fi
  [ -z "${3:-}" ] || printf -- "$3" > "$d/tasks.md"
}
notes() { # <指示>…：collect 的 notes 陣列；沒給就是空陣列
  local out="" t
  for t in "$@"; do out="$out${out:+,}{\"at\":\"2026-11-17T10:00\",\"text\":\"$t\"}"; done
  printf '[%s]' "$out"
}
inbox_card() { printf '{"slug":"%s","section":"收件匣","stage":"explore","notes":%s}' "$1" "$2"; }
T3='- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n'
T3_1='- [x] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n'
live_card() { # <slug> <notes> <agent_status>
  printf '{"slug":"%s","section":"進行中","stage":"apply","notes":%s,"dispatch":%s,"agent_status":"%s"}' "$1" "$2" "$D" "$3"
}

# --- 帶指示的收件匣卡被派到 explore（正例）---
printf '{}' > "$DISP"; rm -f "$MEMO"
card_dir g-p2 P2; card_dir g-p1 P1; card_dir b-prefix P2; card_dir b-short P2
cards "[$(inbox_card g-p2 "$(notes "$N")"),$(inbox_card g-p1 "$(notes "$N")"),$(inbox_card b-prefix "$(notes "沿用母卡 x：$N")"),$(inbox_card b-short "$(notes '做到 propose 完成就停')")]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch g-p2 ')" 1 "P2 帶指示的收件匣卡要派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch g-p1 ')" 1 "P1 帶指示的收件匣卡要派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch b-prefix ')" 1 "指示前面有別的字也要派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch b-short ')" 1 "只有前半句也要派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c -- '--note' "$OPSX_FAKE_LOG")" 0 "派 explore 不帶 --note：$(cat "$OPSX_FAKE_LOG")"

# --- 沒帶指示的收件匣卡不派（反例）---
rm -f "$MEMO"
card_dir n-none P1; card_dir n-other P1; card_dir n-explore P1
cards "[$(inbox_card n-none "$(notes)"),$(inbox_card n-other "$(notes '先看 review 的意見再改')"),$(inbox_card n-explore "$(notes '做到 explore 完成就停')")]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "沒帶指示的收件匣卡不派：$(cat "$OPSX_FAKE_LOG")"

# --- 名額滿了帶指示的卡等下一輪（反例）---
rm -f "$MEMO"
printf '1\n' > "$OPSX_STATE_DIR/max-working"
cards "[$(live_card busy "$(notes)" working),$(inbox_card g-p2 "$(notes "$N")")]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "名額滿了不派：$(cat "$OPSX_FAKE_LOG")"
grep -q '達上限 1' "$LOG" || fail "要記達上限：$(cat "$LOG")"
rm -f "$OPSX_STATE_DIR/max-working"

# --- coordinate 收掉 propose 完的 pane（正例）---
for st in idle done; do
  rm -f "$MEMO"; printf '{"demo/s-%s":%s}' "$st" "$D" > "$DISP"
  card_dir "s-$st" P1 "$T3"
  cards "[$(live_card "s-$st" "$(notes "$N")" "$st")]"
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(count "^opsx stop s-$st ")" 1 "$st 的討論卡要收 pane：$(cat "$OPSX_FAKE_LOG")"
  [ -n "$(memo_get _proposed "demo/s-$st")" ] || fail "$st：memo 要記成 coordinator 收的：$(cat "$MEMO")"
done

# --- 還在做的 pane 不收（反例）---
rm -f "$MEMO"; printf '{}' > "$DISP"
card_dir k-work P1 "$T3"; card_dir k-none P1 "$T3"; card_dir k-ticked P1 "$T3_1"; card_dir k-notasks P1
cards "[$(live_card k-work "$(notes "$N")" working),$(live_card k-none "$(notes)" idle),$(live_card k-ticked "$(notes "$N")" idle),$(live_card k-notasks "$(notes "$N")" idle)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx stop')" 0 "working、沒指示、已勾、沒 tasks.md 都不收：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(memo_get _proposed demo/k-work)$(memo_get _proposed demo/k-none)$(memo_get _proposed demo/k-ticked)$(memo_get _proposed demo/k-notasks)" "" "不收的不記：$(cat "$MEMO")"

# --- 收掉的 P1 卡下一輪派 apply 並追加指示（正例）---
STOPPED='{"mode":"stopped","agent":"codex","pane":"w1:p1","drive_pid":null}'
proposed_memo() { printf '{"_proposed":{"demo/%s":{"at":"2026-11-17T10:00:00+08:00"}}}' "$1" > "$MEMO"; }
card_dir r-p1 P1 "$T3"; proposed_memo r-p1; printf '{"demo/r-p1":%s}' "$STOPPED" > "$DISP"
cards "[{\"slug\":\"r-p1\",\"stage\":\"apply\",\"notes\":$(notes "$N")}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch r-p1 ')" 1 "coordinator 收的 P1 卡要派 apply：$(cat "$OPSX_FAKE_LOG")"
grep '^opsx dispatch r-p1 ' "$OPSX_FAKE_LOG" | grep -q -- '--note .*propose 已完成' || fail "派 apply 要帶 --note 含 propose 已完成：$(cat "$OPSX_FAKE_LOG")"
grep '^opsx dispatch r-p1 ' "$OPSX_FAKE_LOG" | grep -q -- '--agent codex' || fail "沿用 dispatch.json 的 agent：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(memo_get _proposed demo/r-p1)" "" "派出後不再記成 coordinator 收的：$(cat "$MEMO")"

# --- 收掉的 P2 卡不派 apply（反例）---
card_dir r-p2 P2 "$T3"; proposed_memo r-p2; printf '{"demo/r-p2":%s}' "$STOPPED" > "$DISP"
cards "[{\"slug\":\"r-p2\",\"stage\":\"apply\",\"notes\":$(notes "$N")}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "coordinator 收的 P2 卡不派：$(cat "$OPSX_FAKE_LOG")"

# --- 人停的卡照舊不派（反例）---
rm -f "$MEMO"
card_dir h-p1 P1 "$T3"; printf '{"demo/h-p1":%s}' "$STOPPED" > "$DISP"
cards '[{"slug":"h-p1","stage":"apply"}]'
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "人停的卡不派：$(cat "$OPSX_FAKE_LOG")"

# coordinator 收過的卡被人又派出去、再在板上停掉：這次是人停的，不派
card_dir m-p1 P1 "$T3_1"; proposed_memo m-p1; printf '{"demo/m-p1":%s}' "$D" > "$DISP"
cards "[$(live_card m-p1 "$(notes "$N")" working)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(memo_get _proposed demo/m-p1)" "" "人又派出去了就不再記成 coordinator 收的：$(cat "$MEMO")"
printf '{"demo/m-p1":%s}' "$STOPPED" > "$DISP"
cards "[{\"slug\":\"m-p1\",\"stage\":\"apply\",\"notes\":$(notes "$N")}]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "人派出去又停掉的卡不派：$(cat "$OPSX_FAKE_LOG")"
echo "coordinate-discussion-cards ok"
