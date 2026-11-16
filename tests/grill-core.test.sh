#!/usr/bin/env bash
# grill 以 grill-me 為核心、非 chore／bug-fix 一律經 grill 的文字契約。只證明規則寫在對的地方且舊規則已移除；agent 守不守由 eval 驗。
# 驗收：openspec/changes/me-20261116-1046/specs/grill-core/spec.md、specs/light-flow/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $2"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $2"; }

CONT="$OPSX_ROOT/references/continue.md"
EXP="$OPSX_ROOT/skills/explore/SKILL.md"
PROP="$OPSX_ROOT/skills/propose/SKILL.md"
HEAD="$OPSX_ROOT/schemas/opsx/artifacts-head.yaml"
REQ="$OPSX_ROOT/docs/rewrite-requirements-pstack-grill.md"

# --- 2.1 接站文字：非 chore／bug-fix 一律經 grill，沒有「待決空就直接 propose」 ---
assert_fixed '| explore | `/opsx-workflow:grill <slug>` | kind is not chore or bug-fix, whether 待決 is empty or not |' "$CONT"
assert_fixed '| explore | `/opsx-workflow:propose <slug>` | kind is chore or bug-fix |' "$CONT"
assert_not_fixed '待決 empty, or kind is chore or bug-fix' "$CONT"
assert_not_fixed 'an empty one straight to /propose' "$EXP"
assert_not_fixed '`/opsx-workflow:propose <slug>` when it is empty' "$EXP"
assert_fixed 'kind is chore or bug-fix' "$EXP"
assert_not_fixed 'If `explore.md` has a non-empty 待決 and no `grill.md`' "$PROP"
assert_not_fixed '待決空 → 直接 /propose' "$HEAD"
assert_not_fixed '只在 explore.md 的待決非空時才有' "$HEAD"
assert_not_fixed '回一句「沒有待決」就停' "$REQ"
assert_not_fixed '空 → 回「沒有待決」停' "$REQ"
assert_not_fixed '| 有 explore.md，待決段非空，沒 grill.md |' "$REQ"

GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
section() { awk -v h="## $1" '/^```/{f=!f} !f && /^## /{on=(index($0,h)==1); if(on) print; next} on' "$2"; }
awk '/^---$/{n++; next} n==1' "$GRILL" > "$FX/desc"
section "Steps" "$GRILL" > "$FX/steps"
section "Core" "$GRILL" > "$FX/core"
section "What to read" "$GRILL" > "$FX/read"
section "Reopen 已知 and 不做" "$GRILL" > "$FX/reopen"
section "In autopilot" "$GRILL" > "$FX/auto"

# --- 3.1 grill-me 為核心；待決空不停；chore／bug-fix 照舊不跑 ---
[ -s "$FX/core" ] || fail "grill has no '## Core' section"
assert_fixed 'Interview the user relentlessly about every aspect of their plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.' "$FX/core"
assert_fixed 'skills-retired-20261110/grill-me/SKILL.md' "$FX/core"
assert_not_fixed 'non-empty 待決' "$FX/desc"
assert_not_fixed 'If 待決 is empty there is nothing to do' "$FX/desc"
assert_fixed 'even when 待決 is empty' "$FX/desc"
assert_fixed 'chore or bug-fix' "$FX/desc"
assert_not_fixed '沒有待決' "$GRILL"
assert_fixed 'Read every source in `## What to read`' "$FX/steps"
assert_fixed 'even when 待決 is empty' "$FX/steps"
assert_fixed '不經 grill，直接 /opsx-workflow:propose' "$GRILL"

# --- 3.2 讀全部來源，母卡兩種找法，沒有母卡不問 ---
[ -s "$FX/read" ] || fail "grill has no '## What to read' section"
for k in 'inbox.md' '## 派工指示' '## 已知' '## 待決' '## 不做' 'CONTEXT.md' 'docs/adr/' 'openspec/workplan.yaml' 'split_into:' 'parent:' 'grill.md'; do
  assert_fixed "$k" "$FX/read"
done
assert_fixed 'A D the parent card already decided is not asked again' "$FX/read"
assert_fixed 'No parent card: do not look further and do not ask about it' "$FX/read"

# --- 3.3 已知裡藏著選擇的條目與每條不做當分支，純事實不問 ---
[ -s "$FX/reopen" ] || fail "grill has no '## Reopen 已知 and 不做' section"
assert_not_fixed 'It does not reopen things explore already put in 已知 or 不做' "$GRILL"
assert_fixed 'Every 不做 item is a branch' "$FX/reopen"
assert_fixed 'hides a choice' "$FX/reopen"
assert_fixed 'pure fact' "$FX/reopen"
for k in 'LINE' 'role_gate' 'getUserAppRoles' 'stage.sh' '母卡 grill.md 已定' 'eval fixture'; do assert_fixed "$k" "$FX/reopen"; done

# --- 3.4 autopilot：不相依的一次全開，相依的等；有 open gate 不接 propose ---
assert_fixed 'Open every bucket-3 gate that does not depend on another at once, each as its own gate' "$FX/auto"
assert_fixed 'waits on' "$FX/auto"
assert_fixed 'While any gate is open, do not continue to /opsx-workflow:propose' "$FX/auto"
assert_not_fixed 'Once 待決 is empty, propose comes next as usual' "$GRILL"

# --- 4.1 eval：待決空的 dev 卡照樣 grill ---
EV="$OPSX_ROOT/skills/grill/evals/evals.json"
python3 -I - "$EV" <<'PY' || fail "grill eval 1 is not empty-pending-still-grills"
import json, sys
e = {x["id"]: x for x in json.load(open(sys.argv[1]))["evals"]}[1]
assert e["name"] == "empty-pending-still-grills", e["name"]
a = " ".join(e["assertions"])
assert "no 待決" not in a and "No grill.md was written" not in a, a
for k in ("沒有待決", "questions.md", "不做匯入", "不做 CSV", "src/"):
    assert k in a, k
PY
assert_not_fixed 'empty-pending-stops' "$EV"

echo "ok grill-core"
