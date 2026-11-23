#!/usr/bin/env bash
# Stop hook 與併入項目：tasks.md 寫完之後才併進來的項目（propose 寫 tasks.md 的空窗）不能被帶過。
# 驗收：openspec/changes/agent-20261111-2326/specs/inbox-write-lock/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
H="$OPSX_ROOT/hooks"
export CLAUDE_PLUGIN_ROOT="$OPSX_ROOT"

R="$(mk_repo Acmecorp-AI git@gitlab.example.com:acmecorp/Acmecorp-AI.git)"
C="$R/openspec/changes/eval-core"; mk_change "$R" eval-core
printf 'schema: opsx\ncreated: 2026-11-05\nkind: bug-fix\n' > "$C/.openspec.yaml"
printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$C/explore.md"
printf '## 1. x\n\n- [x] 1.1 a\n  - 驗收：R\n  - 測試：tests/a.test.sh\n' > "$C/tasks.md"
printf '{"phase":"apply","step":2,"total":2,"label":"x","tests":"green","at":"2026-11-05T15:00:00+08:00"}' > "$C/status.json"
printf -- '---\nsource: me\nkind_of_work: planned\n---\n\n## 一句話\n\nx\n\n## 併入：2026-11-06T10:00:00+08:00 agent:foo\n\n- id: late-item\n- kind_of_work: planned\n- type: bug\n\n晚到的項目\n' > "$C/inbox.md"
STOP_STATE="$OPSX_STATE_DIR/stop-chain"
sg() { printf '{"cwd":"%s","stop_hook_active":false}' "$R" | bash "$H/openspec-stop-gate.sh" 2>/dev/null; true; }
reason() { printf '%s' "$1" | jq -r '.reason // ""'; }

# tasks.md 沒提到併入的 id：擋，點名 id
rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in *late-item*) ;; *) fail "沒有去處的併入項目要擋並點名 late-item：$out" ;; esac

# tasks.md 提到它：不再因為併入擋（其餘照原本的站，這裡是 review）
printf '%s\n- [x] 1.2 處理 late-item\n  - 驗收：R\n  - 測試：無 · 文件\n' "$(cat "$C/tasks.md")" > "$C/tasks.md"
rm -rf "$STOP_STATE"
out="$(sg)"
case "$(reason "$out")" in *late-item*) fail "tasks.md 已提到 id 不能再因併入擋：$out" ;; esac

# 卡在 babysit 站、MR 全綠、邏輯表對得上，但表裡有沒標記的沒經過決定項：Stop hook 報的第一條是它
# 驗收：openspec/changes/logic-map-undecided-gate/specs/board-collect/spec.md「opsx merge 與 Stop hook 擋同一條」
use_fakes glab; export OPSX_FAKE_LOG="$FX/glab.log" OPSX_TEST_GLAB_JSON="$FX/mr.json" OPSX_MR_CACHE_TTL=0
printf '{"state":"opened","draft":false,"has_conflicts":false,"sha":"abc1234def","head_pipeline":{"status":"success"},"unresolved_discussions_count":0}' > "$OPSX_TEST_GLAB_JSON"
printf '# report\n\n## MR\nhttps://gitlab.example.com/a/b/-/merge_requests/212 · opened 2026-11-10 · auto-merge: no\nbabysit: 2026-11-10T14:00:00+08:00\n\n## 邏輯表\nopenspec/changes/eval-core/logic-map.md · abc1234\n' > "$C/report.md"
said() { sed -n 1p "$OPSX_STATE_DIR/stop-said/Acmecorp-AI-eval-core"; }
printf '# 邏輯表\n\n### ⚠ 要看的地方\n- 沒經過決定。D4：以後都 判斷\n' > "$C/logic-map.md"
rm -rf "$STOP_STATE"; sg >/dev/null
assert_eq "$(said)" "babysit 做完，邏輯表有沒經過決定的項目沒處理" "沒標記的項要是 Stop hook 的第一條 blocker"
printf '# 邏輯表\n\n### ⚠ 要看的地方\n- 沒經過決定。D4：以後都 判斷 · gate logic-map-undecided-r3\n' > "$C/logic-map.md"
rm -rf "$STOP_STATE"; sg >/dev/null
assert_eq "$(said)" "babysit 一輪做完，等 MR 合併" "標記過的項不擋"

echo "stop-gate-merge ok"
