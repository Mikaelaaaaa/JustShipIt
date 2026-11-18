#!/usr/bin/env bash
# skills/babysit/SKILL.md：threads-only 的 push wave 之後、回覆之前照 review 的產表步重產邏輯表檔案（不發留言）；
# 每一輪最後照 `## 邏輯表` 的 sha 比對 MR head，不同就重產一次；merge 模式不重產。skill 是文字，只能檢查 skill 寫了什麼。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
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

# --- 照 sha 比對重產（design D7，跟 pr step 5c 一樣）：不看這輪有沒有 push，merge 模式不產，一輪只產一次 ---
assert_fixed 'Every run except the `merge <sha>` mode checks the map once, after its last push' "$STEP"
assert_fixed 'with the same check the pr skill makes before its reply' "$STEP"
assert_fixed 'a `產表失敗：` line, or no `## 邏輯表` section' "$STEP"
assert_fixed 'A run whose map already shows the MR head does not regenerate it, and the `merge <sha>` mode never does' "$STEP"
assert_not_fixed 'Every run that pushed regenerates' "$STEP"
# sha 的比法跟 mergeready 一樣：7 碼以上、是 MR head 的開頭（大 repo 的 --short 會給 8–9 碼）
assert_fixed 'a hex sha of 7 or more characters that the MR head starts with' "$STEP"
assert_not_fixed 'the first 7 characters of the MR head' "$STEP"
assert_not_fixed 'did not push never regenerate' "$STEP"
# 步 5 不另寫一次重產，免得同一輪產兩次
STEP5="$FX/step5"
awk '/^5\. /{on=1} /^6\. /{on=0} on' "$SK" > "$STEP5"
[ -s "$STEP5" ] || fail "skills/babysit/SKILL.md 沒有步 5"
assert_not_fixed 'regenerate the logic map' "$STEP5"
