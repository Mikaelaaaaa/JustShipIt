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

# --- autopilot-forge-access D12：步 6 讀 GitLab 未解決 thread 用 glab mr note list --state unresolved，不用 glab api（autopilot 不放行）---
STEP6="$FX/step6"
awk '/^6\. /{on=1} /^7\. /{on=0} on' "$SK" > "$STEP6"
[ -s "$STEP6" ] || fail "skills/babysit/SKILL.md 沒有步 6"
grep -oE 'Unresolved threads:[^.]*' "$STEP6" | grep -qF 'glab mr note list <iid> --state unresolved' || fail "步 6 讀未解決 thread 要用 glab mr note list <iid> --state unresolved"
assert_not_fixed 'glab api' "$STEP6"

# --- D12：步 8 GitLab 回覆進原 thread 用 glab mr note create --reply，沒有 --message-file 與 glab api ---
assert_fixed 'glab mr note create <iid> --reply <discussion-id>' "$STEP"
assert_not_fixed '--message-file' "$STEP"
assert_not_fixed 'glab api' "$STEP"

# --- D11：步 7 開新 build 前寫 gate（autopilot 的 allow 只放行唯讀 glab ci）---
STEP7="$FX/step7"
awk '/^7\. /{on=1} /^8\. /{on=0} on' "$SK" > "$STEP7"
[ -s "$STEP7" ] || fail "skills/babysit/SKILL.md 沒有步 7"
assert_fixed 'before that one fresh build, write a gate' "$STEP7"

# --- 不重產的情況（Scenario「沒有 push 不重產」）---
assert_fixed 'Only a `threads-only` run that pushed' "$STEP"
for k in '`check`' '`merge <sha>`' 'did not push'; do
  grep -F 'never regenerate it' "$STEP" | grep -qF -- "$k" || fail "不重產清單缺 $k"
done
