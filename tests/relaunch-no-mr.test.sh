#!/usr/bin/env bash
# relaunch 與 dispatch 的「可送的站」：沒有 MR 的卡在 archive 站要送 /archive，workplan 已 merged 的 archive 站照舊不送。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「其他入口把無 MR 的卡送去 archive」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr ps
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_DRIVE_MAX=0
export OPSX_DISPATCH_RETRY_SLEEP=0
SID=329c1d2a-42f9-4e58-a57d-c55ea78ac173
export OPSX_TEST_HERDR_AGENTS="$FX/agents.json"
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_session": {"agent": "claude", "kind": "id", "source": "herdr:claude", "value": "%s"},"agent_status":"idle","pane_id":"w1:pE","tab_id":"w1:tB","workspace_id":"w1"}],"type":"agent_list"}}\n' "$SID" > "$OPSX_TEST_HERDR_AGENTS"

R="$(mk_repo Acmecorp-CS git@gitlab.example.com:acmecorp/Acmecorp-CS.git)"
git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" branch -q feat/docs/mikaela HEAD
C="$R/openspec/changes/docs"; mkdir -p "$C"
printf 'schema: opsx\nkind: chore\n' > "$C/.openspec.yaml"
printf '## 1\n\n- [x] 1.1 a\n' > "$C/tasks.md"
printf '{"tests":"green"}' > "$C/status.json"
printf '# report\n' > "$C/report.md"
printf '{"Acmecorp-CS/docs":{"pane":"w1:pE","tab":"w1:tB","workspace":"acmecorp-cs","workspace_id":"w1","agent":"claude","model":"claude-sonnet-5-5","mode":"autopilot","worktree":"/x","kind":"chore","branch":"feat/docs/mikaela","grants":[],"once":[],"drive_pid":null}}' > "$OPSX_STATE_DIR/dispatch.json"
workplan() { # <status> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: docs\n        branch: feat/docs/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        changes:\n          - name: docs\n            status: pending\n'
  } > "$R/openspec/workplan.yaml"
}
sendable() { ( source "$OPSX_ROOT/bin/lib/stage.sh"; st_sendable_stage "$R" docs "$1" ) && echo yes || echo no; }
cd "$R"

# 正例：無 MR 的卡 relaunch 送 /archive
workplan pending "mr: none"
out="$(opsx relaunch docs 2>&1)"; assert_eq "$?" 0 "無 MR 的卡 relaunch: $out"
grep -q '^agent prompt docs /opsx-workflow:archive docs$' "$OPSX_FAKE_LOG" || fail "relaunch 要送 /opsx-workflow:archive：$(cat "$OPSX_FAKE_LOG")"
# dispatch 的交回 session 與 feature 派工用同一個判斷
assert_eq "$(sendable archive)" yes "無 MR 的 archive 站可送"
assert_eq "$(sendable pr)" yes "一般站照舊可送"

# 反例：workplan 已 merged 的卡 relaunch 照舊報錯、不送鍵
workplan merged ""; : > "$OPSX_FAKE_LOG"
out="$(opsx relaunch docs 2>&1)"; [ $? -ne 0 ] || fail "merged 的卡 relaunch 要報錯: $out"
case "$out" in *"沒有可送的那一站"*) ;; *) fail "報錯要說沒有可送的那一站：$out" ;; esac
grep -qE '^(pane send-keys|pane send-text|agent start|agent prompt)' "$OPSX_FAKE_LOG" && fail "merged 的卡不送鍵：$(cat "$OPSX_FAKE_LOG")"
assert_eq "$(sendable archive)" no "merged 的 archive 站不可送"
assert_eq "$(sendable split)" no "split 不可送"

echo "relaunch-no-mr ok"
