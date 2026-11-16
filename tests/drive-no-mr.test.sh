#!/usr/bin/env bash
# opsx drive 遇到下一站是 archive 的卡：沒有 MR（workplan mr: none、branch 沒有 commit）與 workplan 已 merged 要說不同的話。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「drive 不把無 MR 的卡說成已合併」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_POLL=0 OPSX_DRIVE_MAX=3

R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" branch -q feat/docs/mikaela HEAD
C="$R/openspec/changes/docs"; mkdir -p "$C" "$OPSX_STATE_DIR"
printf 'schema: opsx\nkind: chore\n' > "$C/.openspec.yaml"
printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"
printf '{"phase":"review","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-16T14:00:00+08:00"}' > "$C/status.json"
printf '# report\n' > "$C/report.md"
printf '{"Acmecorp-CS/docs":{"mode":"drive","pane":"p42","grants":[]}}' > "$OPSX_STATE_DIR/dispatch.json"
workplan() { # <status> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: docs\n        branch: feat/docs/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        changes:\n          - name: docs\n            status: pending\n'
  } > "$R/openspec/workplan.yaml"
}
cd "$R"

# 正例：無 MR 的卡結束訊息寫沒有 MR
workplan pending "mr: none"
out="$(opsx drive docs 2>&1)"; assert_eq "$?" 0 "drive 無 MR: $out"
case "$out" in *"沒有 MR"*) ;; *) fail "無 MR 的卡要說沒有 MR：$out" ;; esac
case "$out" in *"已 merged"*) fail "無 MR 的卡不能說已 merged：$out" ;; esac

# 反例：workplan 已 merged 的卡照舊說已 merged
workplan merged ""
out="$(opsx drive docs 2>&1)"; assert_eq "$?" 0 "drive merged: $out"
case "$out" in *"已 merged"*) ;; *) fail "已合併的卡要說已 merged：$out" ;; esac

echo "drive-no-mr ok"
