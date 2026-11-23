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
relcard() { # <slug> [tasks] [note]：卡目錄；第二個參數有值寫 tasks.md，第三個參數是派工指示那一條的文字
  local d="$O/openspec/changes/$1"; mkdir -p "$d"
  printf -- '---\nsource: me\n---\n\n## 一句話\n\n%s\n\n## 派工指示\n\n- 2026-11-22T10:00:00+08:00 %s\n' "$1" "${3:-做到 propose 完成就停（協調者補卡）}" > "$d/inbox.md"
  [ -z "${2:-}" ] || printf '## 1\n\n- [ ] 1.1 a\n' > "$d/tasks.md"
}
relcard a t

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
# 不是 propose 完的補卡（反例）：沒有 tasks.md、派工指示沒有補卡記號，都拒絕、點名卡與原因、dispatch.json 不變
relcard nt; relcard nm t "做到 propose 完成就停（留在待指派），不要 apply"
printf '{"o/nt":{"mode":"autopilot","pane":"w1:p1"},"o/nm":{"mode":"autopilot","pane":"w1:p2"}}' > "$DISP"; cp "$DISP" "$FX/before"
out="$(opsx release nt --repo "$O" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] || fail "沒有 tasks.md 要退出非 0"
case "$out" in *o/nt*tasks.md*) ;; *) fail "stderr 要含卡名與 tasks.md：$out" ;; esac
cmp -s "$DISP" "$FX/before" || fail "沒有 tasks.md 時 dispatch.json 不能動"
out="$(opsx release nm --repo "$O" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] || fail "沒有補卡記號要退出非 0"
case "$out" in *o/nm*協調者補卡*) ;; *) fail "stderr 要含卡名與補卡記號：$out" ;; esac
cmp -s "$DISP" "$FX/before" || fail "沒有補卡記號時 dispatch.json 不能動"

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
CARDS="c-wait c-done c-stop c-gone c-reuse c-relaunch c-old"
for s in $CARDS; do for_card "$s"; done
python3 -I - "$C" $CARDS > "$OPSX_TEST_COLLECT_JSON" <<'PY'
import json, sys
top = sys.argv[1]
base = {"repo": "demo", "kind": "dev", "stage": "apply", "section": "待指派", "archived": False, "waiting": None, "open_gates": [],
        "dispatch": None, "agent_status": None, "mr": None, "stopped": None, "notes": [], "since": None, "dedup_checked": None}
print(json.dumps({"repo_paths": {"demo": top}, "errors": [],
                  "cards": [dict(base, slug=s, path="%s/openspec/changes/%s" % (top, s)) for s in sys.argv[2:]]}))
PY
NOW_AT="$(python3 -I -c 'import datetime; print(datetime.datetime.now().astimezone().isoformat(timespec="seconds"))')"
W="$C/.claude/worktrees"
# c-wait 剛放掉、c-old 放掉超過一輪，pane 都還在自己的 worktree；c-reuse 的 pane id 被 herdr 重用給別處的 pane；
# c-gone 的 pane 不在清單；c-relaunch 的 pane 不在清單但正在 relaunch
python3 -I - "$DISP" "$W" "$R_AT" "$NOW_AT" <<'PY'
import json, sys
disp, w, old, now = sys.argv[1:]
def rel(pane, slug, at, **extra):
    return dict({"mode": "autopilot", "agent": "claude", "pane": pane, "worktree": "%s/%s" % (w, slug), "released_at": at}, **extra)
d = {"demo/c-wait": rel("w1:p2", "c-wait", now), "demo/c-old": rel("w1:p6", "c-old", old),
     "demo/c-gone": rel("w1:p9", "c-gone", old), "demo/c-reuse": rel("w1:p7", "c-reuse", old),
     "demo/c-relaunch": rel("w1:p8", "c-relaunch", old, relaunching_at=now),
     "demo/c-done": rel("w1:p1", "c-done", old, reaped_at=old),
     "demo/c-stop": {"mode": "stopped", "agent": "claude", "pane": "w1:p3"}}
json.dump(d, open(disp, "w"))
PY
{ printf '{"id":"cli:agent:list","result":{"agents":['
  agent w1:p2 idle "$W/c-wait"; printf ','
  agent w1:p6 blocked "$W/c-old"; printf ','
  agent w1:p7 working "$FX/elsewhere"
  printf '],"type":"agent_list"}}'; } > "$FX/agents-coord.json"
export OPSX_TEST_HERDR_AGENTS="$FX/agents-coord.json"
: > "$OPSX_FAKE_LOG"; : > "$OPSX_STATE_DIR/coordinator.log"
bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/coord.out" 2>&1 || fail "coordinate rc: $(cat "$FX/coord.out")"
CLOG="$OPSX_STATE_DIR/coordinator.log"
assert_eq "$(grep -c '^opsx dispatch c-done ' "$OPSX_FAKE_LOG" || true)" 1 "收掉後照 P1 規則派一次：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-wait ' "$OPSX_FAKE_LOG" || true)" 0 "pane 還沒收不派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-stop ' "$OPSX_FAKE_LOG" || true)" 0 "人停的卡照舊不派"
grep -q -- '-- demo/c-wait.*reap' "$CLOG" || fail "剛放掉的 log 要有一行 -- 含 c-wait 與 reap：$(cat "$CLOG")"
grep 'demo/c-wait' "$CLOG" | grep -q '??' && fail "剛放掉的不記 ??：$(cat "$CLOG")"
# 放掉超過 REDISPATCH_MINUTES 還沒收：記 ?? 點名卡、pane 與 agent 狀態，照樣不派
grep '?? demo/c-old' "$CLOG" | grep 'w1:p6' | grep -q 'blocked' || fail "放掉超過一輪的要記 ?? 含 c-old、pane 與 blocked：$(cat "$CLOG")"
assert_eq "$(grep -c '^opsx dispatch c-old ' "$OPSX_FAKE_LOG" || true)" 0 "放掉超過一輪、pane 還在也不派"
# pane 不在 agent 清單：先關一次 pane 再記 pane_closed_at，照 P1 派
assert_eq "$(grep -c '^pane close w1:p9$' "$OPSX_FAKE_LOG" || true)" 1 "pane 不在 agent 清單時送一次 pane close：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-gone ' "$OPSX_FAKE_LOG" || true)" 1 "pane 已不在 herdr 的放掉條目當成已收，照 P1 派：$(cat "$OPSX_FAKE_LOG")"
[ -n "$(field demo/c-gone pane_closed_at)" ] || fail "pane 已不在 herdr 要記 pane_closed_at，dispatch.sh 才放行：$(cat "$DISP")"
[ -z "$(field demo/c-wait pane_closed_at)" ] || fail "pane 還在 herdr 的不記：$(cat "$DISP")"
# pane id 在、cwd 在別的 worktree：那是 herdr 重用 id 給的別人的 pane，當成已收、不關它，照 P1 派
[ -n "$(field demo/c-reuse pane_closed_at)" ] || fail "pane id 被重用的要記 pane_closed_at：$(cat "$DISP")"
assert_eq "$(grep -c '^opsx dispatch c-reuse ' "$OPSX_FAKE_LOG" || true)" 1 "pane id 被重用的照 P1 派：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^pane close w1:p7$' "$OPSX_FAKE_LOG" || true)" 0 "不關別人的 pane：$(cat "$OPSX_FAKE_LOG")"
# relaunch 中：claude 已 /exit 所以不在清單，不關、不記
[ -z "$(field demo/c-relaunch pane_closed_at)" ] || fail "relaunch 中的不記 pane_closed_at：$(cat "$DISP")"
assert_eq "$(grep -c '^pane close w1:p8$' "$OPSX_FAKE_LOG" || true)" 0 "relaunch 中的不關 pane：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(grep -c '^opsx dispatch c-relaunch ' "$OPSX_FAKE_LOG" || true)" 0 "relaunch 中的不派"
unset OPSX_TEST_HERDR_AGENTS

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
# worktree 還在：分支還 checkout 在那棵 worktree，照 P1 單卡派回原本的 worktree，feature session 不交它
assert_eq "$(grep -c '^opsx dispatch c-rel ' "$OPSX_FAKE_LOG" || true)" 1 "worktree 還在的放掉補卡單卡派：$(cat "$OPSX_FAKE_LOG")；$(cat "$OPSX_STATE_DIR/coordinator.log")"
assert_eq "$(grep -c '^opsx dispatch --feature fr ' "$OPSX_FAKE_LOG" || true)" 0 "worktree 還在時 feature session 不交它：$(cat "$OPSX_FAKE_LOG")"
# worktree 不在：不再佔著分支，交給 session
rmdir "$C/.claude/worktrees/c-rel"
printf '{}' > "$OPSX_STATE_DIR/coordinator-memo.json"; : > "$OPSX_FAKE_LOG"; : > "$OPSX_STATE_DIR/coordinator.log"
bash "$OPSX_ROOT/bin/opsx" coordinate > "$FX/coord.out" 2>&1 || fail "coordinate rc: $(cat "$FX/coord.out")"
assert_eq "$(grep -c '^opsx dispatch --feature fr ' "$OPSX_FAKE_LOG" || true)" 1 "worktree 不在的放掉補卡交給 session：$(cat "$OPSX_FAKE_LOG")；$(cat "$OPSX_STATE_DIR/coordinator.log")"
assert_eq "$(grep -c '^opsx dispatch c-rel ' "$OPSX_FAKE_LOG" || true)" 0 "worktree 不在時不單卡派：$(cat "$OPSX_FAKE_LOG")"
echo "dispatch-release ok"
