#!/usr/bin/env bash
# opsx status：寫 changes/<slug>/status.json。對應要求檔 §3.6 新增的儲存 6。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo Acmecorp-AI)"; mk_change "$R" eval-core; cd "$R"
S="$R/openspec/changes/eval-core/status.json"

# --- 正常：從 branch 推 slug ---
opsx status apply 4/8 "實作 + self-check" || fail "status rc"
assert_file "$S"
python3 -I - "$S" <<'PY' || fail "status.json shape"
import json,sys,re
d=json.load(open(sys.argv[1]))
assert d["phase"]=="apply" and d["step"]==4 and d["total"]==8, d
assert d["label"]=="實作 + self-check", d
assert d["tests"]=="unknown", d
assert re.match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$", d["at"]), d["at"]
PY

# --- tests 旗標：寫了就留，下一次沒給要保留 ---
opsx status apply 8/8 "測試 agent" --tests green || fail "tests flag"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["tests"]=="green",d' "$S"
opsx status review 1/7 "diff" || fail "status 2"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["tests"]=="green" and d["phase"]=="review",d' "$S"

# --- --change 指定 slug（不在卡的 branch 上也能寫）---
mkdir -p "$R/openspec/changes/other"; printf 'schema: opsx\n' > "$R/openspec/changes/other/.openspec.yaml"
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" checkout -q main
opsx status explore 1/8 "讀 inbox" --change other || fail "--change"
assert_file "$R/openspec/changes/other/status.json"

# --- 邊界：branch 對不到卡、也沒 --change → rc 2，不亂寫 ---
assert_rc 2 opsx status apply 1/8 x
assert_no_file "$R/openspec/changes/main"

# --- 邊界：phase 不在清單、step 格式錯、step > total、指定的卡不存在 → rc 2 ---
git -C "$R" checkout -q feat/eval-core/mikaela
assert_rc 2 opsx status deploy 1/8 x
assert_rc 2 opsx status apply 4 x
assert_rc 2 opsx status apply 9/8 x
assert_rc 2 opsx status apply 1/8 x --tests maybe
assert_rc 2 opsx status apply 1/8 x --change nope

# --- --show 印目前的，沒有檔印 none ---
out="$(opsx status --show)"; echo "$out" | grep -q "review 1/7" || fail "show: $out"
rm "$S"; out="$(opsx status --show)"; assert_eq "$out" "none"

# --- worker：一般分支是 session ---
opsx status apply 1/3 x || fail "worker session"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="session",d' "$S"

# --- 子殼分支 <主>--<子>：寫子殼的 status.json，worker 是 subagent-<子>，主殼不動 ---
mkdir -p "$R/openspec/changes/eval-core/subs/s1"
cp "$S" "$S.before"
git -C "$R" checkout -q -b feat/eval-core--s1/mikaela
opsx status apply 1/3 "子" || fail "子殼分支 rc"
SS="$R/openspec/changes/eval-core/subs/s1/status.json"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="subagent-s1" and d["label"]=="子",d' "$SS"
diff -q "$S" "$S.before" >/dev/null || fail "子殼分支不該動主殼 status.json"

# --- 子殼不存在：rc 2，訊息含它要找的路徑 ---
git -C "$R" checkout -q -b feat/eval-core--nope/mikaela
out="$(opsx status apply 1/3 x 2>&1)"; rc=$?
assert_eq "$rc" 2 "子殼不存在 rc"
echo "$out" | grep -q 'openspec/changes/eval-core/subs/nope' || fail "子殼不存在的訊息: $out"

# --- --sub / --worker：session 在主 change 分支上替子殼寫 ---
git -C "$R" checkout -q feat/eval-core/mikaela
rm "$SS"
opsx status apply 2/3 y --sub s1 --worker subagent-s1 || fail "--sub rc"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="subagent-s1" and d["step"]==2,d' "$SS"
opsx status apply 3/3 z --sub s1 || fail "--sub 無 --worker"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="session",d' "$SS"
assert_rc 2 opsx status apply 1/3 x --sub nope

# --- status-card-lookup：分支名對不到卡時用 dispatch worktree 名 ---
Q="$(mk_repo Acmecorp-CS)"; W="$Q/.claude/worktrees"
mkcard() { mkdir -p "$Q/openspec/changes/$1"; printf 'schema: opsx\n' > "$Q/openspec/changes/$1/.openspec.yaml"; }
phase_of() { python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["phase"])' "$Q/openspec/changes/$1/status.json"; }
for c in other-card my-card me-1402 parent child a b m; do mkcard "$c"; done
mkdir -p "$Q/openspec/changes/m/subs/s"
git -C "$Q" checkout -q -b fix/other-card/mikaela
git -C "$Q" worktree add -q -b feat/my-card/mikaela "$W/my-card"
git -C "$Q" worktree add -q -b feat/switch-off-popup/mikaela "$W/me-1402"
git -C "$Q" worktree add -q -b feat/no-card/mikaela "$W/agent-x"
git -C "$Q" worktree add -q -b feat/child/mikaela "$W/parent"
git -C "$Q" worktree add -q -b feat/a/mikaela "$W/a"
git -C "$Q" worktree add -q -b feat/m--s/mikaela "$FX/sub-wt"
nostatus() { [ -z "$(find "$Q/openspec" -name status.json)" ] || fail "不該有 status.json：$(find "$Q/openspec" -name status.json)"; }

# 分支名就是卡名（正例）
( cd "$W/my-card" && opsx status apply 1/3 x ) || fail "分支名就是卡名 rc"
assert_eq "$(phase_of my-card)" apply "分支名就是卡名"
rm "$Q/openspec/changes/my-card/status.json"

# 分支名不是卡名時用 dispatch worktree 名（正例）
( cd "$W/me-1402" && opsx status apply 1/3 x ) || fail "worktree 名 rc"
assert_eq "$(phase_of me-1402)" apply "worktree 名"
rm "$Q/openspec/changes/me-1402/status.json"

# 分支和 worktree 名都對不到卡（反例）
( cd "$W/agent-x" && opsx status apply 1/3 x ) 2>/dev/null; assert_eq "$?" 2 "都對不到 rc"
nostatus

# --- status-card-lookup：dispatch 的 agent 在主 checkout 寫自己 pane 的卡 ---
# agent 在主 checkout 寫自己 pane 的卡（正例）
( cd "$Q" && OPSX_CARD=my-card opsx status explore 2/9 x ) || fail "pane 的卡 rc"
assert_eq "$(phase_of my-card)" explore "pane 的卡"
assert_no_file "$Q/openspec/changes/other-card/status.json"
rm "$Q/openspec/changes/my-card/status.json"

# pane worktree 已切到續接的子卡（正例）
( cd "$Q" && OPSX_CARD=parent opsx status apply 1/2 x ) || fail "續接子卡 rc"
assert_eq "$(phase_of child)" apply "續接子卡"
assert_no_file "$Q/openspec/changes/parent/status.json"
rm "$Q/openspec/changes/child/status.json"

# agent 的 pane worktree 不在時拒寫（反例）
out="$(cd "$Q" && OPSX_CARD=gone opsx status apply 1/2 x 2>&1)"; assert_eq "$?" 2 "pane worktree 不在 rc"
echo "$out" | grep -qF "$W/gone" || fail "pane worktree 不在的訊息沒有路徑: $out"
echo "$out" | grep -qF -- "--change" || fail "pane worktree 不在的訊息沒有 --change: $out"
nostatus

# subagent 在自己的 worktree 不看 OPSX_CARD（反例）
( cd "$FX/sub-wt" && OPSX_CARD=m opsx status apply 1/2 x ) || fail "subagent rc"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["worker"]=="subagent-s",d' "$Q/openspec/changes/m/subs/s/status.json"
assert_no_file "$Q/openspec/changes/m/status.json"
rm "$Q/openspec/changes/m/subs/s/status.json"

# --- status-card-lookup：沒有 OPSX_CARD 時主 checkout 照分支推，--change 永遠優先 ---
# 人在主 checkout 照分支推（正例）
( cd "$Q" && opsx status review 1/7 x ) || fail "人在主 checkout rc"
assert_eq "$(phase_of other-card)" review "人在主 checkout"
rm "$Q/openspec/changes/other-card/status.json"

# --change 蓋過 OPSX_CARD（反例）
( cd "$Q" && OPSX_CARD=a opsx status pr 5/5 x --change b ) || fail "--change rc"
assert_eq "$(phase_of b)" pr "--change 蓋過 OPSX_CARD"
assert_no_file "$Q/openspec/changes/a/status.json"
echo ok
