#!/usr/bin/env bash
# skills/explore/SKILL.md 的拆工規則：D5 對照、拆法 gate、確認後建殼。只證明規則寫在對的段落且舊句子已移除；agent 守不守由 eval 驗。
# 驗收：openspec/changes/split-plan/specs/work-split/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SK="$OPSX_ROOT/skills/explore/SKILL.md"
assert_file "$SK"
has() { grep -qF -- "$1" "$2" || fail "'$1' not in $(basename "$2")"; }
section() { awk -v h="## $1" '/^```/{fence=!fence} index($0,h)==1{on=1;print;next} !fence && /^## /{on=0} on' "$SK"; }
ENDING="$FX/ending"; SPLIT="$FX/split"; ENGAGE="$FX/engage"
section "Ending: explore.md" > "$ENDING"; section "Splitting a big card" > "$SPLIT"; section "How to Engage" > "$ENGAGE"
for f in "$ENDING" "$SPLIT" "$ENGAGE"; do [ -s "$f" ] || fail "section missing: $f"; done

# --- new-auto-merge：拆卡前先處理原卡的 ## 併入 段（拆出或帶進主 change），不留在 split 的卡上 ---
has '## 併入' "$SPLIT"; has 'opsx split-out' "$SPLIT"

# --- held-branch-guard：opsx chain 沒續接時寫 gate 請人派。coordinate 只派有 tasks.md 的卡，剛拆的主 change 不會被它派到 ---
has 'opsx chain <original>' "$SPLIT"
! grep -qF 'left for the coordinator to dispatch' "$SPLIT" || fail "不能寫交給 coordinator 派：剛拆的主 change 沒有 tasks.md"
has 'opsx chain --unclaimed <original>' "$SPLIT"
GATE="$FX/dispatch-gate"; awk '/^## dispatch-<main>/{on=1} on && /^```/{exit} on' "$SPLIT" > "$GATE"
[ -s "$GATE" ] || fail "拆卡段要有 dispatch-<main> gate 範本"
has 'status: open' "$GATE"; has 'waits-on:' "$GATE"
! grep -qF 'needs: run' "$GATE" || fail "從看板派不是要人跑的指令，dispatch gate 不寫 needs: run"

# --- Scenario：explore skill 有 D5 對照段 ---
has 'D5 check' "$ENDING"
has 'more than one subsystem' "$ENDING"
has 'different risk' "$ENDING"
has 'more than 6 tasks' "$ENDING"
has 'any one' "$ENDING"

# --- Scenario：拆法 gate 段存在 ---
has 'type: decision' "$SPLIT"
for k in session 'main change' 'sub-change' 'depends-on'; do has "$k" "$SPLIT"; done
has 'Until the gate is answered, create no shell and do not touch the workplan' "$SPLIT"

# --- Scenario（me-20261122-1148 specs/work-split）：split gate 預設一張主 change；多張要寫不能當子 change 的理由；風險不同不再另開 ---
has 'one main change with sub-changes' "$SPLIT"
has 'ships on its own' "$SPLIT"; has 'must be reviewed separately' "$SPLIT"
SGATE="$FX/split-gate"; awk '/^## split$/{on=1} on && /^```/{exit} on' "$SPLIT" > "$SGATE"
[ -s "$SGATE" ] || fail "拆卡段要有 split gate 範本"
has '不當子 change：' "$SGATE"
! grep -qF 'different risks get their own main change' "$SK" || fail "風險不同另開主 change 的提示要移除"

# --- Scenario（me-20261122-1148）：PR level 段用兩個條件，不再按風險／關注點／reviewer 分 PR ---
PRL="$FX/pr-level"; awk '/^### PR level/{on=1;next} on && /^#{2,3} /{exit} on' "$SK" > "$PRL"
[ -s "$PRL" ] || fail "section missing: PR level"
has 'ships on its own' "$PRL"; has 'must be reviewed separately' "$PRL"
for k in 'Different risk' 'Different concern' 'Different reviewer'; do ! grep -qF -- "$k" "$PRL" || fail "PR level 段還有 $k"; done

# --- R1.5：兩條同時成立要釘整句，且要在範本外的說明文字（範本本身不算） ---
PROSE="$FX/split-prose"; awk '/^```/{exit} {print}' "$SPLIT" > "$PROSE"
has 'both ships on its own and must be reviewed separately' "$PROSE"
has 'different risk alone is not enough' "$PROSE"
has 'both ships on its own and must be reviewed separately' "$PRL"
! grep -qF 'or must be reviewed separately' "$SK" || fail "條件是「且」，不能寫成 or"

# --- R1.1：已經有 subs/ 的主 change 不再拆（不然整張原卡的範圍會在主 change 再觸發 D5） ---
has 'already has `subs/`' "$ENDING"; has 'does not split again' "$ENDING"
has 'already has `subs/`' "$PROSE"

# --- R1.3：workplan 範例不再按風險拆兩個 PR ---
! grep -qF 'low risk, merge first' "$SK" || fail "workplan 範例不該再按風險拆 PR"
! grep -qF 'eval-core' "$SK" || fail "workplan 範例應是一個 PR"

# --- R1.4：範本佔位不夾指示；PR level 寫明理由寫在哪 ---
! grep -qF 'only when there is a second main change' "$SGATE" || fail "範本佔位不能夾給 agent 的指示"
has '`main change` line' "$PRL"

# --- R2.1（D9）：有第二張主 change 時 選項 不標 Recommended，交使用者看理由 ---
has 'without `(Recommended)`' "$PROSE"

# --- R3.1（D9）：板子先拿 建議 當推薦（collect.sh），所以第二張主 change 時連 建議 行也不寫；範本後那段也要分一張／兩張 ---
has 'leave out the `建議:` line' "$PROSE"
! grep -qF 'leave that line out of the template' "$SK" || fail "「leave that line out」會被讀成拿掉唯一的 main change 行"
has 'has no recommendation, so it goes to the user' "$SPLIT"

# --- R3.2：不再拆的條件三處一致（subs/ 或 split_into），不留做不到的「D5 改看子 change」 ---
has 'or is listed in a parent card'"'"'s `split_into`' "$ENDING"
has 'or is listed in a parent card'"'"'s `split_into`' "$PROSE"
! grep -qF 'Judge D5 per sub-change' "$SK" || fail "沒有步驟會對子 change 跑 D5"
! grep -qF 'judge each sub-change instead' "$SK" || fail "沒有步驟會對子 change 跑 D5"

# --- R4.1（D11）：範本第二張主 change 那行自己註明刪 Recommended 與 建議，照抄範本也不會被協調者代答 ---
grep -F 'main change <pr2>' "$SGATE" | grep -qF 'drop `(Recommended)` and the `建議:` line' || fail "範本 pr2 行要註明刪 Recommended 與 建議"

# --- Scenario：移除 autopilot 不確認的句子 ---
! grep -qF 'written without the confirmation step' "$SK" || fail "autopilot 不確認的句子要移除"
has 'Splitting a big card' "$ENGAGE"

# --- Scenario：建殼步驟完整（四步，順序固定） ---
line() { grep -nF -- "$1" "$SPLIT" | head -1 | cut -d: -f1; }
a="$(line 'openspec new change')"; b="$(line 'subs/<sub>/')"; c="$(line 'openspec/workplan.yaml')"; d="$(line 'split_into:')"
for v in "$a" "$b" "$c" "$d"; do [ -n "$v" ] || fail "建殼四步缺一步: $a $b $c $d"; done
[ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] || fail "四步順序：主殼 $a < 子殼 $b < workplan $c < split_into $d"
has 'parent:' "$SPLIT"

# --- Scenario：explore skill 有步驟表（驗收：openspec/changes/node-steps-text/specs/node-step-text/spec.md「explore skill 有步驟表」） ---
STEPS="$FX/steps"; section "Steps" > "$STEPS"
[ -s "$STEPS" ] || fail "section missing: Steps"
for k in '../how/SKILL.md' '../blast-radius/SKILL.md' '../why/SKILL.md' 'references/prototype.md' '../unslop/SKILL.md' '查資料' 'skip：' '## 步驟'; do has "$k" "$STEPS"; done
! grep -qF 'There are no fixed steps' "$SK" || fail "'no fixed steps' 要移除"
TPL="$OPSX_ROOT/schemas/opsx/templates/explore.md"
has '## 步驟' "$TPL"
# 驗收：node-step-text「模板與 skill 步驟名一致」——步驟名與順序逐行相同
awk -F'|' '/^\| [0-9]+ \|/{gsub(/^ +| +$/,"",$3); print $3}' "$STEPS" > "$FX/skill-names"
awk '/^## /{on=($0=="## 步驟");next} on && /^- [0-9]+ /{sub(/^- [0-9]+ /,""); sub(/：.*/,""); print}' "$TPL" > "$FX/tpl-names"
[ -s "$FX/skill-names" ] || fail "SKILL.md 步驟表沒有步驟列"
cmp -s "$FX/skill-names" "$FX/tpl-names" || fail "步驟名或順序不一致。SKILL.md 步驟表: $(tr '\n' ' ' < "$FX/skill-names")／模板 ## 步驟: $(tr '\n' ' ' < "$FX/tpl-names")"
REQ="$OPSX_ROOT/docs/rewrite-requirements-pstack-grill.md"
! grep -qF '八段固定標題' "$REQ" || fail "需求文件 §8.3 不該再寫八段固定標題"
# 驗收：「模板與 skill 步驟名一致」——§8.3 explore 子表的步驟名與順序也相同，摘要列也有查資料與 unslop
awk '/^### /{on=($0 ~ /^### explore（主流程節點 1/);next} on' "$REQ" > "$FX/req-explore"
awk -F'|' '/^\| [0-9]+ /{gsub(/^ *[0-9]+ *| +$/,"",$2); print $2}' "$FX/req-explore" > "$FX/req-names"
cmp -s "$FX/skill-names" "$FX/req-names" || fail "§8.3 explore 子表與 SKILL.md 步驟名或順序不一致。SKILL.md: $(tr '\n' ' ' < "$FX/skill-names")／§8.3: $(tr '\n' ' ' < "$FX/req-names")"
SUMMARY_ROW="$(grep -F '| **explore** | 讀檔' "$REQ")"
for k in '查資料' 'unslop'; do printf '%s' "$SUMMARY_ROW" | grep -qF -- "$k" || fail "§8.3 主表 explore 摘要列沒有 $k"; done
# 步驟 1、8、9 沒有已知區塊可指，要有合法寫法與例子
for k in '- 1 讀卡：done' '- 8 待決：待決' '- 9 unslop：done'; do
  has "$k" "$ENDING"
  has "$k" "$TPL"
done
# split gate 在 opsx-workflow 由協調者照建議答（specs/opsx-autonomy「agent 規則寫明誰答 gate」）
has 'opsx-workflow repo' "$SPLIT"
has 'not one that needs your hands, a merge, has no recommendation, is a stuck gate or carries `needs: run`' "$SPLIT"
! grep -qF 'the coordinator never answers any gate' "$SK" || fail "explore SKILL.md 不該再寫協調者不答任何 gate"
echo ok
