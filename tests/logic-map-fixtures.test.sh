#!/usr/bin/env bash
# logic-map 的 eval fixture 與 without 對照組：fixture 只有 base、head 兩個 commit、沒有 remote，樹跟原 commit 一致；
# evals.json 每題指到 fixture、範圍是 HEAD^...HEAD；prepare-run 的 without 少 logic-map、不認得的 variant 被拒。
# 對應 openspec/changes/logic-map-skill/subs/eval-fixtures/specs/logic-map「fixture 隔離」「eval 有沒 skill 的對照組」。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
EV="$OPSX_ROOT/skills/logic-map/evals"
FIXTURES="$EV/fixtures"
assert_file "$FIXTURES/_lib.sh"

# --- evals.json：每題的 fixture、commit、範圍 ---
python3 -I -c '
import json, sys
for e in json.load(open(sys.argv[1]))["evals"]:
    print(e["id"], e["files"][0] if e["files"] else "-", e["prompt"].replace("\n", " "))' "$EV/evals.json" > "$FX/evals" || fail "evals.json 讀不了"
assert_eq "$(awk '{print $1, $2}' "$FX/evals")" "1 fixtures/stop-gate-subagent
2 fixtures/gate-title-slug
3 fixtures/coordinate-usage-limit
4 fixtures/question-reply
5 fixtures/coordinate-usage-limit
6 fixtures/logic-map-classify"
grep -v '^4 ' "$FX/evals" > "$FX/map-evals"
assert_eq "$(grep -c 'HEAD^...HEAD' "$FX/map-evals")" 5 "產表題的範圍都是 HEAD^...HEAD"
grep '^4 ' "$FX/evals" > "$FX/question-eval"
# 第 5 題只驗兩段業務說明：位置、句數、沒有識別字
python3 -I -c '
import json, sys
e = [x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == 5][0]
print("\n".join(e["assertions"]))' "$EV/evals.json" > "$FX/eval5" || fail "evals.json 第 5 題讀不了"
for k in '## 這支 PR 在做什麼（業務說明）' '### 業務上在做什麼' '3 到 5 句' '2 到 4 句' '反引號'; do assert_grep "$k" "$FX/eval5"; done
assert_not_grep 'HEAD^...HEAD' "$FX/question-eval"
assert_not_grep '7b30eef\|24b2c40\|6312881\|8389924' "$FX/evals"
assert_not_grep '絕對路徑' "$FX/evals"

# 對照用：一個只做過 init 與兩次 commit 的 repo，.git 底下該有的東西
mkdir -p "$FX/plain"; git -C "$FX/plain" init -q -b x
echo a > "$FX/plain/a"; git -C "$FX/plain" add a
git -C "$FX/plain" -c user.name=a -c user.email=a@a commit -q -m a
git -C "$FX/plain" -c user.name=a -c user.email=a@a commit -q --allow-empty -m b

check_fixture() { # check_fixture <name> <commit>
  local name="$1" commit="$2" dest="$FX/fx-$1"
  assert_file "$FIXTURES/$name/setup.sh"
  bash "$FIXTURES/$name/setup.sh" "$dest" >/dev/null 2>&1 || fail "$name setup.sh 失敗"
  assert_eq "$(git -C "$dest" remote)" "" "$name 不該有 remote"
  assert_eq "$(git -C "$dest" log --format=%s)" "head
base" "$name 只有 head、base 兩個 commit"
  assert_eq "$(git -C "$dest" status --short)" "" "$name 工作樹要乾淨"
  git -C "$dest" diff HEAD^ HEAD > "$FX/$name.fixture.diff"
  git -C "$OPSX_ROOT" diff "$commit^" "$commit" > "$FX/$name.orig.diff"
  cmp -s "$FX/$name.fixture.diff" "$FX/$name.orig.diff" || fail "$name 的 head 對 base diff 要等於 $commit 的 diff"
  [ -s "$FX/$name.orig.diff" ] || fail "$name 的 diff 是空的"
  # 跟 tests/scenarios.test.sh 同一條規則：路徑含評測字眼的檔（題目自己的測試檔除外）不能留在題目 repo
  git -C "$dest" ls-files > "$FX/$name.files"
  ! grep -Ev '(\.test\.|_test\.|(^|/)tests?/)' "$FX/$name.files" | grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' || fail "$name 留著含評測字眼的路徑"
  git -C "$dest" ls-tree -r --name-only HEAD^ > "$FX/$name.base-files"
  ! grep -Ev '(\.test\.|_test\.|(^|/)tests?/)' "$FX/$name.base-files" | grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' || fail "$name 的 base 留著含評測字眼的路徑"
  assert_file "$dest/bin/opsx"
  # tests/ 底下描述評測工具的檔不算題目自己的測試；只有這個 commit 改到的測試檔留著
  assert_no_file "$dest/tests/run-candidate.test.sh"
  assert_no_file "$dest/tests/scenarios.test.sh"
  assert_no_file "$dest/tests/eval-playbook.test.sh"
  # 題目自己的測試要跑得起來：共用的 lib.sh 與 fakes 留著
  assert_file "$dest/tests/lib.sh"
  assert_dir "$dest/tests/fakes"
  # 被刪的檔不能留在 .git/objects：git fsck 挖得回來
  assert_eq "$(git -C "$dest" fsck --unreachable --no-reflogs 2>&1)" "" "$name 有 unreachable 物件"
  assert_eq "$(ls "$dest/.git")" "$(ls "$FX/plain/.git")" "$name 的 .git 不該多出檔案（例如刪掉的路徑清單）"
  assert_eq "$(git -C "$dest" rev-parse --abbrev-ref HEAD)" "fix/$name/dev" "$name 停在卡的分支上"
}
check_fixture stop-gate-subagent 8389924
check_fixture gate-title-slug 24b2c40
check_fixture coordinate-usage-limit 6312881

# --- 提問題的 fixture：不是 commit 快照，是一份邏輯表加它的 design 與討論紀錄 ---
QR="$FX/fx-question-reply"
assert_file "$FIXTURES/question-reply/setup.sh"
bash "$FIXTURES/question-reply/setup.sh" "$QR" >/dev/null 2>&1 || fail "question-reply setup.sh 失敗"
assert_eq "$(git -C "$QR" remote)" "" "question-reply 不該有 remote"
assert_eq "$(git -C "$QR" status --short)" "" "question-reply 工作樹要乾淨"
CH="$QR/openspec/changes/report-export"
for f in logic-map.md design.md explore.md; do assert_file "$CH/$f"; done
# 只有 design.md 寫了 fallback_role：回答要把它標成 agent 自己加的
assert_grep 'fallback_role' "$CH/design.md"
assert_grep 'fallback_role' "$CH/logic-map.md"
assert_not_grep 'fallback_role' "$CH/explore.md"
# design.md 不自報出處：要分出哪條是 agent 自己加的，只能拿 explore.md 來比
assert_not_grep 'explore.md' "$CH/design.md"
# 沒給 dest 就停，不在目前目錄建 repo
assert_rc 1 bash "$FIXTURES/question-reply/setup.sh"
# eval 4 的斷言真的帶著 spec 的 Scenario：只看 assertions（expected_output 不逐條評分），逐條對，
# 刪掉或改弱任一條要被抓到；出處要能分出「有比對」與「全標 design.md」
python3 -I -c '
import json, sys
e = next(x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == 4)
print("\n".join(e["assertions"]))' "$EV/evals.json" > "$FX/eval4"
assert_grep 'D1、D2、D3' "$FX/eval4"
assert_grep '至少 2 個選項' "$FX/eval4"
grep 'fallback_role' "$FX/eval4" > "$FX/eval4-design" || fail "eval 4 沒有 fallback_role 的斷言"
assert_grep 'design.md' "$FX/eval4-design"
assert_grep 'path:line' "$FX/eval4-design"
grep 'admin' "$FX/eval4" | grep 'analyst' > "$FX/eval4-explore" || fail "eval 4 沒有 admin 與 analyst 名單的斷言"
assert_grep 'explore.md' "$FX/eval4-explore"
assert_grep 'path:line' "$FX/eval4-explore"
assert_grep '表格' "$FX/eval4"
assert_not_grep '讀了 explore.md' "$FX/eval4"
git -C "$QR" ls-files > "$FX/question-reply.files"
! grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' "$FX/question-reply.files" || fail "question-reply 留著含評測字眼的路徑"

# --- 分類題的 fixture：合成的 base、head 兩個 commit，design.md 在 base，五種分類各有一處 ---
CL="$FX/fx-logic-map-classify"
assert_file "$FIXTURES/logic-map-classify/setup.sh"
bash "$FIXTURES/logic-map-classify/setup.sh" "$CL" >/dev/null 2>&1 || fail "logic-map-classify setup.sh 失敗"
assert_eq "$(git -C "$CL" remote)" "" "logic-map-classify 不該有 remote"
assert_eq "$(git -C "$CL" log --format=%s)" "head
base" "logic-map-classify 只有 head、base 兩個 commit"
assert_eq "$(git -C "$CL" status --short)" "" "logic-map-classify 工作樹要乾淨"
assert_eq "$(git -C "$CL" rev-parse --abbrev-ref HEAD)" "feat/member-export/dev" "logic-map-classify 停在卡的分支上"
CLD="$CL/openspec/changes/member-export/design.md"
assert_file "$CLD"
# design.md 不在 diff 裡：產表的 subagent 只能從 design: 行讀到它
git -C "$CL" diff --name-only HEAD^ HEAD > "$FX/classify.diff-files"
assert_eq "$(cat "$FX/classify.diff-files")" "src/export.py" "head 只改 src/export.py"
# 三條 D：一條有使用者出處、一條 agent 自定（理由沒有使用者／grill／explore）、一條跟程式相反
grep -E '^- D[0-9]' "$CLD" > "$FX/classify-ds"
assert_eq "$(grep -c . "$FX/classify-ds")" 3 "design.md 有三條 D"
grep -A1 -E '^- D1 ' "$CLD" | grep -qF '使用者' || fail "D1 的理由要有使用者出處"
! grep -A1 -E '^- D2 ' "$CLD" | grep -qE '使用者|grill|explore' || fail "D2 的理由不能有使用者或 grill／explore 出處"
grep -qF 'admin 也一樣' "$CLD" || fail "D3 要寫 admin 也不能匯出別部門"
# 程式：schema 的 NOT NULL 讓 role 為 None 的分支走不到；admin 跨部門放行（違反 D3）；email 過濾 design 沒提
grep -qF 'role TEXT NOT NULL' "$CL/schema.sql" || fail "schema.sql 要把 role 定成 NOT NULL"
grep -qF 'user.role is None' "$CL/src/export.py" || fail "head 要有 role 為 None 的分支"
grep -qF 'role != "admin"' "$CL/src/export.py" || fail "head 要讓 admin 跨部門"
grep -qF '"@" not in' "$CL/src/export.py" || fail "head 要有 design 沒提的 email 過濾"
! grep -qF 'email' "$CLD" || fail "design.md 不能提 email"
git -C "$CL" ls-files > "$FX/classify.files"
! grep -Eiq 'eval|test|judge|experiment|rubric|score|compare|benchmark|candidate|arena' "$FX/classify.files" || fail "logic-map-classify 留著含評測字眼的路徑"
assert_rc 1 bash "$FIXTURES/logic-map-classify/setup.sh"
# eval 6：prompt 帶 design: 行；斷言五種標籤的位置、條件照程式字面、標籤寫 design Dn
grep '^6 ' "$FX/evals" | grep -qF 'design: openspec/changes/member-export/design.md' || fail "eval 6 的 prompt 沒有 design: 行"
python3 -I -c '
import json, sys
e = next(x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == 6)
print("\n".join(e["assertions"]))' "$EV/evals.json" > "$FX/eval6"
for k in '照 design D1' '照 design D2（agent 自定）' 'bug：違反 design D3' '沒經過決定' '程式整理' '照程式字面' '照 design D 行'; do
  assert_grep "$k" "$FX/eval6"
done

# --- eval 1 改成 #88：答案講 Stop 閘門與 stage.sh，不再是 commit 閘門 ---
python3 -I -c '
import json, sys
e = next(x for x in json.load(open(sys.argv[1]))["evals"] if x["id"] == 1)
print(e["eval_name"]); print(e["expected_output"]); print("\n".join(e["assertions"]))' "$EV/evals.json" > "$FX/eval1"
assert_grep 'openspec-stop-gate.sh' "$FX/eval1"
assert_grep 'bin/lib/stage.sh' "$FX/eval1"
assert_not_grep 'openspec-commit-gate.sh' "$FX/eval1"
assert_not_grep 'commit-gate' "$FX/eval1"

# --- without 少 logic-map（正例）---
new="$FX/v-new"; without="$FX/v-without"
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug new "$new" >/dev/null 2>&1 || fail "prepare-run new 失敗"
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug without "$without" >/dev/null 2>&1 || fail "prepare-run without 失敗"
assert_dir "$new/.claude/skills/logic-map"
assert_no_file "$without/.claude/skills/logic-map"
ls "$new/.claude/skills" | grep -vx logic-map > "$FX/new-skills"
ls "$without/.claude/skills" > "$FX/without-skills"
assert_eq "$(cat "$FX/without-skills")" "$(cat "$FX/new-skills")" "without 的其他 skill 要跟 new 一樣"
diff -r "$new/.claude/references" "$without/.claude/references" >/dev/null || fail "without 的 references 要跟 new 一樣"
assert_eq "$(git -C "$without" status --short)" "" "without 的工作 repo 要乾淨"
assert_no_file "$new/.claude/skills/logic-map/evals"

# --- 不認得的 variant 被拒（反例）---
bash "$OPSX_ROOT/evals/prepare-run.sh" logic-map gate-title-slug nope "$FX/v-nope" >/dev/null 2> "$FX/nope.err"
assert_eq "$?" 2 "nope 要退出 2"
assert_grep 'without' "$FX/nope.err"
assert_grep 'new' "$FX/nope.err"
assert_grep 'old' "$FX/nope.err"
