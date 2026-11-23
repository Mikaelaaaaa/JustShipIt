#!/usr/bin/env bash
# git prepare-commit-msg（opsx init 以 hook.opsx.event 與 hook.opsx.command 安裝）：agent 的 commit 在真的發生時照卡判斷，
# 規則跟 PreToolUse 的 openspec-commit-gate.sh 一樣，但看的是真的 commit，不論指令怎麼寫。擋 = 原因印到 stderr、exit 1。
# 參數：$1 訊息檔。驗收：specs/commit-gate-git-hook/spec.md。

# 人的 commit 直接放行；這行在 source 任何東西之前，perl、python、jq 壞掉也擋不到人
[ "${CLAUDECODE:-}" = 1 ] || [ -n "${OPSX_CARD:-}" ] || exit 0
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" < /dev/null
export OPSX_CWD="$PWD"
block() { printf '%s\n' "$1" >&2; exit 1; }

top="$(repo_top)"
[ -n "$top" ] || block "opsx commit 閘門：讀不到主 checkout（git rev-parse --git-common-dir 失敗），先擋下。"
[ -f "$top/openspec/workplan.yaml" ] || exit 0

if grep -qF '[no-change]' "$1"; then
  mkdir -p "$OPSX_STATE_DIR"
  printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(repo_name)" "$(branch)" "$(head -n 1 "$1" | cut -c1-200)" | opsx_append "$OPSX_STATE_DIR/bypass.log"
  exit 0
fi

d="$(card_dir)"
[ -n "$d" ] || block "opsx commit 閘門：branch '$(branch)' 對不到 openspec/changes/<slug>/。先 /opsx-workflow:propose 開卡（或 /opsx-workflow:explore），或在 commit 訊息加 [no-change] 說明為什麼這個 commit 不屬於任何 change。"
case "$(card_slug)" in
  *--*)
    [ -f "$d/tasks.md" ] || block "opsx commit 閘門：${d#"$top"/} 沒有 tasks.md。先 /opsx-workflow:propose 寫出子殼的 tasks.md 再 commit；不屬於 task 的改動加 [no-change]。" ;;
  *)
    if [ "$(tasks_done "$d")" -eq 0 ]; then
      block "opsx commit 閘門：${d#"$top"/} 的 tasks.md 還沒有任何勾（$( [ -f "$d/tasks.md" ] && echo '有 tasks.md 但全未勾' || echo '沒有 tasks.md' )）。先 /opsx-workflow:apply 做完一個 task 並勾起來再 commit；不屬於 task 的改動加 [no-change]。"
    fi ;;
esac
exit 0
