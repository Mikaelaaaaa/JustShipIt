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
assert_fixed 'there is neither `grill.md` nor `proposal.md`' "$PROP"
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
assert_fixed 'read every source in `## What to read`' "$FX/steps"
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
while IFS= read -r row; do assert_fixed "$row" "$FX/reopen"; done <<'ROWS'
| 不做 | LINE 與自動草稿的工具組不動 | yes |
| 已知 | role_gate 沒有任何執行期讀取端 | yes |
| 已知 | getUserAppRoles 回三個模組的角色 slug | yes |
| 已知 | stage.sh 的 stage_of 依 kind 與 grill.md 決定下一站 | no: pure fact |
| 已知 | 母卡 grill.md 已定 D3：不改 role_gate | no: the user answered it on the parent card |
| 不做 | 不改 eval fixture 的 schema 複本 | yes: every 不做 is confirmed |
ROWS
assert_not_fixed 'stage.sh 第 182 行' "$GRILL"

# --- R1.2 沒有要問的分支也一定寫 grill.md ---
assert_fixed 'Always write grill.md' "$GRILL"
assert_fixed '- 無：所有分支由 已知 解決' "$GRILL"

# --- R1.3 openspec/ 底下的檔從主 checkout 讀；母卡比對整項 ---
assert_fixed 'from the main checkout' "$FX/read"
assert_fixed 'a whole item of the `split_into:` list' "$FX/read"

# --- R1.4 Step 1 先看 kind；autopilot 下不做與藏著選擇的已知一律是使用者題 ---
grep -m1 -E '^1\. ' "$FX/steps" | grep -q '^1\. Kind chore or bug-fix: reply' || fail "Step 1 要先看 kind"
assert_fixed 'Every 不做 item and every 已知 entry that hides a choice is a product choice' "$FX/auto"

# --- R2.2 等前題的題用 router 認得的標記；重進 grill 讀自己的 grill.md 與 gates.md，D 接著編號 ---
assert_fixed '  - waits on gate: <gate id>' "$FX/auto"
assert_fixed "The card's own \`grill.md\` and \`gates.md\`" "$FX/read"
assert_fixed 'continue numbering after the last D' "$FX/read"
assert_fixed 'If `grill.md` exists but an item in 待決 still carries `waits on gate:`' "$PROP"
assert_fixed 'If there is no `grill.md` but `proposal.md` exists and 待決 still lists an item, stop the same way' "$PROP"
assert_fixed 'if 2b changes it to anything else while there is neither `grill.md` nor `proposal.md`' "$PROP"

# --- R2.3 explore 模板的待決註解 ---
assert_not_fixed '空的話直接 /propose' "$OPSX_ROOT/schemas/opsx/templates/explore.md"
assert_fixed 'kind 不是 chore 或 bug-fix 時，空的也接 /grill' "$OPSX_ROOT/schemas/opsx/templates/explore.md"

# --- R2.4 autopilot 下使用者答不做或藏著選擇的已知，答案都寫成 D ---
assert_fixed "the user's answer becomes a D whether it keeps the item as it is or changes it" "$FX/auto"

# --- R1.5 舊規則殘句 ---
for s in '待決為空 → 直接 propose' 'explore 做完待決非空' '改為待決段為空即跳過' '只在 explore.md 待決非空時有事'; do assert_not_fixed "$s" "$REQ"; done
assert_not_fixed '待決非空就 `/grill`' "$OPSX_ROOT/docs/HANDOFF.md"

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
