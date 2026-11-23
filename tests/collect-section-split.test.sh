#!/usr/bin/env bash
# 看板分欄照 stage 與 pane 狀態：apply 之後在工作的是進行中，沒在工作的是等待中並帶 hold，apply 之前有 pane 的是待指派。
# 驗收：openspec/changes/me-20261120-1456/specs/board-collect/spec.md「看板分欄照 stage 與 pane 狀態」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
export OPSX_MR_CACHE_TTL=0
mkdir -p "$OPSX_STATE_DIR/stop-said"

q() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,ensure_ascii=False,sort_keys=True) if isinstance(d,(dict,list,bool)) or d is None else d)' "$2"; }
card() { printf '%s' "$1" | python3 -I -c 'import json,sys;d=json.load(sys.stdin)
c=[c for c in d["cards"] if c["repo"]==sys.argv[1] and c["slug"]==sys.argv[2]]
print(json.dumps(c[0],ensure_ascii=False) if c else "null")' "$2" "$3"; }

ROOT="$FX/code"; mkdir -p "$ROOT/r/.git"
CH="$ROOT/r/openspec/changes"
STEPS='## 步驟\n\n- 1 讀卡：done\n- 2 how：已知\n- 3 影響範圍：已知\n- 4 why：skip：x\n- 5 prototype：skip：x\n- 6 查資料：skip：x\n- 7 對照 code：skip：x\n- 8 待決：待決\n- 9 unslop：done\n'
base() { # <slug>：只有 inbox 的卡（stage explore）
  mkdir -p "$CH/$1"
  printf 'schema: opsx\ncreated: 2026-11-15\nkind: dev\n' > "$CH/$1/.openspec.yaml"
  printf '## 一句話\n\n%s\n' "$1" > "$CH/$1/inbox.md"
}
grill_card() { base "$1"; printf '## 已知\n\n- x\n\n## 待決\n\n- 選 a 還是 b\n\n## 不做\n\n- x\n\n%b' "$STEPS" > "$CH/$1/explore.md"; }
propose_card() { grill_card "$1"; printf '## 決策\n\n- D1 a\n' > "$CH/$1/grill.md"; printf '## 已知\n\n- x\n\n## 待決\n\n## 不做\n\n- x\n\n%b' "$STEPS" > "$CH/$1/explore.md"; }
apply_card() { base "$1"; printf '## 1\n\n- [ ] 1.1 a\n' > "$CH/$1/tasks.md"; }
review_card() { base "$1"; printf '## 1\n\n- [x] 1.1 a\n' > "$CH/$1/tasks.md"; printf '{"phase":"apply","step":1,"total":1,"label":"x","tests":"green"}' > "$CH/$1/status.json"; }
pr_card() { review_card "$1"; printf '# report\n' > "$CH/$1/report.md"; }
babysit_card() { # <slug> <iid> <mr json>
  review_card "$1"
  printf '# report\n\n## MR\nhttps://gitlab.example.com/acmecorp/r/-/merge_requests/%s\n' "$2" > "$CH/$1/report.md"
  printf '%s' "$3" > "$FX/mr-$2.json"
}
stopped() { printf '%s\n2026-11-20T10:00:00+08:00\n' "$2" > "$OPSX_STATE_DIR/stop-said/r-$1"; }
export OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_TEST_GLAB_JSON_BY_IID="$FX/mr-"
MR_CI='{"state":"opened","draft":false,"has_conflicts":false,"sha":"aaa111","head_pipeline":{"status":"running"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}'
MR_CONFLICT='{"state":"opened","draft":false,"has_conflicts":true,"sha":"bbb222","head_pipeline":{"status":"success"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}'

apply_card a-working
babysit_card b-ci 11 "$MR_CI"; stopped b-ci 'babysit 一輪做完，等 MR 合併'
babysit_card b-conflict 12 "$MR_CONFLICT"; stopped b-conflict 'babysit 做完，MR 卡在衝突'
review_card rv-bg; stopped rv-bg '等背景工作（review 站）'
pr_card pr-rev; stopped pr-rev '等 reviewer（pr 站）'
base ex-w
grill_card gr-i
propose_card pp-w
apply_card a-unknown
babysit_card b-work 13 "$MR_CI"; stopped b-work 'babysit 做完，MR 卡在衝突'
babysit_card b-red 14 '{"state":"opened","draft":false,"has_conflicts":false,"sha":"ccc333","head_pipeline":{"status":"failed"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}'
babysit_card b-manual 15 '{"state":"opened","draft":false,"has_conflicts":false,"sha":"ddd444","head_pipeline":{"status":"manual"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}'
babysit_card b-timeout 16 '{"state":"opened","draft":false,"has_conflicts":false,"sha":"eee555","head_pipeline":{"status":"timed_out"},"unresolved_discussions_count":0,"created_at":"2026-11-05T01:10:00.000Z","merged_at":null}'
babysit_card b-gone 17 "$MR_CI"; stopped b-gone '等背景工作（babysit 站）'
apply_card undispatched

printf '{' > "$OPSX_STATE_DIR/dispatch.json"
printf '"r/a-working":{"pane":"pa","mode":"autopilot"},"r/b-ci":{"pane":"pb","mode":"autopilot"},"r/b-conflict":{"pane":"pc","mode":"autopilot"},' >> "$OPSX_STATE_DIR/dispatch.json"
printf '"r/rv-bg":{"pane":"pd","mode":"autopilot"},"r/pr-rev":{"pane":"pe","mode":"autopilot"},"r/ex-w":{"pane":"pf","mode":"autopilot"},' >> "$OPSX_STATE_DIR/dispatch.json"
printf '"r/gr-i":{"pane":"pg","mode":"autopilot"},"r/pp-w":{"pane":"ph","mode":"autopilot"},"r/a-unknown":{"pane":"gone","mode":"autopilot"},"r/b-work":{"pane":"pi","mode":"autopilot"},"r/b-red":{"pane":"pb","mode":"autopilot"},"r/b-manual":{"pane":"pb","mode":"autopilot"},"r/b-timeout":{"pane":"pb","mode":"autopilot"},"r/b-gone":{"pane":"gone2","mode":"autopilot"}}' >> "$OPSX_STATE_DIR/dispatch.json"
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
printf '{"id":"cli:agent:list","result":{"agents":[' > "$OPSX_TEST_HERDR_AGENTS"
printf '{"pane_id":"pa","agent_status":"working"},{"pane_id":"pb","agent_status":"idle"},{"pane_id":"pc","agent_status":"done"},' >> "$OPSX_TEST_HERDR_AGENTS"
printf '{"pane_id":"pd","agent_status":"idle"},{"pane_id":"pe","agent_status":"idle"},{"pane_id":"pf","agent_status":"working"},' >> "$OPSX_TEST_HERDR_AGENTS"
printf '{"pane_id":"pg","agent_status":"idle"},{"pane_id":"ph","agent_status":"working"},{"pane_id":"pi","agent_status":"working"}],"type":"agent_list"}}' >> "$OPSX_TEST_HERDR_AGENTS"

J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc: $J"

expect() { # <slug> <stage> <section> <hold> <說明>
  local c; c="$(card "$J" r "$1")"
  assert_eq "$(q "$c" stage)" "$2" "$1 的 stage（fixture）：$c"
  assert_eq "$(q "$c" section)" "$3" "$1 的 section：$5"
  assert_eq "$(q "$c" hold)" "$4" "$1 的 hold：$5"
}
# 一般場景
expect a-working apply 進行中 null "apply 站在工作"
expect b-ci babysit 等待中 "等 CI" "pipeline 還沒過"
expect b-conflict babysit 等待中 "等協調者" "MR 卡在衝突、pane 做完"
expect rv-bg review 等待中 "等背景工作" "停在等背景工作"
expect pr-rev pr 等待中 "等背景工作" "停在等 reviewer"
expect ex-w explore 待指派 null "還在 explore 的 pane"
expect gr-i grill 待指派 null "還在 grill 的 pane"
expect pp-w propose 待指派 null "還在 propose 的 pane"
# 邊界場景
expect a-unknown apply 等待中 "等協調者" "pane 不在了"
expect b-work babysit 進行中 null "在工作時不看停住原因與 CI"
expect b-red babysit 等待中 "等協調者" "pipeline 已經失敗，不是在等 CI"
expect b-manual babysit 等待中 "等協調者" "手動 job 要人按，CI 不會自己往下走"
expect b-timeout babysit 等待中 "等協調者" "CI 逾時"
expect b-gone babysit 等待中 "等協調者" "pane 不在了，先於 CI 與停住原因"
# 沒派出的卡不帶 hold
expect undispatched apply 待指派 null "沒派出"

# herdr 讀不到：分不出有沒有在工作，留在進行中
J="$(OPSX_TEST_HERDR_LIST_FAIL='socket gone' opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc（herdr 斷）: $J"
expect b-ci babysit 進行中 null "herdr 讀不到"

# 排序：等待中在進行中之後、待指派之前
J="$(opsx collect --root "$ROOT")"
order="$(printf '%s' "$J" | python3 -I -c 'import json,sys
seen=[]
for c in json.load(sys.stdin)["cards"]:
    if c["section"] not in seen: seen.append(c["section"])
print(" ".join(seen))')"
assert_eq "$order" "進行中 等待中 待指派" "cards 依 進行中 · 等待中 · 待指派 排序"

# --- Unicode 行界字元不切段（card-auto-merge「併入段的兩種形狀」）：讀取端只以 \n 切行 ---
LS=$'\342\200\250'; NEL=$'\302\205'; FF=$'\014'
merged_line() { # <slug> <字元>：一行形狀的併入段
  base "$1"; printf '\n## 併入：2026-11-20T10:00:00+08:00 agent:t\n\n- id: m-%s\n- kind_of_work: planned\n- type: bug\n\nfoo%sbar\n' "$1" "$2" >> "$CH/$1/inbox.md"
}
merged_indented() { # <slug> <字元>：縮排形狀的併入段
  base "$1"; printf '\n## 併入：2026-11-20T10:00:00+08:00 agent:t\n\n- id: m-%s\n- kind_of_work: planned\n- type: bug\n\n  ## 一句話\n\n  foo%sbar\n' "$1" "$2" >> "$CH/$1/inbox.md"
}
merged_line ls-line "$LS"; merged_indented ls-ind "$LS"; merged_line ls-nel "$NEL"; merged_indented ls-ff "$FF"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc（行界字元）: $J"
errs="$(q "$J" errors)"
row() { # <slug> <字元>
  assert_eq "$(q "$(card "$J" r "$1")" merged.0.text)" "foo$2bar" "$1 的併入段一句話"
  case "$errs" in *"$1 的併入段"*) fail "$1 不該有併入段格式錯誤：$errs" ;; esac
}
row ls-line "$LS"; row ls-ind "$LS"; row ls-nel "$NEL"; row ls-ff "$FF"

# --- 看板對含 \r 的段報格式錯，跟 split-out 判斷一致（card-auto-merge「讀併入段不轉換行」）---
base cr
printf '\n## 併入：2026-11-20T10:00:00+08:00 agent:t\n\n- id: r1\n- kind_of_work: planned\n- type: bug\n\none\rtwo\n' >> "$CH/cr/inbox.md"
printf '\r\n## 併入：2026-11-20T10:01:00+08:00 agent:t\r\n\r\n- id: r3\r\n- kind_of_work: planned\r\n- type: bug\r\n\r\n整段 CRLF\r\n' >> "$CH/cr/inbox.md"
printf '\n## 併入：2026-11-20T10:02:00+08:00 agent:t\n\n- id: ok1\n- kind_of_work: planned\n- type: bug\n\nfine\n' >> "$CH/cr/inbox.md"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect rc（\\r）: $J"
assert_eq "$(q "$(card "$J" r cr)" merged | python3 -I -c 'import json,sys; print(" ".join(m["id"] for m in json.load(sys.stdin)))')" "ok1" "含 \\r 的段不進 merged[]"
errs="$(q "$J" errors)"
case "$errs" in *"cr 的併入段"*r1*) ;; *) fail "r1 要報格式錯：$errs" ;; esac
case "$errs" in *"cr 的併入段"*r3*) ;; *) fail "r3 要報格式錯：$errs" ;; esac
echo "collect-section-split ok"
