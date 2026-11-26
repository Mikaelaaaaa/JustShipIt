#!/usr/bin/env bash
# skills/pr/SKILL.md 步 5c：head 跟 report.md 記的 sha 不同才照 review 的產表步重產，只寫檔，不發留言。
# skill 是文字，只能檢查 skill 寫了什麼；agent 守不守由 eval 驗。對應 openspec/changes/pr-logic-map/specs/pr-logic-map。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/pr/SKILL.md"
assert_file "$SK"

assert_fixed() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
assert_not_fixed() { ! grep -qF -- "$1" "$2" || fail "'$1' should not be in $(basename "$2")"; }

# 步 5c 一段：從 `5c.` 那行到 `6.` 那行之前
STEP="$FX/step5c"
awk '/^5c\. /{on=1} /^6\. /{on=0} on' "$SK" > "$STEP"
[ -s "$STEP" ] || fail "skills/pr/SKILL.md 沒有步 5c"

# --- 位置：5b 之後、6 之前；新開與更新都跑 ---
python3 -I - "$SK" <<'PY' || fail "Logic map 不在 Back-link 與 Reply 之間"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
backlink = text.index("**Back-link.**")
logic = text.index("**Logic map.**")
reply = text.index("**Reply.**")
if not backlink < logic < reply:
    sys.exit("順序：backlink=%d logic=%d reply=%d" % (backlink, logic, reply))
PY
assert_fixed 'on a new MR and on an update' "$STEP"
assert_fixed 'step 5c runs on both' "$SK"

# --- 產表搬到 review 的產表步：5c 只在 head 變了時照它重產，不自帶 prompt（specs/pr-logic-map）---
assert_fixed 'run sub-steps 1–4 of `../review/SKILL.md` step 1b' "$STEP"
[ -f "$(dirname "$SK")/../review/SKILL.md" ] || fail "../review/SKILL.md does not resolve from skills/pr/"
assert_not_fixed 'repo: <' "$STEP"
assert_not_fixed 'Spawn one fresh subagent' "$STEP"
# head 沒變不重產；sha 不同、產表失敗行、沒有這段三種情況才重產（Examples 表每列）
assert_fixed 'equals the first 7 characters of `git rev-parse HEAD`' "$STEP"
assert_fixed 'without spawning anything' "$STEP"
for k in 'a different sha' 'a `產表失敗：` line' 'no `## 邏輯表` section'; do
  grep -F 'Otherwise' "$STEP" | grep -qF -- "$k" || fail "重產條件缺 $k"
done
assert_fixed '<remote>` from step 1' "$STEP"

# --- 只產檔：不發留言、不改留言、不查字數上限 ---
for k in 'comment' '留言' 'gh pr' 'glab api' '--edit-last' 'viewerDidAuthor' '65,536' '1,000,000'; do
  assert_not_fixed "$k" "$STEP"
done

# --- report.md 的 ## 邏輯表 一行：重產時整行覆寫 ---
assert_fixed '## 邏輯表' "$STEP"
assert_fixed 'openspec/changes/<slug>/logic-map.md · <sha>' "$STEP"
assert_fixed 'overwrites the whole line' "$STEP"
assert_not_fixed 'go on to step 6' "$STEP"

# --- skip： 行不重產（「head 沒變不重產」邊界列）---
grep -F 'without spawning anything' "$STEP" | grep -qF 'a line that starts with `skip：`' || fail "5c 沒把 skip： 行當成不重產"

# --- 產表停在 gate 時不接 babysit（specs/pr-logic-map「產表停在 gate 不接 babysit」）---
# 只看 5c 段：5b 的 "A failed back-link does not stop /pr" 還在，整檔比對會誤過
assert_not_fixed 'does not stop /pr' "$STEP"
assert_fixed 'When step 1b stops at a gate, stop here: do not reply and do not continue to step 6' "$STEP"
assert_fixed 'continue with step 6 only once the line under `## 邏輯表` names this head or starts with `skip：`' "$STEP"
# D11 答完那行仍不對就重述並停
# R3.2 答案進來先重跑 1b，跑完仍不對才停
assert_fixed 'After the gate is answered, run step 1b again first: its opening paragraph continues by the answer.' "$STEP"
assert_fixed 'when that run ends and the line still does neither, say so and stop again' "$STEP"
assert_not_fixed 'When the gate is answered and the line still does neither' "$STEP"
# R3.3 skip： 不重產釘整句，不只片語同行
assert_fixed 'so does a line that starts with `skip：` (the user waived the map, or the card is `mr: none`): continue with step 6 without spawning anything' "$STEP"
# D10 skip：mr: none 只在 workplan 還標 mr: none 時算已處理
assert_fixed '`skip：mr: none` counts only while the card'"'"'s PR in `openspec/workplan.yaml` still has `mr: none`' "$STEP"

# --- R1.3 router 在 gate 答完後送到 pr：pr 先認 logic-map-undecided，open 就停，答了沒寫回就先照 review 寫回 ---
awk 'index($0,"## Where you are")==1{on=1;next} /^## /{on=0} on' "$SK" > "$FX/where"
assert_fixed 'Look at the newest `logic-map-undecided-r*` gate in gates.md. If it is open, stop and repeat its question.' "$FX/where"
assert_fixed 'If it is answered and has no `寫回:` line, run the **Logic map gate answered** step of `../review/SKILL.md` Step 4 first' "$FX/where"

# --- push 之前表要對上要推的 head（specs/pr-logic-map「push 之前表要對上要推的 head」）---
STEP4="$FX/step4"
awk '/^4\. /{on=1} /^5\. /{on=0} on' "$SK" > "$STEP4"
[ -s "$STEP4" ] || fail "skills/pr/SKILL.md 沒有步 4"
python3 -I - "$STEP4" <<'PY' || fail "步 4 的比對不在 git push 之前"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
check = text.index("Before the push")
push = text.index("git push -u")
if not check < push:
    sys.exit("順序：check=%d push=%d" % (check, push))
PY
# 「push 前表對不上就先重產再 push」：sha、產表失敗行、沒有這段都算對不上
assert_fixed 'run the check of step 5c against `git rev-parse HEAD`' "$STEP4"
assert_fixed 'run sub-steps 1–4 of `../review/SKILL.md` step 1b' "$STEP4"
# 「push 前已對上不重產」：照 5c 的檢查，skip： 行與對到 HEAD 的表不重產
assert_fixed 'when it would continue without spawning anything, push' "$STEP4"
# 「不看 auto-merge」
assert_fixed 'whether or not the MR has auto-merge' "$STEP4"
assert_fixed 'before any request that turns auto-merge back on' "$STEP4"
# 「產表停在 gate 不 push」
assert_fixed 'When step 1b stops at a gate, stop: do not push and do not open or update the MR' "$STEP4"

# --- pr 與 babysit 用同一個段名與輸出路徑（Scenario「段名與路徑一致」）---
BS="$OPSX_ROOT/skills/babysit/SKILL.md"
for f in "$SK" "$BS"; do
  assert_fixed '## 邏輯表' "$f"
  assert_fixed 'openspec/changes/<slug>/logic-map.md' "$f"
done
