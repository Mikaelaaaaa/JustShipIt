#!/usr/bin/env bash
# skills/pr 的描述更新（步 4b）與 auto-merge 檢查（步 4c），babysit 步 5 推完後引用它們。
# skill 是文字，只能檢查 skill 寫了什麼；agent 守不守由 eval 驗。對應 openspec/changes/agent-20261126-1118-2/specs/mr-description-update。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PR="$OPSX_ROOT/skills/pr/SKILL.md"
BS="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_file "$PR"
assert_file "$BS"

has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$(dirname "$2")")/$(basename "$2")"; }
hasnt() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$(dirname "$2")")/$(basename "$2")"; }

UPD="$FX/step4b"; AM="$FX/step4c"; WHERE="$FX/where"; BS5="$FX/babysit5"
awk '/^4b\. /{on=1} /^4c\. /{on=0} on' "$PR" > "$UPD"
awk '/^4c\. /{on=1} /^5\. /{on=0} on' "$PR" > "$AM"
awk '/^## Where you are/{on=1} /^## Steps/{on=0} on' "$PR" > "$WHERE"
awk '/^5\. \*\*Order is conflicts/{on=1} /^6\. /{on=0} on' "$BS" > "$BS5"
[ -s "$UPD" ] || fail "skills/pr/SKILL.md 沒有步 4b"
[ -s "$AM" ] || fail "skills/pr/SKILL.md 沒有步 4c"
[ -s "$BS5" ] || fail "skills/babysit/SKILL.md 沒有步 5"

# --- 描述更新照 forge 用一條能跑的指令（Scenario Outline 兩列）---
has 'step 4b' "$WHERE"
has 'gh pr edit <n> --body-file openspec/changes/<slug>/mr.md' "$UPD"
has 'needs: run' "$UPD"
has 'by: coordinator' "$UPD"
has 'glab api -X PUT projects/:fullpath/merge_requests/<iid> -F description=@<absolute path of mr.md>' "$UPD"
# 反例：不叫 agent 用跑不動的 glab mr update 寫法
hasnt '$(cat' "$PR"
hasnt 'glab mr update` /' "$WHERE"
grep -F 'glab mr update' "$UPD" | grep -qF 'do not use' || fail "步 4b 要寫明 GitLab 不用 glab mr update 更新描述"

# --- 更新後讀回確認 ---
has "step 5's read-back" "$UPD"
has 'write the same gate again' "$UPD"
has 'never try another way' "$UPD"

# --- 描述沒變就不更新 ---
has 'same as mr.md' "$UPD"
has 'no update and no gate' "$UPD"

# --- 更新步驟只寫在 pr：babysit 引用、不重寫 ---
has '`../pr/SKILL.md`' "$BS5"
has 'steps 4b and 4c' "$BS5"
has 'only when it changed' "$BS5"
has 'no gate' "$BS5"
hasnt 'description=@' "$BS"

# --- auto-merge：依狀態決定動作（Scenario Outline 兩張表每一列）---
has 'merge_when_pipeline_succeeds' "$AM"
has 'head_pipeline.status' "$AM"
has 'When auto-merge is on, do nothing' "$AM"          # true + running
for s in '`created`' '`pending`' '`running`'; do        # false + created / pending / running：開重設 gate
  grep -F 'needs: run' "$AM" | grep -qF -- "$s" || fail "步 4c 開 gate 的狀態缺 $s"
done
has 'by: coordinator' "$AM"
has 'auto-merge: no（pipeline 已綠，等合併）' "$AM"     # false + success
has 'auto-merge: no（被取消）' "$AM"                     # false + failed
grep -F '`success`' "$AM" | grep -qF 'write no gate' || fail "pipeline 已綠時不開 gate"
grep -F '`failed`' "$AM" | grep -qF 'write no gate' || fail "pipeline 失敗時不開 gate"
# 反例：重設指令同時帶兩個參數
has 'glab api -X PUT projects/:fullpath/merge_requests/<iid>/merge -F merge_when_pipeline_succeeds=true -F sha=<head sha>' "$AM"
# 步 4 指向 4c，不再只留一句「only if」
has 'Auto-merge is step 4c' "$PR"
echo OK
