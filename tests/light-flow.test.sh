#!/usr/bin/env bash
# 依 kind 減輕流程：router 跳過 grill、continue.md 的 Light flow 段、grill / propose / review 的文字契約。
# 只證明規則寫在對的地方且沒被反向改寫；agent 守不守由 eval 驗。驗收：openspec/changes/kind-light-flow/specs/light-flow/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$(dirname "$2")")/$(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }
bash_fn() { ( source "$OPSX_ROOT/bin/lib/common.sh"; source "$OPSX_ROOT/bin/lib/stage.sh"; "$@" ); }

# --- 1.1 chore 與 bug-fix 待決非空也不經 grill；其他 kind 照舊 ---
R="$(mk_repo light)"
mk_card() { # mk_card <slug> <kind>
  local d="$R/openspec/changes/$1"; mkdir -p "$d"
  printf 'schema: opsx\nkind: %s\n' "$2" > "$d/.openspec.yaml"
  printf '## 已知\n- x\n\n## 待決\n- 要不要 A？\n\n## 不做\n' > "$d/explore.md"
}
mk_card c-chore chore; mk_card c-bug bug-fix; mk_card c-dev dev; mk_card c-ops ops
assert_eq "$(bash_fn stage_name "$R" c-chore)" propose "chore 有待決 → propose"
assert_eq "$(bash_fn stage_name "$R" c-bug)" propose "bug-fix 有待決 → propose"
assert_eq "$(bash_fn stage_name "$R" c-dev)" grill "dev 有待決 → grill"
assert_eq "$(bash_fn stage_name "$R" c-ops)" grill "ops 有待決 → grill"

# --- explore 之後的下一站：spec Examples 七列，待決空的非 chore／bug-fix 也進 grill ---
mk_empty() { # mk_empty <slug> <kind>：待決段只有空白與註解
  mk_card "$1" "$2"
  printf '## 已知\n- x\n\n## 待決\n<!-- 無 -->\n\n## 不做\n- y\n' > "$R/openspec/changes/$1/explore.md"
}
mk_empty e-chore chore; mk_empty e-dev dev; mk_empty e-perf perf; mk_empty e-bug bug-fix
while IFS='|' read -r slug want; do
  assert_eq "$(bash_fn stage_name "$R" "$slug")" "$want" "explore 之後 [$slug]"
done <<'TABLE'
c-chore|propose
c-bug|propose
c-dev|grill
c-ops|grill
e-dev|grill
e-chore|propose
e-perf|grill
e-bug|propose
TABLE
mk_empty e-grilled dev; printf '# grill\n' > "$R/openspec/changes/e-grilled/grill.md"
assert_eq "$(bash_fn stage_name "$R" e-grilled)" propose "已有 grill.md 不再進 grill"
# grill 寫了部分 grill.md、待決還留著等前題的題：回 grill，不接 propose
mk_card c-left dev; printf '# grill\n' > "$R/openspec/changes/c-left/grill.md"
assert_eq "$(bash_fn stage_name "$R" c-left)" grill "有 grill.md 但待決還有題 → grill"
# 舊規則下已進 propose（有 proposal.md、沒 grill.md）的卡不送回 grill
mk_empty e-legacy dev; printf '# proposal\n' > "$R/openspec/changes/e-legacy/proposal.md"
assert_eq "$(bash_fn stage_name "$R" e-legacy)" propose "已有 proposal.md 的舊卡留在 propose"

CONT="$OPSX_ROOT/references/continue.md"
GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
PROP="$OPSX_ROOT/skills/propose/SKILL.md"
REV="$OPSX_ROOT/skills/review/SKILL.md"
for f in "$CONT" "$GRILL" "$PROP" "$REV"; do assert_file "$f"; done
section() { awk -v h="## $1" 'index($0,h)==1{on=1;print;next} /^## /{on=0} on' "$2"; }

# --- 1.2 grill 與 propose 的文字；continue.md 的 explore 兩列 ---
assert_fixed '| explore | `/opsx-workflow:grill <slug>` | kind is not chore or bug-fix, whether 待決 is empty or not' "$CONT"
assert_fixed '| explore | `/opsx-workflow:propose <slug>` | kind is chore or bug-fix |' "$CONT"
assert_fixed 'kind is chore or bug-fix' "$GRILL"
assert_fixed 'kind is chore or bug-fix' "$PROP"
assert_fixed '假設' "$PROP"
assert_fixed 'The exception is a card whose kind is chore or bug-fix' "$PROP"

# --- 2.1 continue.md 的 Light flow 段 ---
section "Light flow" "$CONT" > "$FX/sec-light"; [ -s "$FX/sec-light" ] || fail "continue.md has no '## Light flow' section"
assert_fixed 'tasks.md has at most 3 tasks' "$FX/sec-light"
assert_fixed 'first path component' "$FX/sec-light"
assert_fixed 'test paths' "$FX/sec-light"
assert_fixed 'Only kind chore or bug-fix' "$FX/sec-light"
assert_fixed 'Consider never blocks the flow' "$FX/sec-light"

# --- 2.2 小卡只一個合併 reviewer，其他卡三個 ---
assert_fixed 'one merged reviewer' "$REV"
assert_fixed '../../references/continue.md' "$REV"
assert_fixed 'Light flow' "$REV"
assert_not_fixed 'Three agents every time;' "$REV"
assert_fixed 'Three agents every time except a small card' "$REV"

# --- 2.3 輪數、第三次不審、Consider 不開 gate ---
assert_fixed '# Review · <slug> · 第 <N> 輪 · <date> · <commit>' "$REV"
section "Step 0" "$REV" > "$FX/sec-step0"; [ -s "$FX/sec-step0" ] || fail "review has no '## Step 0' section"
assert_fixed 'Read the round from report.md' "$FX/sec-step0"
assert_fixed 'two rounds' "$FX/sec-step0"
assert_fixed 'does not start a reviewer' "$FX/sec-step0"
assert_fixed 'Consider never opens a gate' "$REV"

# --- review 回歸：後面幾輪重寫 report.md 時保留 pr 附加的 ## MR ---
awk 'index($0,"## Step 5")==1{on=1;print;next} /^## (Step|Guardrails)/{on=0} on' "$REV" > "$FX/sec-step5"; [ -s "$FX/sec-step5" ] || fail "review has no '## Step 5' section"
assert_fixed 'keeps an existing `## MR` section verbatim' "$FX/sec-step5"
assert_fixed 'Consider never opens a gate' "$CONT"

# --- review-fix-in-scope：範圍內退回 apply，第 2 輪後確認而不重審 ---
assert_fixed 'confirm pass' "$FX/sec-step0"
assert_fixed '待修（範圍內）' "$FX/sec-step0"
assert_fixed '| review | `/opsx-workflow:apply <slug>` | `待修（範圍內）` has items |' "$CONT"
assert_fixed '| review | `/opsx-workflow:pr <slug>` | no `待修（範圍內）` item left open (Consider does not count) |' "$CONT"
assert_fixed '確認: <sha>' "$FX/sec-light"
assert_not_fixed 'a gate lists the Bug and Must-fix items still open' "$CONT"
# report.md 在、沒有 MR，但 review 退回的 R task 還沒勾 → apply，不是 pr
mk_card c-back dev
printf '## 1. x\n\n- [x] 1.1 a\n\n## R1. review 退回\n\n- [ ] R1.1 b\n' > "$R/openspec/changes/c-back/tasks.md"
printf '# Review · c-back · 第 1 輪\n### 待修（範圍內）\n- a.sh:1 x\n' > "$R/openspec/changes/c-back/report.md"
assert_eq "$(bash_fn stage_name "$R" c-back)" apply "report 在且 R task 未勾 → apply"
printf '## 1. x\n\n- [x] 1.1 a\n\n## R1. review 退回\n\n- [x] R1.1 b\n' > "$R/openspec/changes/c-back/tasks.md"
assert_eq "$(bash_fn stage_name "$R" c-back)" pr "report 在且 task 全勾 → pr"
