#!/usr/bin/env bash
# opsx stack <主> <子> <sha>：把 subagent 在子殼分支上的 commit 疊回 PR 分支，勾主殼 tasks.md。
# 驗收：openspec/changes/apply-fanout/specs/subchange-stack/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo stk)"; mkdir -p "$OPSX_STATE_DIR"
printf 'openspec/\n' >> "$R/.git/info/exclude"   # 跟真的 repo 一樣，openspec/ 不進 git
M="$R/openspec/changes/m"; mkdir -p "$M"; printf 'schema: opsx\nkind: dev\n' > "$M/.openspec.yaml"
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: f
    prs:
      - name: m
        branch: feat/m/u
        status: in-progress
        depends-on: []
        changes:
          - name: s1
            status: pending
            depends-on: []
          - name: s2
            status: pending
            depends-on: [s1]
          - name: s3
            status: pending
            depends-on: []
EOF
cat > "$M/tasks.md" <<'EOF'
## 1. 子 change

- [ ] 1.1 `s1`：改 a.txt
  - 驗收：x
  - 測試：x
- [ ] 1.2 `s2`：也改 a.txt（依賴 1.1）
  - 驗收：x
  - 測試：x
- [ ] 1.3 `s3`：加 b.txt
  - 驗收：x
  - 測試：x
EOF
cd "$R"
git checkout -q -b feat/m/u
printf 'base\n' > a.txt; git add a.txt; git commit -q -m "chore: base"
# 三個子 change 都從 PR 分支目前的 HEAD 開（subagent 的起點）
git checkout -q -b feat/m--s1/u feat/m/u; printf 's1\n' > a.txt; git commit -q -am "feat: s1"; S1="$(git rev-parse HEAD)"
git checkout -q -b feat/m--s2/u feat/m/u; printf 's2\n' > a.txt; git commit -q -am "feat: s2"; S2="$(git rev-parse HEAD)"
git checkout -q -b feat/m--s3/u feat/m/u; printf 'b\n' > b.txt; git add b.txt; git commit -q -m "feat: s3"; S3="$(git rev-parse HEAD)"
git checkout -q -b other feat/m/u

# --- Scenario：不在 PR 分支上 ---
before="$(git rev-parse HEAD)"
out="$(opsx stack m s1 "$S1" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "不在 PR 分支要拒絕: $out"
echo "$out" | grep -q 'feat/m/u' || fail "訊息要說 PR 分支: $out"
assert_eq "$(git rev-parse HEAD)" "$before" "不在 PR 分支不動歷史"

git checkout -q feat/m/u
base="$(git rev-parse HEAD)"

# --- Scenario：依賴的子 change 還沒疊回 ---
out="$(opsx stack m s2 "$S2" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "依賴沒疊回要拒絕: $out"
echo "$out" | grep -q 's1' || fail "訊息要列出 s1: $out"
assert_eq "$(git rev-parse HEAD)" "$base" "依賴沒疊回不動歷史"

# --- 邊界：sha 不存在、子 change 不在 workplan、參數不對 ---
assert_rc 2 opsx stack m s1 0000000000000000000000000000000000000000
assert_rc 2 opsx stack m nope "$S1"
assert_rc 2 opsx stack m s1
assert_eq "$(git rev-parse HEAD)" "$base" "邊界都不動歷史"
assert_eq "$(git status --porcelain)" "" "邊界都不留髒 tree"

# --- Scenario：乾淨疊回（cherry-pick 執行時主殼項目已勾） ---
printf '#!/bin/sh\ncp "%s" "%s"\n' "$M/tasks.md" "$FX/seen-tasks.md" > .git/hooks/prepare-commit-msg
chmod +x .git/hooks/prepare-commit-msg
printf 'keep me\n' > "$FX/victim"; ln -s "$FX/victim" "$M/tasks.md.stack.tmp"   # symlink-safe-writes：舊的固定暫存檔名
out="$(opsx stack m s1 "$S1" 2>&1)"; assert_eq "$?" 0 "乾淨疊回: $out"
grep -q '^- \[x\] 1.1 `s1`' "$FX/seen-tasks.md" || fail "cherry-pick 當下 s1 要已勾: $(cat "$FX/seen-tasks.md")"
rm .git/hooks/prepare-commit-msg
assert_eq "$(cat "$FX/victim")" "keep me" "tasks.md 的舊暫存檔名上的 symlink 不能被寫"
rm -f "$M/tasks.md.stack.tmp"
assert_eq "$(git rev-list --count "$base"..HEAD)" 1 "PR 分支多一個 commit"
assert_eq "$(git log -1 --format=%s)" "feat: s1" "subject 跟子 change 的 commit 一樣"
grep -q '^- \[x\] 1.1 `s1`' "$M/tasks.md" || fail "s1 要勾: $(cat "$M/tasks.md")"
grep -q '^- \[ \] 1.2 `s2`' "$M/tasks.md" || fail "s2 不該勾"
grep -q '^- \[ \] 1.3 `s3`' "$M/tasks.md" || fail "s3 不該勾"

# --- Scenario：兩個子 change 改同一行 ---
head="$(git rev-parse HEAD)"
# 檔尾不帶換行：寫回也要逐字相同
printf '%s' "$(cat "$M/tasks.md")" > "$FX/t"; mv "$FX/t" "$M/tasks.md"
cp "$M/tasks.md" "$FX/tasks-before.md"
out="$(opsx stack m s2 "$S2" 2>&1)"; rc=$?
assert_eq "$rc" 3 "衝突退出 3: $out"
cmp -s "$M/tasks.md" "$FX/tasks-before.md" || fail "衝突後 tasks.md 要跟跑之前逐字相同: $(cat "$M/tasks.md")"
echo "$out" | grep -q 'a.txt' || fail "要印衝突檔: $out"
assert_eq "$(git status --porcelain)" "" "衝突後工作目錄乾淨"
assert_eq "$(git rev-parse HEAD)" "$head" "衝突後 HEAD 不變"
assert_grep 's2' "$M/decisions.tsv"
assert_grep '疊回衝突' "$M/decisions.tsv"
grep -q '^- \[ \] 1.2 `s2`' "$M/tasks.md" || fail "衝突的 s2 不勾"
echo >> "$M/tasks.md"

# 衝突之後沒依賴的子 change 照疊
out="$(opsx stack m s3 "$S3" 2>&1)"; assert_eq "$?" 0 "s3 疊回: $out"
grep -q '^- \[x\] 1.3 `s3`' "$M/tasks.md" || fail "s3 要勾"

# --- Scenario：裸名項目被拒並說明格式 ---
cat >> "$R/openspec/workplan.yaml" <<'EOF'
          - name: s4
            status: pending
            depends-on: []
EOF
printf -- '- [ ] 1.4 s4：沒包反引號\n  - 驗收：x\n  - 測試：x\n' >> "$M/tasks.md"
git checkout -q -b feat/m--s4/u feat/m/u; printf 'c\n' > c.txt; git add c.txt; git commit -q -m "feat: s4"; S4="$(git rev-parse HEAD)"
git checkout -q feat/m/u
head="$(git rev-parse HEAD)"
out="$(opsx stack m s4 "$S4" 2>&1)"; rc=$?
assert_eq "$rc" 2 "裸名項目要拒絕: $out"
echo "$out" | grep -q '`s4`' || fail "訊息要含 \`s4\`: $out"
echo "$out" | grep -q -- '- \[ \] <編號> `s4`' || fail "訊息要給格式範例: $out"
assert_eq "$(git rev-parse HEAD)" "$head" "裸名被拒不動歷史"

# --- Scenario：cherry-pick 非衝突失敗時還原 tasks.md ---
cat >> "$R/openspec/workplan.yaml" <<'EOF'
          - name: s5
            status: pending
            depends-on: []
EOF
printf -- '- [ ] 1.5 `s5`：跟 s3 一樣加 b.txt\n  - 驗收：x\n  - 測試：x\n' >> "$M/tasks.md"
git checkout -q -b feat/m--s5/u "$base"; printf 'b\n' > b.txt; git add b.txt; git commit -q -m "feat: s5"; S5="$(git rev-parse HEAD)"
git checkout -q feat/m/u
head="$(git rev-parse HEAD)"
cp "$M/tasks.md" "$FX/tasks-before.md"
out="$(opsx stack m s5 "$S5" 2>&1)"; rc=$?
[ $rc -ne 0 ] || fail "空 cherry-pick 要失敗: $out"
echo "$out" | grep -q '不是衝突' || fail "訊息要含「不是衝突」: $out"
cmp -s "$M/tasks.md" "$FX/tasks-before.md" || fail "非衝突失敗後 tasks.md 要跟跑之前逐字相同: $(cat "$M/tasks.md")"
assert_eq "$(git rev-parse HEAD)" "$head" "非衝突失敗不動歷史"

# --- cherry-pick 被 commit hook 擋時，印出 hook 的原因 ---
cat >> "$R/openspec/workplan.yaml" <<'EOF'
          - name: s6
            status: pending
            depends-on: []
EOF
printf -- '- [ ] 1.6 `s6`：加 d.txt\n  - 驗收：x\n  - 測試：x\n' >> "$M/tasks.md"
git checkout -q -b feat/m--s6/u "$base"; printf 'd\n' > d.txt; git add d.txt; git commit -q -m "feat: s6"; S6="$(git rev-parse HEAD)"
git checkout -q feat/m/u
printf '#!/bin/sh\necho HOOK-SAYS-NO >&2\nexit 1\n' > .git/hooks/prepare-commit-msg; chmod +x .git/hooks/prepare-commit-msg
head="$(git rev-parse HEAD)"
cp "$M/tasks.md" "$FX/tasks-before.md"
out="$(opsx stack m s6 "$S6" 2>&1)"; rc=$?
rm .git/hooks/prepare-commit-msg
[ $rc -ne 0 ] || fail "hook 擋下要失敗: $out"
echo "$out" | grep -q 'HOOK-SAYS-NO' || fail "要印出 hook 的原因: $out"
cmp -s "$M/tasks.md" "$FX/tasks-before.md" || fail "hook 擋下後 tasks.md 要跟跑之前逐字相同: $(cat "$M/tasks.md")"
assert_eq "$(git rev-parse HEAD)" "$head" "hook 擋下不動歷史"

# --- Scenario：文件寫出反引號格式 ---
for f in skills/propose/SKILL.md references/work-split.md; do
  grep -q '反引號' "$OPSX_ROOT/$f" || fail "$f 要寫反引號"
  grep -q 'opsx stack' "$OPSX_ROOT/$f" || fail "$f 要提 opsx stack"
  grep -q -- '- \[ \] 1.1 `<子 change 名>`：' "$OPSX_ROOT/$f" || fail "$f 要給範例"
done
echo ok
