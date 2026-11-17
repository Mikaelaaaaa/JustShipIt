#!/usr/bin/env bash
# skill 的範圍規則：卡範圍內同一張修，範圍外開卡帶「做到 propose 就停」派工指示，範圍題不開 gate。
# 只證明規則寫在對的段落；agent 守不守由 eval 驗。對應 openspec/changes/scope-routing-skills/specs/scope-routing。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
hasnt() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

APPLY="$OPSX_ROOT/skills/apply/SKILL.md"
REVIEW="$OPSX_ROOT/skills/review/SKILL.md"
GRILL="$OPSX_ROOT/skills/grill/SKILL.md"
EXPLORE="$OPSX_ROOT/skills/explore/SKILL.md"
LMAP="$OPSX_ROOT/skills/logic-map/SKILL.md"
LEAD="$OPSX_ROOT/skills/lead/SKILL.md"
PROPOSE="$OPSX_ROOT/skills/propose/SKILL.md"
NOTE='做到 propose 完成就停（留在待指派），不要 apply'

grep -F '| 6 |' "$APPLY" > "$FX/apply6"
grep -F -- '- **範圍外.**' "$REVIEW" > "$FX/review-oos"
grep -F -- '- **Logic map, undecided.**' "$REVIEW" > "$FX/review-lm"
awk '/^## Answering questions about a map/{on=1} /^## Output template/{on=0} on' "$LMAP" > "$FX/lmap-qa"
grep -F '2. **Forward gates' "$LEAD" > "$FX/lead2"
awk '/^## 怎麼問 gate/{on=1;next} /^## /{on=0} on' "$LEAD" > "$FX/lead-ask"
grep -F 'dispatch-<' "$PROPOSE" > "$FX/propose-dispatch"
for f in apply6 review-oos review-lm lmap-qa lead2 lead-ask propose-dispatch; do [ -s "$FX/$f" ] || fail "段落找不到：$f"; done

# --- apply 以卡範圍判開卡（正例／反例）---
has "this card's scope" "$FX/apply6"
has 'add a task' "$FX/apply6"
hasnt "outside this task's scope" "$FX/apply6"

# --- 開卡的 skill 都寫派工指示（Scenario Outline：review、apply、grill、explore）---
for f in "$FX/apply6" "$FX/review-oos" "$GRILL" "$EXPLORE"; do
  has 'opsx note' "$f"
  has "$NOTE" "$f"
done

# --- 併進別張卡時不寫指示（反例）---
has 'skip `opsx note` when it merged' "$FX/apply6"
has 'skip `opsx note` when it merged' "$FX/review-oos"

# --- skill 明寫範圍不問人（Scenario Outline：review、apply、grill、explore）---
for f in "$APPLY" "$REVIEW" "$GRILL" "$EXPLORE"; do
  has 'never a gate option' "$f"
  has '範圍內的產品取捨' "$f"
done

# --- 範圍內的產品取捨仍開 gate（反例）---
has 'is still bucket 3' "$GRILL"

# --- review 先判 ⚠ 的範圍 ---
has '（既有）' "$FX/review-lm"
has '範圍外' "$FX/review-lm"
has 'opens a card instead of entering the gate' "$FX/review-lm"

# --- logic-map 問答標範圍外／不開卡 ---
has '範圍外，review 會開卡' "$FX/lmap-qa"
hasnt 'opsx new' "$FX/lmap-qa"
has 'Do not write or change any file' "$FX/lmap-qa"

# --- 協調者判範圍題（正例）／其他 gate 仍不代答（反例）---
has '協調者判定：範圍內' "$FX/lead2"
has '協調者判定：範圍外' "$FX/lead2"
has '④' "$FX/lead2"
has 'never answer' "$FX/lead2"
has '不代答' "$FX/lead-ask"

# --- P2 討論卡 propose 完開派工 gate（正例／反例）---
has '做到 propose 完成就停' "$FX/propose-dispatch"
has 'P2' "$FX/propose-dispatch"
has 'A card without that note gets no such gate' "$PROPOSE"

# --- propose-stop 指示在 apply 時失效（正例／反例）---
grep -F '做到 propose 完成就停' "$APPLY" | grep -F 'tasks.md' > "$FX/apply-expiry"
[ -s "$FX/apply-expiry" ] || fail "apply 沒有講「做到 propose 完成就停」在有 tasks.md 時失效"
has 'open no gate' "$FX/apply-expiry"
has 'only once the card already has tasks.md' "$FX/apply-expiry"

echo "scope-routing OK"
