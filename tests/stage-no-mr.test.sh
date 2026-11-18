#!/usr/bin/env bash
# 無 MR 收尾：workplan PR 標 mr: none、branch 相對 <primary remote>/main 沒有 commit 時，review 之後下一站是 archive。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「無 MR 收尾的條件」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 只 source stage.sh：hooks/_lib.sh（router、Stop hook）就是這樣載入的
stage() { ( source "$OPSX_ROOT/bin/lib/stage.sh"; stage_name "$1" "$2" ); }

# repo 一個 commit、remote origin 的 main 指向它；卡 c 已 review（report.md 沒 MR 網址、tasks 全勾）
fixture() { # <name> → 印 repo 路徑
  local r; r="$(mk_repo "$1" git@gitlab.example.com:g/p.git)"
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$r/openspec/changes/c"
  printf 'schema: opsx\nkind: dev\n' > "$r/openspec/changes/c/.openspec.yaml"
  printf '## 1\n- [x] 1.1 a\n' > "$r/openspec/changes/c/tasks.md"
  printf '{"tests":"green"}\n' > "$r/openspec/changes/c/status.json"
  printf '# report\n沒有 MR\n' > "$r/openspec/changes/c/report.md"
  printf '%s' "$r"
}
workplan() { # <repo> <pr 名> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: %s\n        branch: feat/c/mikaela\n        status: pending\n' "$2"
    [ -z "$3" ] || printf '        %s\n' "$3"
    printf '        changes:\n          - name: c\n            status: pending\n'
  } > "$1/openspec/workplan.yaml"
}

# 一般場景：none、與 remote main 相同 → archive
R="$(fixture same)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
assert_eq "$(stage "$R" c)" archive "mr: none、branch 沒 commit"

# 一般場景：沒寫 mr、與 remote main 相同 → pr
R="$(fixture nofield)"; workplan "$R" c ""; git -C "$R" branch -q feat/c/mikaela HEAD
assert_eq "$(stage "$R" c)" pr "沒標 mr: none"

# 一般場景：none、branch 多 1 個 commit → pr
R="$(fixture ahead)"; workplan "$R" c "mr: none"
git -C "$R" checkout -q -b feat/c/mikaela; git -C "$R" commit -q --allow-empty -m code
assert_eq "$(stage "$R" c)" pr "branch 有自己的 commit"

# 邊界：branch 本地不存在 → pr
R="$(fixture nobranch)"; workplan "$R" c "mr: none"
assert_eq "$(stage "$R" c)" pr "branch 不存在"

# 邊界：branch 落後 remote main，沒有自己的 commit → archive
R="$(fixture behind)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
git -C "$R" commit -q --allow-empty -m newer-main; git -C "$R" update-ref refs/remotes/origin/main HEAD
assert_eq "$(stage "$R" c)" archive "branch 只落後 main"

# 邊界：有 gitlab remote 時以 gitlab/main 為準（origin/main 較舊，用它會誤判成有 commit）
R="$(fixture gitlab)"; workplan "$R" c "mr: none"; git -C "$R" remote add gitlab git@gitlab.example.com:g/p.git
git -C "$R" checkout -q -b feat/c/mikaela; git -C "$R" commit -q --allow-empty -m merged-upstream
git -C "$R" update-ref refs/remotes/gitlab/main HEAD
assert_eq "$(stage "$R" c)" archive "primary remote 是 gitlab"

# 邊界：沒有 <primary remote>/main → pr
R="$(fixture nobase)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
git -C "$R" update-ref -d refs/remotes/origin/main
assert_eq "$(stage "$R" c)" pr "base 不存在"

# 邊界：卡是 PR 底下的 change，PR 名不同 → 以 change 名找到所屬 PR
R="$(fixture child)"; workplan "$R" docs-pr "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
assert_eq "$(stage "$R" c)" archive "change 名對到 PR"

# 邊界：review 退回的 task 沒勾 → apply（無 MR 的判斷排在未勾 task 之後）
R="$(fixture reopened)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
printf '## 1\n- [x] 1.1 a\n\n## R1. review 退回\n- [ ] R1.1 b\n' > "$R/openspec/changes/c/tasks.md"
assert_eq "$(stage "$R" c)" apply "退回的 task 沒做完"

# 邊界：report.md 已有 MR 網址 → babysit（無 MR 的判斷排在 MR 網址之後）
R="$(fixture hasmr)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
printf '# report\n\n## MR\nhttps://gitlab.example.com/g/p/-/merge_requests/9\n' > "$R/openspec/changes/c/report.md"
assert_eq "$(stage "$R" c)" babysit "已開 MR"

# 判不成時 pr 行附原因：驗收 openspec/changes/agent-20261116-1640/specs/no-mr-archive/spec.md「標了不開 MR 但判不成時 pr 行附原因」
line() { ( source "$OPSX_ROOT/bin/lib/stage.sh"; stage_of "$1" "$2" ); }
has() { case "$1" in *"$2"*) ;; *) fail "[$2] not in [$1]${3:+ — $3}" ;; esac; }
hasnt() { case "$1" in *"$2"*) fail "[$2] should not be in [$1]${3:+ — $3}" ;; esac; }

R="$(fixture why-ahead)"; workplan "$R" c "mr: none"
git -C "$R" checkout -q -b feat/c/mikaela; git -C "$R" commit -q --allow-empty -m a; git -C "$R" commit -q --allow-empty -m b
out="$(line "$R" c)"; has "$out" "pr · c" "branch 有 2 commit"; has "$out" "workplan mr: none，但 branch 有 2 個自己的 commit" "branch 有 2 commit"

R="$(fixture why-nobranch)"; workplan "$R" c "mr: none"
out="$(line "$R" c)"; has "$out" "pr · c"; has "$out" "workplan mr: none，但 本地 branch feat/c/mikaela 查不到"

R="$(fixture why-nobase)"; workplan "$R" c "mr: none"; git -C "$R" branch -q feat/c/mikaela HEAD
git -C "$R" update-ref -d refs/remotes/origin/main
out="$(line "$R" c)"; has "$out" "pr · c"; has "$out" "workplan mr: none，但 origin/main 查不到"

R="$(fixture why-upper)"; workplan "$R" c "mr: None"; git -C "$R" branch -q feat/c/mikaela HEAD
out="$(line "$R" c)"; has "$out" "pr · c"; has "$out" "workplan mr: None，但 mr: None 不認得，只認 none"

R="$(fixture why-no)"; workplan "$R" c "mr: no"; git -C "$R" branch -q feat/c/mikaela HEAD
out="$(line "$R" c)"; has "$out" "pr · c"; has "$out" "workplan mr: no，但 mr: no 不認得，只認 none"

R="$(fixture why-nobranchfield)"
printf 'features:\n  - name: f\n    prs:\n      - name: c\n        status: pending\n        mr: none\n' > "$R/openspec/workplan.yaml"
out="$(line "$R" c)"; has "$out" "pr · c"; has "$out" "workplan mr: none，但 workplan 沒寫 branch"

# 反例：沒寫 mr 欄位 → pr 行不附原因
R="$(fixture why-nofield)"; workplan "$R" c ""; git -C "$R" branch -q feat/c/mikaela HEAD
out="$(line "$R" c)"; has "$out" "pr · c"; hasnt "$out" "workplan mr:"

echo "stage-no-mr ok"
