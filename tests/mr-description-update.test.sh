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

# --- 更新後讀回確認；第二次仍不對改交使用者（D10）---
has "When the answer comes back, run step 5's read-back." "$UPD"
has 'for the first time, write the same gate again' "$UPD"
has 'the second time, write it without the `by: coordinator` line' "$UPD"
has 'Never try another way' "$UPD"
# 開了更新 gate 也不停
has 'carry on without waiting for it' "$UPD"
hasnt 'and stop.' "$UPD"

# --- 描述沒變就不更新：只比 ## Changes 各列的（編號, 對應測試），散文欄不比 ---
has 'compare the (編號, 對應測試) pairs of its `## Changes` rows with those of the MR' "$UPD"
has 'ignoring trailing whitespace' "$UPD"
has 'When the pairs are the same, there is no update and no gate' "$UPD"
# GitHub 更新後也讀回
has "--body-file openspec/changes/<slug>/mr.md\`, then step 5's read-back" "$UPD"

# --- 更新步驟只寫在 pr：babysit 引用、不重寫 ---
has '`../pr/SKILL.md`' "$BS5"
has 'run step 4b of `../pr/SKILL.md`' "$BS5"
has 'only when it changed' "$BS5"
has 'no gate' "$BS5"
hasnt 'description=@' "$BS"
# 4c 只在邏輯表指到 head 之後跑：步 5、步 8 推完只跑 4b，4c 接在「每次 run 最後檢查邏輯表一次」之後
hasnt 'steps 4b and 4c' "$BS"
BS8="$FX/babysit8"
awk '/^8\. /{on=1} /^9\. /{on=0} on' "$BS" > "$BS8"
has 'run step 4b of `../pr/SKILL.md`' "$BS8"
python3 -I - "$BS8" <<'PY' || fail "babysit 步 8：4c 要在每次 run 最後檢查邏輯表之後"
import sys
t = open(sys.argv[1], encoding="utf-8").read()
check = t.index("checks the map once")
c4 = t.index("then run step 4c of `../pr/SKILL.md`")
if not check < c4:
    sys.exit("check=%d 4c=%d" % (check, c4))
PY

# --- auto-merge：條件與時機 ---
has "the repo's CLAUDE.md or the user's global CLAUDE.md" "$AM"
has 'On a new MR and on an update alike it runs after step 5c' "$AM"
hasnt 'after step 5 has written' "$AM"
# 5c 接下去之前先跑 4c（地圖已指到 head 與重產後兩條路）
has 'continue with step 6 without spawning anything, running step 4c first' "$PR"
has 'Then run step 4c and continue with step 6 only once the line' "$PR"
# 每種狀態一行（bullet），斷言對整行，狀態與動作綁在同一個 bullet
line_of() { grep -F -- "$1" "$AM" || fail "步 4c 沒有含 '$1' 的行"; }
# GitHub（D11）
case "$(line_of '- GitHub:')" in *'write no gate'*'auto-merge: no（GitHub 不處理）'*) ;; *) fail "GitHub 那行要不開 gate、寫 GitHub 不處理" ;; esac
# 讀三個欄位；auto-merge 開著不動（true + running）
has 'read `merge_when_pipeline_succeeds`, `head_pipeline.status` and `head_pipeline.sha`' "$AM"
has 'When auto-merge is on, do nothing' "$AM"
# 邏輯表沒指到 head（skip： 行算已定）或 undecided gate 還開著：先不開（D13）
case "$(line_of '- When the line under `## 邏輯表`')" in *'neither names the current head nor starts with `skip：`'*'`logic-map-undecided-r*` gate is open'*'write no gate yet'*) ;; *) fail "邏輯表或 undecided gate 未定時先不開重設 gate" ;; esac
# null：沒有 pipeline，PUT 會直接合併，不開 gate（沒有 CI 的 repo）
case "$(line_of '- When `head_pipeline` is null')" in *'write no gate'*'auto-merge: no（沒有 pipeline）'*) ;; *) fail "null 那行要不開 gate、寫沒有 pipeline" ;; esac
grep -F -- '- When `head_pipeline` is null' "$AM" | grep -qF 'write a `needs: run`' && fail "null 那行不能開 gate"
# 還沒跑完（舊 sha、created／pending／running／waiting_for_resource 等）：開重設 gate
GATE="$(line_of '- When `head_pipeline.sha` is not `git rev-parse HEAD`')"
case "$GATE" in *'or its status is not `success`, `failed`, `canceled` or `skipped`'*'write a `needs: run` gate with a `by: coordinator` line'*) ;; *) fail "沒跑完的狀態要開協調者 gate：$GATE" ;; esac
case "$GATE" in *'glab api -X PUT projects/:fullpath/merge_requests/<iid>/merge -F merge_when_pipeline_succeeds=true -F sha=<full 40-character output of git rev-parse HEAD>'*) ;; *) fail "重設指令要帶兩個參數、sha 完整 40 碼：$GATE" ;; esac
# success：不開、寫已綠（false + success）
case "$(line_of '- When the pipeline is `success`')" in *'write no gate'*'auto-merge: no（pipeline 已綠，等合併）'*) ;; *) fail "success 那行要不開 gate、寫已綠" ;; esac
# failed／canceled／skipped：不開、寫被取消（false + failed）
case "$(line_of '- When the pipeline is `failed`, `canceled` or `skipped`')" in *'write no gate'*'auto-merge: no（被取消）'*) ;; *) fail "failed 那行要不開 gate、寫被取消" ;; esac
# 反例：success 與 failed 那兩行不得出現開 gate 的寫法
grep -F -- '- When the pipeline is `success`' "$AM" | grep -qF 'write a `needs: run`' && fail "success 那行不能開 gate"
grep -F -- '- When the pipeline is `failed`' "$AM" | grep -qF 'write a `needs: run`' && fail "failed 那行不能開 gate"
# 步 4 指向 4c
has 'Auto-merge is step 4c' "$PR"
echo OK
