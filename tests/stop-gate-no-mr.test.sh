#!/usr/bin/env bash
# Stop hook 與無 MR 收尾：workplan mr: none、branch 沒有 commit 的卡 review 完要被推去 /archive；workplan 已 merged 的卡照舊放行。
# 驗收：openspec/changes/agent-20261116-1405-2/specs/no-mr-archive/spec.md「Stop hook 推無 MR 的卡去 archive」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
git -C "$R" update-ref refs/remotes/origin/main HEAD
C="$R/openspec/changes/docs"; mk_change "$R" docs
printf 'schema: opsx\ncreated: 2026-11-16\nkind: chore\n' > "$C/.openspec.yaml"
printf '## 1. x\n\n- [x] 1.1 a\n  - 驗收：R\n  - 測試：無 · 文件\n' > "$C/tasks.md"
printf '{"phase":"review","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-16T14:00:00+08:00"}' > "$C/status.json"
printf '# report\n\n### 待修（範圍內）\n\n### 範圍外\n' > "$C/report.md"
workplan() { # <status> <mr 欄位行，空字串就不寫>
  { printf 'features:\n  - name: f\n    prs:\n      - name: docs\n        branch: feat/docs/mikaela\n        status: %s\n' "$1"
    [ -z "$2" ] || printf '        %s\n' "$2"
    printf '        changes:\n          - name: docs\n            status: pending\n'
  } > "$R/openspec/workplan.yaml"
}
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
sg() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
reason() { printf '%s' "$1" | jq -r '.reason // ""'; }

# 正例：無 MR 的卡停下時被推去 archive
workplan pending "mr: none"; rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in */opsx-workflow:archive*) ;; *) fail "無 MR 的卡要被推去 /opsx-workflow:archive：$out" ;; esac

# 反例：無 MR 的卡有 open 的 decision gate 時放行
printf '## q\ntype: decision\nstatus: open\n問題: 選哪個？\n' > "$C/gates.md"
rm -rf "$STOP_STATE"
assert_eq "$(sg)" "" "有 open gate 要放行"
rm -f "$C/gates.md"

# 反例：workplan 已 merged 的卡（沒有 mr 欄位）停下時放行
workplan merged ""; rm -rf "$STOP_STATE"
assert_eq "$(sg)" "" "workplan merged 的 archive 站照舊放行"

# 驗收 openspec/changes/agent-20261116-1640/specs/no-mr-archive/spec.md「worktree 快轉到新 main 後仍推去 archive」
# worktree（已在 feat/docs/mikaela）快轉到 report 之後才有的 main commit：branch 與 origin/main 同一個 commit，沒有自己的 commit
touch -t 202601010000 "$C/report.md"
git -C "$R" commit -q --allow-empty -m newer-main
git -C "$R" update-ref refs/remotes/origin/main HEAD
workplan pending "mr: none"; rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in */opsx-workflow:archive*) ;; *) fail "快轉到新 main 後要推去 archive：$out" ;; esac
case "$(reason "$out")" in *"再跑一次 /opsx-workflow:review"*) fail "快轉到新 main 不該要求重審：$out" ;; esac

# 反例：沒標 mr 的卡（下一站 pr）在 report 後有新 commit，照舊要求重審
workplan pending ""; rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in *"再跑一次 /opsx-workflow:review"*) ;; *) fail "pr 站在 report 後有新 commit 要求重審：$out" ;; esac

# 反例（D11）：workplan 的 branch 沒有自己的 commit（站仍是 archive），但 session 的 HEAD 在另一個 branch 上有 report 之後的 commit → 照舊要求重審
git -C "$R" checkout -q -b feat/docs/other
git -C "$R" commit -q --allow-empty -m unreviewed
workplan pending "mr: none"; rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in *"再跑一次 /opsx-workflow:review"*) ;; *) fail "HEAD 有 report 之後的自己的 commit 要求重審：$out" ;; esac

echo "stop-gate-no-mr ok"
