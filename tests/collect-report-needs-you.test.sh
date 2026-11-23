#!/usr/bin/env bash
# MR 全綠、report.md 留了要人決定的項目、沒有 gate、pane 沒在改：waiting.type 是 report 待你決定，進待處理。
# 驗收：openspec/changes/me-20261120-1456/specs/board-collect/spec.md「report 留了要人決定的項目算待處理」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0
mkdir -p "$OPSX_STATE_DIR"

q() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,ensure_ascii=False,sort_keys=True) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }
card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]==sys.argv[1] and c["slug"]==sys.argv[2]]
print(json.dumps(c[0],ensure_ascii=False) if c else "null")' "$2" "$3"; }

ROOT="$FX/code"; mkdir -p "$ROOT/r/.git"
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_TEST_GLAB_JSON_BY_IID="$FX/mr-"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$FX/mr-31.json"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"running"},"unresolved_discussions_count":0}' > "$FX/mr-32.json"
mk() { # <slug> <iid>：Consider 留一項沒處理、邏輯表對應 head
  local d="$ROOT/r/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-17\nkind: dev\n' > "$d/.openspec.yaml"
  printf '## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  printf '## 1\n\n- [x] 1.1 a\n' > "$d/tasks.md"
  printf '# Review\n\n## 四桶\n### 待修（範圍內）\n### Consider\n- a.ts:3 測試沒蓋到空字串\n\n## MR\nhttps://gitlab.example.com/acmecorp/r/-/merge_requests/%s\n\n## 邏輯表\nopenspec/changes/%s/logic-map.md · abc1234\n' "$2" "$1" > "$d/report.md"
  printf '# 邏輯表\n' > "$d/logic-map.md"
}
mk idle 31
mk working 31
mk running 32
mk nodisp 31
mk stopped 31
printf '{"r/idle":{"pane":"p1","mode":"autopilot"},"r/working":{"pane":"p2","mode":"autopilot"},"r/running":{"pane":"p1","mode":"autopilot"},"r/stopped":{"pane":"p1","mode":"stopped"}}' > "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
printf '{"id":"cli:agent:list","result":{"agents":[{"pane_id":"p1","agent_status":"idle"},{"pane_id":"p2","agent_status":"working"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"

J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"

C="$(card "$J" r idle)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "report 留了項目、pane 閒著：$C"
assert_eq "$(q "$C" section)" 待處理
assert_eq "$(q "$C" waiting.gate_id)" null "不是 gate"
assert_eq "$(q "$C" waiting.options)" '["開啟 pane"]'
assert_eq "$(q "$C" waiting.question)" "report.md 有留給人決定的項目"
C="$(card "$J" r working)"
assert_eq "$(q "$C" waiting)" null "agent 還在改不算待處理"
assert_eq "$(q "$C" section)" 進行中
assert_eq "$(q "$(card "$J" r running)" waiting)" null "MR 沒全綠不算 report 待你決定"
# 沒有 pane（沒派出、被停掉）：只有「開啟 pane」可按也沒用，不標
assert_eq "$(q "$(card "$J" r nodisp)" waiting)" null "沒派出的卡不標 report 待你決定"
assert_eq "$(q "$(card "$J" r stopped)" waiting)" null "停掉的卡不標 report 待你決定"
# herdr 讀不到：分不出 pane 在不在，也不標
J="$(OPSX_TEST_HERDR_LIST_FAIL='socket gone' opsx collect --root "$ROOT")"
assert_eq "$(q "$(card "$J" r idle)" waiting)" null "herdr 讀不到不標 report 待你決定"

# 邏輯表 ⚠ 段的沒經過決定項要有標記（· 開卡 <slug> 或 · gate <id>），不然不是可以合併
# 驗收：openspec/changes/logic-map-undecided-gate/specs/board-collect/spec.md「項都有標記是可以合併」「有沒標記的項就不是可以合併」
mkm() { # <slug> <⚠ 段>：report 沒有待決項、邏輯表對應 head
  mk "$1" 31
  local d="$ROOT/r/openspec/changes/$1"
  printf '# Review\n\n## 四桶\n### 待修（範圍內）\n### Consider\n\n## MR\nhttps://gitlab.example.com/acmecorp/r/-/merge_requests/31\n\n## 邏輯表\nopenspec/changes/%s/logic-map.md · abc1234\n' "$1" > "$d/report.md"
  printf '# 邏輯表\n\n### ⚠ 要看的地方\n%s\n\n## 業務說明\n- 沒經過決定。這段不是 ⚠ 段\n' "$2" > "$d/logic-map.md"
}
mkm ok-empty ''
mkm ok-gate '- 沒經過決定。D4：以後都 判斷 · gate logic-map-undecided-r3'
mkm ok-card '- 沒經過決定。D2（既有）：空清單不提示 · 開卡 agent-20261123-1200'
mkm ok-bug '- bug：違反 design D3。D5：今天 判斷'
mkm ok-tidy '- 程式整理。D3：null 分支走不到'
mkm ok-nodesign $'沒有 design.md，未分類\n- D2：git -C 只取第一個 · gate logic-map-undecided-r1'
mkm ok-subline $'- 沒經過決定。D4：以後都 判斷 · gate logic-map-undecided-r3\n  - 細節：否定句'
mkm no-plain '- 沒經過決定。D4：以後都 判斷'
mkm no-nodesign $'沒有 design.md，未分類\n- D2：git -C 只取第一個'
mkm no-midline '- 沒經過決定。D4：· gate logic-map-undecided-r3 這行後面還有字'
mkm no-word '- 沒經過決定。D4：描述裡提到「開卡」兩個字'
mk no-both 31
printf '# 邏輯表\n\n### ⚠ 要看的地方\n- 沒經過決定。D4：以後都 判斷\n' > "$ROOT/r/openspec/changes/no-both/logic-map.md"
# 邏輯表每個功能各有一段 ⚠，每一段都要看；未分類由各段的第一行決定
mkmulti() { # <slug> <功能 1 的 ⚠ 段> <功能 2 的 ⚠ 段>
  mkm "$1" ''
  printf '# 邏輯表\n\n## 功能 1：甲\n\n### ⚠ 要看的地方\n%s\n\n## 功能 2：乙\n\n### ⚠ 要看的地方\n%s\n' "$2" "$3" > "$ROOT/r/openspec/changes/$1/logic-map.md"
}
mkmulti ok-multi '- 沒經過決定。D1：甲 · gate logic-map-undecided-r1' '- 沒經過決定。D2：乙 · 開卡 agent-20261123-1300'
mkmulti no-multi '- 沒經過決定。D1：甲 · gate logic-map-undecided-r1' '- 沒經過決定。D2：乙'
mkmulti no-multi-nodesign '- bug：違反 design D3。D1：甲' $'沒有 design.md，未分類\n- D2：乙'
printf '{"r/ok-empty":{"pane":"p1","mode":"autopilot"},"r/ok-gate":{"pane":"p1","mode":"autopilot"},"r/ok-card":{"pane":"p1","mode":"autopilot"},"r/ok-bug":{"pane":"p1","mode":"autopilot"},"r/ok-tidy":{"pane":"p1","mode":"autopilot"},"r/ok-nodesign":{"pane":"p1","mode":"autopilot"},"r/ok-subline":{"pane":"p1","mode":"autopilot"},"r/no-plain":{"pane":"p1","mode":"autopilot"},"r/no-nodesign":{"pane":"p1","mode":"autopilot"},"r/no-midline":{"pane":"p1","mode":"autopilot"},"r/no-word":{"pane":"p1","mode":"autopilot"},"r/no-both":{"pane":"p1","mode":"autopilot"},"r/ok-multi":{"pane":"p1","mode":"autopilot"},"r/no-multi":{"pane":"p1","mode":"autopilot"},"r/no-multi-nodesign":{"pane":"p1","mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"
assert_eq "$(q "$(card "$J" r ok-empty)" waiting.type)" 可以合併 "⚠ 段沒有項目"
assert_eq "$(q "$(card "$J" r ok-gate)" waiting.type)" 可以合併 "行尾 · gate"
assert_eq "$(q "$(card "$J" r ok-card)" waiting.type)" 可以合併 "行尾 · 開卡"
assert_eq "$(q "$(card "$J" r ok-bug)" waiting.type)" 可以合併 "bug 項不用標記"
assert_eq "$(q "$(card "$J" r ok-tidy)" waiting.type)" 可以合併 "程式整理項不用標記"
assert_eq "$(q "$(card "$J" r ok-nodesign)" waiting.type)" 可以合併 "未分類表每一項都有標記"
assert_eq "$(q "$(card "$J" r ok-subline)" waiting.type)" 可以合併 "縮排子行屬於上一項"
C="$(card "$J" r no-plain)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "沒標記：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理"
assert_eq "$(q "$C" waiting.options)" '["開啟 pane"]'
assert_eq "$(q "$C" section)" 待處理
C="$(card "$J" r no-nodesign)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "未分類表的項沒標記：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理"
C="$(card "$J" r no-midline)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "標記不在行尾不算：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理"
C="$(card "$J" r no-word)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "描述裡出現開卡字樣不算：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理"
# 跟 report 待決項同時存在：問題欄用「、」列出每一條
C="$(card "$J" r no-both)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "兩條都在：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理、report.md 有留給人決定的項目"
assert_eq "$(q "$(card "$J" r ok-multi)" waiting.type)" 可以合併 "兩個功能的 ⚠ 都有標記"
C="$(card "$J" r no-multi)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "功能 2 的項沒標記：$C"
assert_eq "$(q "$C" waiting.question)" "邏輯表有沒經過決定的項目沒處理"
C="$(card "$J" r no-multi-nodesign)"
assert_eq "$(q "$C" waiting.type)" "report 待你決定" "功能 2 是未分類段、項沒標記：$C"
echo "collect-report-needs-you ok"
