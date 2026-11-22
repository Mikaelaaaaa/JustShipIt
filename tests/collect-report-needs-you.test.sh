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
echo "collect-report-needs-you ok"
