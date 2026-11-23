#!/usr/bin/env bash
# opsx merge：重驗五條件 → dispatch.json 寫一次性核准 → decisions → herdr agent prompt "/babysit merge"。不自己跑 glab mr merge。
# 驗收：specs/board-actions/spec.md「核准合併」兩個 Scenario（herdr-board 3.2）
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_TEST_GLAB_JSON="$FX/mr.json"

R="$(mk_repo Acmecorp-AI)"; C="$R/openspec/changes/x"; mk_change "$R" x; mkdir -p "$OPSX_STATE_DIR"
REPORT='# report\n\n## MR\nhttps://gitlab.example.com/acmecorp/Acmecorp-AI/-/merge_requests/431\n\n## 邏輯表\n%s\n'
printf "$REPORT" 'openspec/changes/x/logic-map.md · abc1234' > "$C/report.md"; printf '# 邏輯表\n' > "$C/logic-map.md"
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","agent_status":"idle"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"
printf '{"Acmecorp-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
cd "$R"

# --- 全綠 ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; assert_eq "$?" 0 "merge: $out"
PD="${OPSX_STATE_DIR}-protected"
assert_eq "$(jq -r '."Acmecorp-AI/x".merge_approved' "$PD/authz.json")" abc1234def
jq -e '."Acmecorp-AI/x".merge_approved_at | startswith("20")' "$PD/authz.json" >/dev/null || fail "要有 merge_approved_at"
assert_eq "$(jq -r '."Acmecorp-AI/x" | has("merge_approved")' "$OPSX_STATE_DIR/dispatch.json")" false "dispatch.json 不再寫核准"
assert_eq "$(tail -1 "$C/decisions.tsv" | cut -f2-4)" $'你\t已允許\t核准合併 abc1234def'
tail -1 "$C/decisions.tsv" | cut -f5 | grep -q '^abc1234def · ' || fail "證據要是 sha · MR URL" 
assert_grep '^agent prompt x /opsx-workflow:babysit merge abc1234def$' "$OPSX_FAKE_LOG"
# 互動模式的卡：沒有閘門，拒絕並說去 pane
printf '{"Acmecorp-AI/x":{"mode":"interactive","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "互動模式要拒絕"; echo "$out" | grep -q 'pane' || fail "要說去 pane: $out"
printf '{"Acmecorp-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
assert_not_grep '^mr merge' "$OPSX_FAKE_LOG"   # 不自己合

# --- 五條件全綠，但 agent 還在改或邏輯表舊：拒絕、什麼都不寫（specs/board-actions「核准合併前確認 agent 停手、邏輯表對應最新 head」） ---
refused() { # <訊息關鍵字> <說明> [訊息不該含的字]
  local out; out="$(opsx merge x 2>&1)" && fail "$2 要拒絕: $out"
  echo "$out" | grep -q "$1" || fail "$2 的訊息要含「$1」: $out"
  [ -z "${3:-}" ] || ! echo "$out" | grep -q "$3" || fail "$2 的訊息不該含「$3」: $out"
  assert_no_file "$PD/authz.json"
  cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "$2：decisions 不該變"
  assert_eq "$(grep -c 'babysit merge' "$OPSX_FAKE_LOG" || true)" 0 "$2 不送 /babysit merge"
}
cp "$C/decisions.tsv" "$FX/before.tsv"; : > "$OPSX_FAKE_LOG"; rm -rf "$PD"
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","agent_status":"working"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"
refused '還在改' "pane working" '等輸入'
# pane 停在權限框：不能把 /babysit merge 加 Enter 打進去
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","agent_status":"blocked"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"
refused '等輸入' "pane blocked" '還在改'
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"p4","agent_status":"idle"}],"type":"agent_list"}}' > "$OPSX_TEST_HERDR_AGENTS"
printf '## g1\ntype: decision\nstatus: open\n問題: 哪個？\n' > "$C/gates.md"
refused 'gate' "open gate"
rm -f "$C/gates.md"
printf "$REPORT" 'openspec/changes/x/logic-map.md · 9f8e7d6' > "$C/report.md"
refused '邏輯表' "邏輯表 sha 舊"
printf "$REPORT" '產表失敗：無 Agent 工具' > "$C/report.md"
refused '邏輯表' "產表失敗"
printf "$REPORT" 'openspec/changes/x/logic-map.md · abc1234' > "$C/report.md"
mv "$C/logic-map.md" "$FX/logic-map.md"
refused '邏輯表' "卡目錄沒有 logic-map.md"
mv "$FX/logic-map.md" "$C/logic-map.md"
printf '\n## 四桶\n### Consider\n- a.ts:3 測試沒蓋到空字串\n' >> "$C/report.md"
refused '留給人決定' "Consider 有沒處理的項"
printf "$REPORT" 'openspec/changes/x/logic-map.md · abc1234' > "$C/report.md"
printf '\n## 四桶\n### 待修（範圍內）\n- a.ts:9 漏判 null · task R1.1\n' >> "$C/report.md"
refused '留給人決定' "待修有一項"
printf "$REPORT" 'openspec/changes/x/logic-map.md · abc1234' > "$C/report.md"
# 邏輯表有沒標記的沒經過決定項（logic-map-undecided-gate specs/board-collect「opsx merge 與 Stop hook 擋同一條」）
printf '# 邏輯表\n\n### ⚠ 要看的地方\n- 沒經過決定。D4：以後都 判斷\n' > "$C/logic-map.md"
refused '邏輯表有沒經過決定的項目沒處理' "邏輯表有沒標記的項"
# gate 答了還沒寫回：標記指到它的項不算處理過
printf '# 邏輯表\n\n### ⚠ 要看的地方\n- 沒經過決定。D4：以後都 判斷 · gate logic-map-undecided-r1\n' > "$C/logic-map.md"
printf '## logic-map-undecided-r1\ntype: decision\nstatus: answered\nanswer: 1A\n' > "$C/gates.md"
refused '邏輯表有沒經過決定的項目沒處理' "gate 答了還沒寫回"
rm -f "$C/gates.md"
printf '# 邏輯表\n' > "$C/logic-map.md"
# herdr 叫不通不擋
out="$(OPSX_TEST_HERDR_LIST_FAIL='socket gone' opsx merge x 2>&1)"; assert_eq "$?" 0 "herdr 讀不到不擋: $out"
rm -rf "$PD"

# --- 有未解 thread：退出非零、什麼都不寫 ---
printf '{"Acmecorp-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
cp "$C/decisions.tsv" "$FX/before.tsv"; : > "$OPSX_FAKE_LOG"; rm -rf "$PD"
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":2}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "threads 要退出非零"
echo "$out" | grep -q 'threads' || fail "要說哪條沒過: $out"
assert_no_file "$PD/authz.json"
cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "decisions 不該變"; assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG" || true)" 0

# --- 快取裡是舊的全綠，merge 也要重抓（TTL 不作數）---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
OPSX_MR_CACHE_TTL=600 opsx collect --root "$FX" >/dev/null 2>&1 || true   # 把全綠灌進快取
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "merge 要重抓，不吃快取: $out"

# --- 沒派出的卡：沒 agent 可執行，拒絕 ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{}' > "$OPSX_STATE_DIR/dispatch.json"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "沒派出要拒絕"; echo "$out" | grep -q '沒派出' || fail "要說沒派出: $out"
# --- 代管卡（auto-dispatch）：送給 herdr_name，prompt 帶 slug ---
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '{"Acmecorp-AI/x":{"mode":"autopilot","pane":"p4","agent":"claude","grants":[],"via":"p","herdr_name":"p"}}' > "$OPSX_STATE_DIR/dispatch.json"; : > "$OPSX_FAKE_LOG"
out="$(opsx merge x 2>&1)"; assert_eq "$?" 0 "代管卡 merge: $out"
assert_grep '^agent prompt p /opsx-workflow:babysit merge abc1234def x$' "$OPSX_FAKE_LOG"
assert_eq "$(jq -r '."Acmecorp-AI/x".merge_approved' "$PD/authz.json")" abc1234def

# --- 受保護位置寫不進去（沙盒內）：非零退出、訊息含路徑，什麼都不改、不送 prompt ---
printf '{"Acmecorp-AI/x":{"mode":"autopilot","pane":"p4","agent":"x","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
rm -rf "$PD"; mkdir -p "$PD"; chmod 500 "$PD"; : > "$OPSX_FAKE_LOG"
cp "$C/decisions.tsv" "$FX/before.tsv"; cp "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before"
out="$(opsx merge x 2>&1)"; [ $? -ne 0 ] || fail "受保護位置唯讀要非零退出"
echo "$out" | grep -qF "$PD" || fail "訊息要含受保護路徑: $out"
cmp -s "$C/decisions.tsv" "$FX/before.tsv" || fail "decisions 不該變"
cmp -s "$OPSX_STATE_DIR/dispatch.json" "$FX/dispatch.before" || fail "dispatch.json 不該變"
assert_eq "$(grep -c '^agent prompt' "$OPSX_FAKE_LOG" || true)" 0
chmod 700 "$PD"
echo ok
