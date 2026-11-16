#!/usr/bin/env bash
# opsx drive 遇到下一站是 archive 的卡：沒有 MR（workplan mr: none、branch 沒有 commit）要送 /archive，workplan 已 merged 才結束。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「drive 把無 MR 的卡送去 archive」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=5

R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" branch -q feat/docs/mikaela HEAD
C="$R/openspec/changes/docs"
card() {
  rm -rf "$C"; mkdir -p "$C" "$OPSX_STATE_DIR"
  printf 'schema: opsx\nkind: chore\n' > "$C/.openspec.yaml"
  printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"
  printf '{"phase":"review","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-16T14:00:00+08:00"}' > "$C/status.json"
  printf '# report\n' > "$C/report.md"
  printf '{"Acmecorp-CS/docs":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
}
workplan() { # <status> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: docs\n        branch: feat/docs/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        changes:\n          - name: docs\n            status: pending\n'
  } > "$R/openspec/workplan.yaml"
}
# 假 agent：收到 /archive 就把卡搬進 archive/
mkdir -p "$R/openspec/changes/archive"
printf 'case "$1" in "/opsx-workflow:archive docs") mv "%s" "%s/openspec/changes/archive/2026-11-16-docs" ;; esac\n' "$C" "$R" > "$FX/on_prompt.sh"
export OPSX_TEST_ON_PROMPT="$FX/on_prompt.sh"
cd "$R"

# 正例：無 MR 的卡被送去 archive，歸檔後 drive 結束
card; workplan pending "mr: none"; : > "$OPSX_FAKE_LOG"
out="$(opsx drive docs 2>&1)"; assert_eq "$?" 0 "drive 無 MR: $out"
grep -q '^agent prompt .*/opsx-workflow:archive docs' "$OPSX_FAKE_LOG" || fail "無 MR 的卡要送 /opsx-workflow:archive：$(cat "$OPSX_FAKE_LOG") / $out"
case "$out" in *"已歸檔"*) ;; *) fail "歸檔後 drive 要結束：$out" ;; esac
case "$out" in *"已 merged"*) fail "無 MR 的卡不能說已 merged：$out" ;; esac

# 反例：workplan 已 merged 的卡照舊結束、不送 /archive
rm -rf "$R/openspec/changes/archive/2026-11-16-docs"
card; workplan merged ""; : > "$OPSX_FAKE_LOG"
out="$(opsx drive docs 2>&1)"; assert_eq "$?" 0 "drive merged: $out"
case "$out" in *"已 merged"*) ;; *) fail "已合併的卡要說已 merged：$out" ;; esac
grep -q '/opsx-workflow:archive' "$OPSX_FAKE_LOG" && fail "已 merged 的卡 drive 不送 /archive：$(cat "$OPSX_FAKE_LOG")"

echo "drive-no-mr ok"
