#!/usr/bin/env bash
# 討論卡（派工指示含「做到 propose 完成就停」）：coordinate 從收件匣派去跑到 propose；propose 完由同一個 pane 接 apply，coordinate 不收 pane（design D8）。
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
# 名額照 dispatch.json 條目與 herdr agent list 數：busy 的 pane 有 agent 在跑、cwd 在條目的 worktree 裡
mkdir -p "$FX/wt/busy"
printf '{"demo/busy":{"mode":"autopilot","agent":"claude","pane":"w1:p1","drive_pid":null,"worktree":"%s"}}' "$FX/wt/busy" > "$DISP"
printf '{"id":"cli:agent:list","result":{"agents":[{"pane_id":"w1:p1","agent_status":"working","cwd":"%s"}],"type":"agent_list"}}' "$FX/wt/busy" > "$FX/agents.json"
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
cards "[$(live_card busy "$(notes)" working),$(inbox_card g-p2 "$(notes "$N")")]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "名額滿了不派：$(cat "$OPSX_FAKE_LOG")"
grep -q '達上限 1' "$LOG" || fail "要記達上限：$(cat "$LOG")"
rm -f "$OPSX_STATE_DIR/max-working"; unset OPSX_TEST_HERDR_AGENTS

# --- propose 完的討論卡 pane 不收，由同一個 pane 接 apply（D8）---
for st in idle done; do
  rm -f "$MEMO"; printf '{"demo/s-%s":%s}' "$st" "$D" > "$DISP"
  card_dir "s-$st" P1 "$T3"
  cards "[$(live_card "s-$st" "$(notes "$N")" "$st")]"
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(count '^opsx (stop|dispatch)')" 0 "${st}、0 個勾的討論卡不收也不重派：$(cat "$OPSX_FAKE_LOG")"
done

# --- 人在 explore 中途停掉的收件匣討論卡不派 ---
rm -f "$MEMO"
card_dir x-p2 P2; printf '{"demo/x-p2":{"mode":"stopped","agent":"claude","pane":"w1:p1","drive_pid":null}}' > "$DISP"
cards "[$(inbox_card x-p2 "$(notes "$N")")]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "人停掉的收件匣討論卡不派：$(cat "$OPSX_FAKE_LOG")"
echo "coordinate-discussion-cards ok"
