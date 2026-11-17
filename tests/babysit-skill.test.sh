#!/usr/bin/env bash
# skills/babysit/SKILL.md：有 push 的輪次（threads-only 的 push wave、check 模式 merge main 之後的 push）照 review 的產表步重產邏輯表檔案（不發留言）；
# merge 與沒 push 的輪次不重產。skill 是文字，只能檢查 skill 寫了什麼。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
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

# --- 不重產的情況（Scenario「沒有 push 不重產」）---
for k in '`merge <sha>`' 'did not push'; do
  grep -F 'never regenerate it' "$STEP" | grep -qF -- "$k" || fail "不重產清單缺 $k"
done

# --- check 模式有 push 也重產（Scenario「check 模式 push 之後重產」）：merge main 之後 head 變了 ---
assert_fixed 'Every run that pushed regenerates the map, `check` mode included' "$STEP"
assert_not_fixed 'the `check` mode, the `merge <sha>` mode' "$STEP"
STEP5="$FX/step5"
awk '/^5\. /{on=1} /^6\. /{on=0} on' "$SK" > "$STEP5"
[ -s "$STEP5" ] || fail "skills/babysit/SKILL.md 沒有步 5"
python3 -I - "$STEP5" <<'PY' || fail "步 5 的 push 之後要照步 8 重產邏輯表"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
push = text.index("Push with `git push`")
regen = text.index("regenerate the logic map the way step 8 says")
if not push < regen:
    sys.exit("順序：push=%d regen=%d" % (push, regen))
PY
