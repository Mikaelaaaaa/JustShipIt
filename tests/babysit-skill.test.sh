#!/usr/bin/env bash
# skills/babysit/SKILL.md：threads-only 的 push wave 之後、回覆之前照 review 的產表步重產邏輯表檔案（不發留言）；
# check、merge 與沒 push 的輪次不重產。skill 是文字，只能檢查 skill 寫了什麼。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

# 步 8 一段：從 `8. ` 那行到 `9. ` 那行之前
STEP="$FX/step8"
awk '/^8\. /{on=1} /^9\. /{on=0} on' "$SK" > "$STEP"
[ -s "$STEP" ] || fail "skills/babysit/SKILL.md 沒有步 8"

# --- 重產照 review 的產表步，不複製指令；編輯 report.md 記的那則 ---
assert_fixed '../review/SKILL.md' "$STEP"
assert_fixed 'step 1b' "$STEP"
assert_fixed '## 邏輯表' "$STEP"
assert_fixed 'openspec/changes/<slug>/logic-map.md' "$STEP"
! grep -qF 'gh pr comment' "$STEP" || fail "babysit 複製了 5c 的指令"

# --- 順序：push wave 之後、回覆之前 ---
python3 -I - "$STEP" <<'PY' || fail "重產不在 push wave 與回覆之間"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
push = text.index("Push that wave")
regen = text.index("regenerate the logic map")
reply = text.index("On GitLab, reply")
if not push < regen < reply:
    sys.exit("順序：push=%d regen=%d reply=%d" % (push, regen, reply))
PY

# --- R1.4 只跑產表步的子步，出口回 babysit 回覆，不走 pr 步 6（它會再叫 babysit）；remote 照 pr 步 1 的規則 ---
assert_fixed 'run sub-steps 1–4 of `../review/SKILL.md` step 1b' "$STEP"
assert_not_fixed 'step 5c' "$STEP"
assert_fixed 'come back here and reply to the threads; never run pr step 6' "$STEP"
assert_fixed '`<remote>` is the primary remote by pr step 1'"'"'s rule' "$STEP"

# --- 只重產檔，不發也不改留言 ---
assert_not_fixed 'edit the comment' "$STEP"
assert_not_fixed 'post a new comment' "$STEP"
assert_not_fixed 'no `## 邏輯表` line' "$STEP"
assert_fixed 'overwrite' "$STEP"

# --- 步 8 只在 push 後重產；merge 模式永不重產（「merge 模式不重產」）---
assert_fixed 'only a `threads-only` run that pushed regenerates the map' "$STEP"
assert_fixed 'The `merge <sha>` mode never regenerates it;' "$STEP"
assert_fixed 'regenerates it only through the comparison in step 1' "$STEP"
assert_not_fixed 'the `check` mode, the `merge <sha>` mode' "$STEP"
assert_not_fixed 'never regenerate it' "$STEP"

# --- 步 8 重產停在 gate 時不回 thread（「push 之後重產失敗不回 thread」）---
assert_not_fixed 'Wherever step 1b ends' "$STEP"
assert_fixed 'When step 1b stops at a gate, stop there and reply to no thread' "$STEP"

# --- 一進來比對 HEAD（specs/pr-logic-map「babysit 一進來比對 HEAD」）---
ENTRY="$FX/step1"
awk '/^1\. /{on=1} /^2\. /{on=0} on' "$SK" > "$ENTRY"
[ -s "$ENTRY" ] || fail "skills/babysit/SKILL.md 沒有步 1"
grep -F '**Logic map first.**' "$ENTRY" > "$FX/entry"; [ -s "$FX/entry" ] || fail "步 1 缺 Logic map first"
for k in 'In `check` and `threads-only`' 'before step 5' '## 邏輯表' 'equal to the first 7 characters of `git rev-parse HEAD`' \
  'or starts with `skip：`' 'spawn nothing' 'run sub-steps 1–4 of `../review/SKILL.md` step 1b' \
  'When step 1b stops at a gate, stop: write no mergeable verdict and reply to no thread' \
  'A `check` run that pushed in step 5 compares again the same way before the forge query of step 6' \
  'The `merge <sha>` mode does none of this' \
  'a different sha' 'a `產表失敗：` line' 'no `## 邏輯表` section'; do
  grep -qF -- "$k" "$FX/entry" || fail "入口比對缺 $k"
done

# --- D10 skip：mr: none 只在 workplan 還標 mr: none 時算已處理（入口與步 8）---
MRNONE='`skip：mr: none` counts only while the card'"'"'s PR in `openspec/workplan.yaml` still has `mr: none`'
grep -qF -- "$MRNONE" "$FX/entry" || fail "入口缺 skip：mr: none 的條件"
assert_fixed "$MRNONE" "$STEP"

# --- D9 放行之後步 8 也不重產 ---
assert_fixed 'unless the line under `## 邏輯表` starts with `skip：`' "$STEP"

# --- D11 步 1 停在 gate 後跟 pr 5c 同條件；答完那行仍不對就重述並停 ---
for k in 'until the gate is answered and the line under `## 邏輯表` names the current head or starts with `skip：`' \
  'After the answer, run step 1b again first; when that run ends and the line still does neither, say so and stop again' \
  'or starts with `skip：`, spawn nothing'; do
  grep -qF -- "$k" "$FX/entry" || fail "入口停 gate 缺 $k"
done
! grep -qF 'When the gate is answered and the line still does neither' "$FX/entry" || fail "入口還是答案一進來就停"
# R3.2 步 8 同一句
assert_fixed 'After the answer, run step 1b again first; when that run ends and the line still does neither, say so and stop again' "$STEP"
