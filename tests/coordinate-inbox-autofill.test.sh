#!/usr/bin/env bash
# coordinate 補收件匣卡：可派存量低於下限、還有名額時，照（等級、since、slug）派判過重複的 P0/P1 收件匣卡去做到 propose。
# 驗收：openspec/changes/inbox-autofill/subs/autofill-coordinate/specs/coordinate-inbox-autofill/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/coordinate-fixture.sh"
CH="$R/openspec/changes"
FLOOR="$OPSX_STATE_DIR/inbox-floor"
STAMP='"2026-11-22T10:00:00+08:00"'

# 每個情境從乾淨的狀態開始：沒有卡、沒有條目、沒有工作中的 pane、沒有下限檔
reset() {
  rm -rf "$CH"; mkdir -p "$CH"
  rm -f "$MEMO" "$FLOOR"; printf '{}' > "$DISP"
  printf '{"id":"cli:agent:list","result":{"agents":[],"type":"agent_list"}}' > "$FX/agents.json"
  export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
}
# pdir <slug> <P0|P1|P2> [tasks]：卡目錄，inbox.md 用 frontmatter 覆寫等級；第三個參數有值就寫 tasks.md
pdir() {
  mkdir -p "$CH/$1"
  printf -- '---\npriority: %s\npriority_reason: 測試\n---\n' "$2" > "$CH/$1/inbox.md"
  [ -z "${3:-}" ] || printf -- '- [ ] 1.1 x\n' > "$CH/$1/tasks.md"
}
# busy <n>：n 個工作中的 pane（dispatch.json 條目加 herdr agent，cwd 在條目的 worktree 裡）
busy() {
  python3 -I - "$FX" "$1" "$DISP" "$FX/agents.json" <<'PY'
import json, os, sys
fx, n, disp, agents = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
d, a = {}, []
for i in range(n):
    wt = os.path.join(fx, "wt", "busy%d" % i)
    os.makedirs(wt, exist_ok=True)
    d["demo/busy%d" % i] = {"mode": "autopilot", "agent": "claude", "pane": "w1:b%d" % i, "drive_pid": None, "worktree": wt}
    a.append({"pane_id": "w1:b%d" % i, "agent_status": "working", "cwd": wt})
with open(disp, "w") as f:
    json.dump(d, f)
with open(agents, "w") as f:
    json.dump({"id": "cli:agent:list", "result": {"agents": a, "type": "agent_list"}}, f)
PY
}
# ready <slug>…：可派的 P1 待指派卡（有 tasks.md），印 JSON 物件以逗號接起來
ready() { local s out=""; for s in "$@"; do pdir "$s" P1 t; out="$out${out:+,}{\"slug\":\"$s\"}"; done; printf '%s' "$out"; }
# stock <slug>…：這些待指派卡這輪 opsx dispatch 會失敗，派完還留在可派存量裡。卡本身照樣用 ready 寫；要在主 shell 呼叫，export 才留得住
stock() { local s; for s in "$@"; do export "OPSX_TEST_FAIL_dispatch_$s=fake fail"; done; }
unstock() { local v; for v in $(compgen -v OPSX_TEST_FAIL_dispatch_); do unset "$v"; done; }
# inbox <slug> <P0|P1|P2> [since] [dedup_checked JSON]：收件匣卡；預設判過重複、since 2026-11-20
inbox() {
  pdir "$1" "$2"
  printf '{"slug":"%s","section":"收件匣","stage":"explore","since":"%s","dedup_checked":%s}' "$1" "${3:-2026-11-20}" "${4:-$STAMP}"
}
inboxes() { local s out=""; for s in "$@"; do out="$out${out:+,}$(inbox "$s" P1)"; done; printf '%s' "$out"; }
filled() { count '^opsx dispatch i[a-z0-9]* .*協調者補卡'; }

# ========== 依存量與名額決定補幾張（Scenario Outline）==========
for row in "0 0 2" "1 3 1" "2 0 0" "0 7 1" "0 8 0" "3 0 0"; do
  set -- $row
  reset; unstock; busy "$2"
  S=""; [ "$1" -eq 0 ] || { stock $(seq -f 'r%g' 1 "$1"); S="$(ready $(seq -f 'r%g' 1 "$1")),"; }
  cards "[$S$(inboxes ia ib ic)]"
  round || fail "存量 $1 工作中 $2 rc: $(cat "$FX/out")"
  assert_eq "$(filled)" "$3" "存量 $1 工作中 $2 要補 $3 張：$(cat "$OPSX_FAKE_LOG")"
done
unstock

# ========== 這輪派出的待指派卡從存量扣掉 ==========
reset
cards "[$(ready ra rb),$(inboxes ia ib ic)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch r[ab] ')" 2 "待指派兩張派出：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(filled)" 2 "派出的待指派不算存量，補 2 張：$(cat "$OPSX_FAKE_LOG")"

# ========== P2 與依賴沒合的待指派卡不算存量 ==========
reset
pdir dep P1
printf 'created: 2026-11-07\n\nfeatures:\n  - name: fa\n    prs:\n      - name: dep\n        status: pending\n        depends-on: []\n        changes:\n          - name: dep\n            status: pending\n  - name: fb\n    prs:\n      - name: rblk\n        status: pending\n        depends-on: [dep]\n        changes:\n          - name: rblk\n            status: pending\n' > "$R/openspec/workplan.yaml"
pdir rp2a P2 t; pdir rp2b P2 t
cards "[{\"slug\":\"rp2a\"},{\"slug\":\"rp2b\"},$(ready rblk),$(inboxes ia ib ic)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch r')" 0 "P2 與依賴沒合的待指派不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(filled)" 2 "它們不算存量，補 2 張：$(cat "$OPSX_FAKE_LOG")"
rm -f "$R/openspec/workplan.yaml"

# ========== 下限設定檔的值決定下限（Scenario Outline）==========
for row in "none 2" "3 3" "1 1" "3nl 3"; do
  set -- $row
  reset
  case "$1" in none) ;; 3nl) printf '3\n' > "$FLOOR" ;; *) printf '%s' "$1" > "$FLOOR" ;; esac
  cards "[$(inboxes ia ib ic id ie)]"
  round || fail "下限 $1 rc: $(cat "$FX/out")"
  assert_eq "$(filled)" "$2" "下限 $1 要補 $2 張：$(cat "$OPSX_FAKE_LOG")"
done

# ========== 設定檔內容不合法時這輪不跑（Scenario Outline）==========
for bad in abc 0 -1 empty; do
  reset
  if [ "$bad" = empty ]; then : > "$FLOOR"; else printf '%s\n' "$bad" > "$FLOOR"; fi
  cards "[$(inboxes ia ib)]"
  if round; then fail "下限 $bad 要非 0 結束：$(cat "$FX/out")"; fi
  grep -q 'inbox-floor' "$LOG" || fail "下限 $bad 的 log 要有 inbox-floor：$(cat "$LOG")"
  assert_eq "$(count '^opsx dispatch')" 0 "下限 $bad 不派任何卡：$(cat "$OPSX_FAKE_LOG")"
done

# ========== 符合條件的卡被補 ==========
reset
cards "[$(inbox ia P1)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ia ')" 1 "判過重複的 P1 收件匣卡派一次：$(cat "$OPSX_FAKE_LOG")"

# ========== 不符條件的卡不補（Scenario Outline）==========
reset
cards "[$(inbox ia P1 2026-11-20 null)]"
round || fail "沒記號 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "沒記號的卡不補：$(cat "$OPSX_FAKE_LOG")"
reset
cards "[$(inbox ia P2)]"
round || fail "P2 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "P2 不補：$(cat "$OPSX_FAKE_LOG")"
reset
printf '{"demo/ia":{"mode":"stopped","agent":"claude","pane":"w1:p1","drive_pid":null}}' > "$DISP"
cards "[$(inbox ia P1)]"
round || fail "stopped rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch')" 0 "人停掉的卡不補：$(cat "$OPSX_FAKE_LOG")"
# 補過一次的卡有活的條目，下一輪不再補
reset
printf '{"demo/ia":%s}' "$D" > "$DISP"
cards "[$(inbox ia P1)]"
round || fail "有條目 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ia ')" 0 "有 dispatch 條目的卡不補：$(cat "$OPSX_FAKE_LOG")"
# 帶 propose 停點指示的收件匣卡由 dispatch_new 派，不再補一次
reset
cards "[{\"slug\":\"ia\",\"section\":\"收件匣\",\"stage\":\"explore\",\"since\":\"2026-11-20\",\"dedup_checked\":$STAMP,\"notes\":[{\"at\":\"2026-11-20T10:00\",\"text\":\"做到 propose 完成就停（留在待指派），不要 apply\"}]}]"
pdir ia P1
round || fail "討論卡 rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ia ')" 1 "討論卡只派一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(filled)" 0 "討論卡不當補卡：$(cat "$OPSX_FAKE_LOG")"

# ========== 只補得下一張時挑排最前的（Scenario Outline）==========
pick() { # <卡甲 slug> <等級> <since> <卡乙 slug> <等級> <since> <被派的>
  reset; unstock; stock rs
  cards "[$(ready rs),$(inbox "$1" "$2" "$3"),$(inbox "$4" "$5" "$6")]"
  round || fail "rc: $(cat "$FX/out")"
  assert_eq "$(count '^opsx dispatch .*協調者補卡')" 1 "只補一張：$(cat "$OPSX_FAKE_LOG")"
  assert_eq "$(count "^opsx dispatch $7 .*協調者補卡")" 1 "要補 $7：$(cat "$OPSX_FAKE_LOG")"
  unstock
}
pick a P1 2026-11-20 b P0 2026-11-21 b
pick a P1 2026-11-21 b P1 2026-11-20 b
pick me-2 P1 2026-11-20 me-1 P1 2026-11-20 me-1

# ========== 排後面的卡下一輪才補 ==========
reset; stock rs
cards "[$(ready rs),$(inbox ia P1 2026-11-20),$(inbox ib P1 2026-11-21)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ib ')" 0 "排第二的不補：$(cat "$OPSX_FAKE_LOG")"
unstock

# ========== 名額滿時 P0 照補 ==========
reset; busy 8; stock ra rb
cards "[$(ready ra rb),$(inbox ia P0)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ia .*協調者補卡')" 1 "名額滿時 P0 照補：$(cat "$OPSX_FAKE_LOG")"
unstock

# ========== P0 佔掉最後一個名額後 P1 不補 ==========
reset; busy 7
cards "[$(inbox ia P0),$(inbox ib P1)]"
round || fail "rc: $(cat "$FX/out")"
assert_eq "$(count '^opsx dispatch ia ')" 1 "P0 補：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(count '^opsx dispatch ib ')" 0 "P0 佔掉最後一個名額，P1 不補：$(cat "$OPSX_FAKE_LOG")"

# ========== 補卡的派工指示 ==========
reset
cards "[$(inbox ia P1)]"
round || fail "rc: $(cat "$FX/out")"
assert_grep "^opsx dispatch ia --agent claude --mode autopilot --kind dev --repo $R --note 做到 propose 完成就停（協調者補卡）\$" "$OPSX_FAKE_LOG"

# ========== 派失敗不中斷 ==========
reset; export OPSX_TEST_FAIL_dispatch_ia="fake fail"
cards "[$(inbox ia P1 2026-11-20),$(inbox ib P1 2026-11-21)]"
round || fail "rc: $(cat "$FX/out")"
grep -q '^.*?? .*ia' "$LOG" || fail "派失敗要記 ?? 含 ia：$(cat "$LOG")"
assert_eq "$(count '^opsx dispatch ib .*協調者補卡')" 1 "第二張照樣補：$(cat "$OPSX_FAKE_LOG")"
unstock
echo "coordinate-inbox-autofill ok"
