#!/usr/bin/env bash
# babysit、apply、review 三個流程文件的守門句。skill 是文字，只能檢查 skill 寫了什麼。
# 驗收：openspec/changes/agent-20261111-2326/specs/skill-step-guards/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }

# --- babysit：push 前後各查一次 PR state；green 只在已啟動的 run 完成後寫，並寫明跑了什麼 ---
BS="$OPSX_ROOT/skills/babysit/SKILL.md"
assert_fixed 'Before each push and again right after it, query the PR state once' "$BS"
assert_fixed 'already merged' "$BS"
assert_fixed 'do not push' "$BS"
assert_fixed 'Write a green verdict only after every background run you started has finished' "$BS"
assert_fixed 'name the tests that ran' "$BS"

# --- apply 第 10 步：勾 task 前核對 task 點名的檔案有出現在 diff ---
AP="$OPSX_ROOT/skills/apply/SKILL.md"
STEP10="$FX/step10"; awk '/^\| 10 \|/' "$AP" > "$STEP10"
[ -s "$STEP10" ] || fail "skills/apply/SKILL.md 沒有第 10 步"
assert_fixed 'git diff --stat' "$STEP10"
assert_fixed 'every file the task names' "$STEP10"
assert_fixed 'do not check the task off' "$STEP10"

# --- apply 第 1、10 步：刪除或取代測試檔時，每個舊 case 在 tasks.md 寫 去處：，勾 task 前核對 ---
STEP1="$FX/step1"; awk '/^\| 1 \|/' "$AP" > "$STEP1"
[ -s "$STEP1" ] || fail "skills/apply/SKILL.md 沒有第 1 步"
assert_fixed 'list every case in the old file' "$STEP1"
assert_fixed '`去處：<old file>::<case> → <new file>::<case>`' "$STEP1"
assert_fixed '`去處：<old file>::<case> → 刻意移除：<reason>`' "$STEP1"
assert_fixed '刻意移除 without a reason is not a destination' "$STEP1"
assert_fixed 'A case removed from a test file that stays needs no 去處 line' "$STEP1"
assert_fixed 'or the task says it replaces one' "$STEP10"
assert_fixed 'every case of that file has a 去處 line' "$STEP10"
assert_fixed 'every case it moved is in the new file' "$STEP10"
assert_fixed 'when either fails, do not check the task off' "$STEP10"
assert_fixed 'deletes, renames or replaces a test file' "$STEP1"
assert_fixed 'git diff --name-status -M <base>' "$STEP10"
assert_fixed '`<base>` is `git merge-base HEAD <remote>/main`' "$STEP10"
assert_fixed 'committed, staged and unstaged deletions and renames included' "$STEP10"
assert_fixed 'a `D` or `R` line for a test file' "$STEP10"
assert_fixed 'under the task that deleted, renamed or replaced it' "$STEP10"
if grep -qF 'git diff --name-status -M HEAD' "$STEP10"; then fail "第 10 步還在跟 HEAD 比，已 commit 的刪除看不到"; fi

# --- review：合併 base 分支後的確認 pass，寫 確認: <sha>、不算一輪 ---
RV="$OPSX_ROOT/skills/review/SKILL.md"
assert_fixed 'Base-merge confirm pass' "$RV"
assert_fixed 'merged the base branch' "$RV"
assert_fixed 'does not count as a round' "$RV"
assert_fixed 'first-parent' "$RV"
echo "skill-step-guards ok"
