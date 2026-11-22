#!/usr/bin/env bash
# opsx release：協調者補的卡 propose 完放掉 pane（dispatch 條目記 released_at），認這個標記的每一處各一個斷言。
# 驗收：openspec/changes/inbox-autofill/subs/autofill-propose-release/specs/dispatch-release/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela OPSX_DISPATCH_RETRY_SLEEP=0
DISP="$OPSX_STATE_DIR/dispatch.json"
field() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get(sys.argv[3], ""))' "$DISP" "$1" "$2"; }

# ---------- opsx release ----------
ROOT="$FX/code"; mkdir -p "$ROOT/o/.git" "$ROOT/o/openspec/changes"
O="$(cd "$ROOT/o" && pwd -P)"

# 記標記（正例）：mode 與 pane 不變
printf '{"o/a":{"mode":"autopilot","pane":"w1:p1","agent":"claude","drive_pid":null}}' > "$DISP"
out="$(opsx release a --repo "$O" 2>&1)"; assert_eq "$?" 0 "release: $out"
[ -n "$(field o/a released_at)" ] || fail "要寫 released_at: $(cat "$DISP")"
assert_eq "$(field o/a mode)" autopilot "mode 不變"
assert_eq "$(field o/a pane)" w1:p1 "pane 不變"
assert_eq "$(grep -c '^pane close' "$OPSX_FAKE_LOG" || true)" 0 "release 不關 pane"

# 重複放掉：rc 0，不覆寫原時間
printf '{"o/a":{"mode":"autopilot","pane":"w1:p1","released_at":"2026-01-01T00:00:00+08:00"}}' > "$DISP"
out="$(opsx release a --repo "$O" 2>&1)"; assert_eq "$?" 0 "重複 release: $out"
assert_eq "$(field o/a released_at)" "2026-01-01T00:00:00+08:00" "不覆寫原時間"

# 不能放掉的條目（反例）：rc 非 0、stderr 含卡名、dispatch.json 不變
printf '{"o/other":{"mode":"autopilot","pane":"w1:p9"}}' > "$DISP"; cp "$DISP" "$FX/before"
out="$(opsx release a --repo "$O" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] || fail "沒有條目要退出非 0"
case "$out" in *o/a*) ;; *) fail "stderr 要含卡名：$out" ;; esac
cmp -s "$DISP" "$FX/before" || fail "沒有條目時 dispatch.json 不能動"
printf '{"o/a":{"mode":"stopped","pane":"w1:p1"}}' > "$DISP"; cp "$DISP" "$FX/before"
out="$(opsx release a --repo "$O" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] || fail "stopped 要退出非 0"
case "$out" in *o/a*) ;; *) fail "stderr 要含卡名：$out" ;; esac
cmp -s "$DISP" "$FX/before" || fail "stopped 時 dispatch.json 不能動"

# ---------- chain.session_alive 與 coordinate 的 live_panes ----------
python3 -I - "$OPSX_ROOT/bin/lib" "$FX/wt" <<'PY' || fail "session_alive / live_panes 要認 released_at"
import sys
sys.path.insert(0, sys.argv[1]); import chain, coordinate
wt = sys.argv[2]
e = {"mode": "autopilot", "pane": "w1:p1", "worktree": wt, "released_at": "2026-11-22T10:00:00+08:00"}
assert not chain.session_alive(e), e
assert chain.session_alive({"mode": "autopilot", "pane": "w1:p1"})
agents = [{"pane_id": "w1:p1", "agent_status": "working", "cwd": wt}]
assert coordinate.live_panes({"o/a": e}, agents, set()) == set()
PY

# ---------- collect：dispatch null、待指派、孤兒理由 released；reap idle 才收 ----------
mkcard() { # <slug>：tasks.md 0/3 勾的活卡
  local d="$O/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\ncreated: 2026-11-05\nkind: dev\n' > "$d/.openspec.yaml"
  printf -- '---\nsource: me\nfound: 2026-11-04\n---\n\n## 一句話\n\n%s\n' "$1" > "$d/inbox.md"
  printf '## 1\n\n- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$d/tasks.md"
}
agent() { # <pane> <status> <cwd>
  printf '{"agent":"claude","pane_id":"%s","agent_status":"%s","cwd":"%s","foreground_cwd":"%s","terminal_title_stripped":"t-%s"}' "$1" "$2" "$3" "$3" "$1"
}
mkcard ri; mkcard rw; mkcard rg; mkcard rd
R_AT="2026-11-22T10:00:00+08:00"
printf '{"o/ri":{"pane":"w1:p1","mode":"autopilot","released_at":"%s"},"o/rw":{"pane":"w1:p2","mode":"autopilot","released_at":"%s"},"o/rg":{"pane":"w1:p3","mode":"autopilot","released_at":"%s"},"o/rd":{"pane":"w1:p4","mode":"autopilot","released_at":"%s"}}' "$R_AT" "$R_AT" "$R_AT" "$R_AT" > "$DISP"
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent w1:p1 idle "$O/.claude/worktrees/ri"; printf ','
  agent w1:p2 working "$O/.claude/worktrees/rw"; printf ','
  agent w1:p4 done "$O/.claude/worktrees/rd"
  printf '],"type":"agent_list"}}'; } > "$FX/agents.json"
export HERDR_ENV=1 OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
opsx collect --root "$ROOT" > "$FX/collect.json" 2>"$FX/collect.err" || fail "collect: $(cat "$FX/collect.err")"
python3 -I - "$FX/collect.json" <<'PY' || fail "collect 要把放掉的卡當成沒派出：$(cat "$FX/collect.json")"
import json, sys
data = json.load(open(sys.argv[1]))
cards = {c["slug"]: c for c in data["cards"]}
for s in ("ri", "rw", "rg"):
    assert cards[s]["dispatch"] is None, (s, cards[s]["dispatch"])
    assert cards[s]["section"] == "待指派", (s, cards[s]["section"])
orphans = {o["slug"]: o["reason"] for o in data["orphans"]}
assert orphans.get("ri") == "released" and orphans.get("rw") == "released", orphans
PY

: > "$OPSX_FAKE_LOG"
out="$(opsx reap --root "$ROOT" 2>&1)"; assert_eq "$?" 0 "reap: $out"
assert_eq "$(grep -c '^pane close w1:p1$' "$OPSX_FAKE_LOG" || true)" 1 "idle 的放掉 pane 要收：$out"
assert_eq "$(grep -c '^pane close w1:p2$' "$OPSX_FAKE_LOG" || true)" 0 "working 的不收"
assert_eq "$(grep -c '^pane close w1:p4$' "$OPSX_FAKE_LOG" || true)" 1 "agent 是 done 的放掉 pane 也收：$out"
[ -n "$(field o/ri reaped_at)" ] || fail "收掉的要補 reaped_at"
[ -z "$(field o/rw reaped_at)" ] || fail "沒收的不補 reaped_at"
unset OPSX_TEST_HERDR_AGENTS; export HERDR_ENV=""

# ---------- opsx dispatch 單卡：pane 收掉後才重派，重派清三個欄位 ----------
R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
mkdir -p "$R/openspec/changes/rel-card"
printf 'schema: opsx\ncreated: 2026-11-05\n' > "$R/openspec/changes/rel-card/.openspec.yaml"
printf '[repos]\n"Acmecorp-CS" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
cd "$R"
printf '{"Acmecorp-CS/rel-card":{"mode":"autopilot","pane":"w1:p1","agent":"claude","drive_pid":null,"released_at":"%s"}}' "$R_AT" > "$DISP"
: > "$OPSX_FAKE_LOG"
out="$(opsx dispatch rel-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "pane 還沒收時要拒絕: $out"
case "$out" in *reap*) ;; *) fail "拒絕要說等 reap 收 pane: $out" ;; esac
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"
# 反例：只有 reaped_at、沒有 released_at、不是 stopped，照舊當成已派出
printf '{"Acmecorp-CS/rel-card":{"mode":"autopilot","pane":"w1:p1","agent":"claude","drive_pid":null,"reaped_at":"%s"}}' "$R_AT" > "$DISP"
out="$(opsx dispatch rel-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "沒有 released_at 的 reaped 條目要拒絕: $out"
assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "拒絕時不碰 herdr"
printf '{"Acmecorp-CS/rel-card":{"mode":"autopilot","pane":"w1:p1","agent":"claude","drive_pid":null,"released_at":"%s","reaped_at":"%s"}}' "$R_AT" "$R_AT" > "$DISP"
out="$(opsx dispatch rel-card --agent claude --mode interactive --kind dev 2>&1)" || fail "收掉後要能重派: $out"
python3 -I -c 'import json,sys; e=json.load(open(sys.argv[1]))["Acmecorp-CS/rel-card"]; assert not ({"released_at","reaped_at","pane_closed_at"} & set(e)), e' "$DISP" || fail "重派要清掉三個欄位：$(cat "$DISP")"
cd "$FX"

# ---------- coordinate dispatch_new（假 opsx 讀 collect JSON；herdr agent 清單是 fakes 的範例，只有 w1:p2、w2:p1） ----------
use_fakes opsx git openspec gh
export OPSX_TEST_COLLECT_JSON="$FX/collect-fake.json" OPSX_FAKE_LOG="$FX/fake.log"
C="$(mk_repo demo)"; mkdir -p "$C/openspec/changes"
for_card() { # <slug>：P1、tasks.md 0/3 勾、待指派
  local d="$C/openspec/changes/$1"; mkdir -p "$d"
  printf -- '---\npriority: P1\npriority_reason: 測試\n---\n' > "$d/inbox.md"
  printf -- '- [ ] 1.1 a\n- [ ] 1.2 b\n- [ ] 1.3 c\n' > "$d/tasks.md"
}
for_card c-wait; for_card c-done; for_card c-stop; for_card c-gone
python3 -I - "$C" > "$OPSX_TEST_COLLECT_JSON" <<'PY'
import json, sys
top = sys.argv[1]
base = {"repo": "demo", "kind": "dev", "stage": "apply", "section": "待指派", "archived": False, "waiting": None, "open_gates": [],
        "dispatch": None, "agent_status": None, "mr": None, "stopped": None, "notes": [], "since": None, "dedup_checked": None}
print(json.dumps({"repo_paths": {"demo": top}, "errors": [],
                  "cards": [dict(base, slug=s, path="%s/openspec/changes/%s" % (top, s)) for s in ("c-wait", "c-done", "c-stop", "c-gone")]}))
PY
printf '{"demo/c-gone":{"mode":"autopilot","agent":"claude","pane":"w1:p9","released_at":"%s"},"demo/c-wait":{"mode":"autopilot","agent":"claude","pane":"w1:p2","released_at":"%s"},"demo/c-done":{"mode":"autopilot","agent":"claude","pane":"w1:p1","released_at":"%s","reaped_at":"%s"},"demo/c-stop":{"mode":"stopped","agent":"claude","pane":"w1:p3"}}' "$R_AT" "$R_AT" "$R_AT" "$R_AT" > "$DISP"
: > "$OPSX_FAKE_LOG"; : > "$OPSX_STATE_DIR/coordinator.log"
bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/coord.out" 2>&1 || fail "coordinate rc: $(cat "$FX/coord.out")"
assert_eq "$(grep -c '^opsx dispatch c-done ' "$OPSX_FAKE_LOG" || true)" 1 "收掉後照 P1 規則派一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-wait ' "$OPSX_FAKE_LOG" || true)" 0 "pane 還沒收不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-stop ' "$OPSX_FAKE_LOG" || true)" 0 "人停的卡照舊不派"
grep -q 'c-wait.*reap' "$OPSX_STATE_DIR/coordinator.log" || fail "log 要有一行含 c-wait 與 reap：$(cat "$OPSX_STATE_DIR/coordinator.log")"
assert_eq "$(grep -c '^opsx dispatch c-gone ' "$OPSX_FAKE_LOG" || true)" 1 "pane 已不在 herdr 的放掉條目當成已收，照 P1 派：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(field demo/c-gone pane_closed_at)" ] || fail "pane 已不在 herdr 要記 pane_closed_at，dispatch.sh 才放行：$(cat "$DISP")"
[ -z "$(field demo/c-wait pane_closed_at)" ] || fail "pane 還在 herdr 的不記：$(cat "$DISP")"

# ---------- coordinate dispatch_features：放掉且 pane 已收的成員不佔分支，session 照常開 ----------
cat > "$C/openspec/workplan.yaml" <<'EOF'
created: 2026-11-07

features:
  - name: base
    prs:
      - name: b0
        branch: feat/b0/u
        status: merged
        depends-on: []
        changes:
          - name: b0
            status: done
  - name: fr
    depends-on: [b0]
    prs:
      - name: c-rel
        branch: feat/c-rel/u
        status: pending
        depends-on: []
        changes:
          - name: c-rel
            status: pending
EOF
for_card c-rel; mkdir -p "$C/.claude/worktrees/c-rel"
python3 -I - "$C" > "$OPSX_TEST_COLLECT_JSON" <<'PY'
import json, sys
top = sys.argv[1]
base = {"repo": "demo", "kind": "dev", "stage": "apply", "section": "待指派", "archived": False, "waiting": None, "open_gates": [],
        "dispatch": None, "agent_status": None, "mr": None, "stopped": None, "notes": [], "since": None, "dedup_checked": None}
print(json.dumps({"repo_paths": {"demo": top}, "errors": [], "cards": [dict(base, slug="c-rel", path="%s/openspec/changes/c-rel" % top)]}))
PY
printf '{"demo/c-rel":{"mode":"autopilot","agent":"claude","pane":"w1:p5","worktree":"%s","released_at":"%s","reaped_at":"%s"}}' "$C/.claude/worktrees/c-rel" "$R_AT" "$R_AT" > "$DISP"
printf '{}' > "$OPSX_STATE_DIR/coordinator-memo.json"; : > "$OPSX_FAKE_LOG"; : > "$OPSX_STATE_DIR/coordinator.log"
bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/coord.out" 2>&1 || fail "coordinate rc: $(cat "$FX/coord.out")"
assert_eq "$(grep -c '^opsx dispatch --feature fr ' "$OPSX_FAKE_LOG" || true)" 1 "放掉且收掉的成員交給 session：$(cat "$OPSX_FAKE_LOG")；$(cat "$OPSX_STATE_DIR/coordinator.log")"
echo "dispatch-release ok"
