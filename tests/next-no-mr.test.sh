#!/usr/bin/env bash
# opsx next：feature session 的成員卡沒有 MR（workplan mr: none、branch 沒有 commit）、還沒歸檔時，要接它去 /archive；PR 已 merged 的照舊跳過。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「feature session 接手無 MR 的成員卡」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R="$(mk_repo nx)"; mk_change "$R" m1; mkdir -p "$OPSX_STATE_DIR"
git -C "$R" checkout -q -
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" branch -q feat/m2/mikaela HEAD
workplan() { # <m2 的 status> <m2 的 mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: fs\n    prs:\n'
    printf '      - name: m1\n        branch: feat/m1/mikaela\n        status: in-progress\n        depends-on: []\n        changes:\n          - name: a1\n            status: done\n'
    printf '      - name: m2\n        branch: feat/m2/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        depends-on: []\n        changes:\n          - name: a2\n            status: done\n'
  } > "$R/openspec/workplan.yaml"
}
mkdir -p "$R/openspec/changes/m2"
printf 'schema: opsx\nkind: chore\n' > "$R/openspec/changes/m2/.openspec.yaml"
printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/m1/tasks.md"
printf -- '- [x] 1.1 x\n' > "$R/openspec/changes/m2/tasks.md"
printf '{"tests":"green"}' > "$R/openspec/changes/m2/status.json"
printf '# report\n\nhttps://github.com/o/r/pull/7\n' > "$R/openspec/changes/m1/report.md"
printf '# report\n' > "$R/openspec/changes/m2/report.md"
git -C "$R" worktree add -q "$R/.claude/worktrees/fs" feat/m1/mikaela
J="$OPSX_STATE_DIR/dispatch.json"
printf '{"nx/@fs":{"mode":"autopilot","pane":"w1:p1","agent":"claude","worktree":"%s/.claude/worktrees/fs"},' "$R" > "$J"
printf '"nx/m1":{"mode":"autopilot","pane":"w1:p1","agent":"claude","herdr_name":"fs","via":"@fs","feature":"fs","branch":"feat/m1/mikaela"},' >> "$J"
printf '"nx/m2":{"mode":"autopilot","pane":"w1:p1","agent":"claude","herdr_name":"fs","via":"@fs","feature":"fs","branch":"feat/m2/mikaela"}}' >> "$J"
cd "$R/.claude/worktrees/fs"

# 正例：m1 等合併，m2 沒有 MR、還沒歸檔 → 接 m2 去 archive
workplan pending "mr: none"
assert_eq "$(opsx next)" "/opsx-workflow:archive m2" "無 MR 的成員卡要接去 archive"

# 反例：m2 的 PR 已 merged → 跳過，沒有下一個
workplan merged "mr: none"
assert_eq "$(opsx next)" "none" "merged 的 archive 站照舊跳過"

echo "next-no-mr ok"
