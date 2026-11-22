#!/usr/bin/env bash
# 共用：訊息、git 位置、TOML 小工具。被 bin/opsx source。

COORDINATOR_AGENT=opsx-coordinator   # 協調者 session 在 herdr 的名字；bin/lib/coordinate.py 的 COORDINATOR 是同一個

say()  { printf '%s\n' "$*"; }
warn() { printf 'opsx: %s\n' "$*" >&2; }
die()  { printf 'opsx: %s\n' "$*" >&2; exit "${2:-2}"; }

# 主 repo 的根目錄：在 dispatch 開的 linked worktree（<top>/.claude/worktrees/<slug>）裡也回主 repo，
# 因為卡（openspec/）只在主 repo、dispatch.json 的 key 也是主 repo 的名字。不在 repo 裡回空字串。
git_toplevel() {
  local common; common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  ( cd "$(dirname "$common")" && pwd -P )
}
# 目前所在 worktree 自己的根（要動 worktree 裡的檔才用這個）
git_worktree_top() { git rev-parse --show-toplevel 2>/dev/null || true; }
# 共用的 .git 目錄（worktree 時指向主 repo 的 .git）
git_common_dir() { git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true; }
git_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || true; }

# 從 {action}/{slug}/{user} 形式的 branch 名取出 slug；對不到回空字串
slug_from_branch() {
  local b="$1"
  case "$b" in
    */*/*) printf '%s' "$b" | cut -d/ -f2 ;;
    *) printf '' ;;
  esac
}

now_iso() {
  # ISO 8601 含時區，例 2026-11-05T15:03:00+08:00
  local raw; raw="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s:%s\n' "${raw:0:22}" "${raw:22:2}"
}

ensure_dir() { mkdir -p "$1"; }

# 檔案沒有這一行就加（整行比對）
append_line_once() { # <file> <line>
  touch "$1"
  grep -qxF -- "$2" "$1" || printf '%s\n' "$2" >> "$1"
}

# MR 所在的 remote：Acmecorp-AI / Infrastructure 的 origin 是 GitHub 鏡像，有 gitlab 就以它為準（同 init.sh 的 register_source）
primary_remote() { # <git dir>
  if git -C "$1" remote get-url gitlab >/dev/null 2>&1; then printf 'gitlab\n'; else printf 'origin\n'; fi
}

# agent 沒指定 model 時照 kind 給：要想的用 opus，照表操課的用 sonnet。dispatch 和 chain 共用
default_model() { # <agent> <kind>
  if [ "$1" = codex ]; then printf 'gpt-5\n'; return; fi
  case "$2" in dev|refactoring|perf|experiment) printf 'claude-opus-5-5\n' ;; *) printf 'claude-sonnet-5-5\n' ;; esac
}

interactive() { [ -z "${OPSX_NONINTERACTIVE:-}" ] && [ -t 0 ]; }

# 資料夾沒按過 Claude Code 的信任對話框時，專案層 settings 的 allow 與 additionalDirectories 不生效。
# 只警告；信任是使用者在對話框的安全確認，opsx 不替他按。worktree 看主 checkout 的根（傳 repo 的 top）。
warn_untrusted() { # <repo 主 checkout 根>
  local out
  out="$("$OPSX_PY" -I "$OPSX_ROOT/bin/lib/claude-trust.py" "$1")" || die "沒讀到 Claude Code 的信任紀錄（上面是原因）"
  case "$out" in
    untrusted*) warn "$1 還沒信任過 Claude Code：專案層 settings 的 allow 與 additionalDirectories 會被忽略，agent 容易卡在權限。到那個資料夾開一次 claude、在對話框按信任；opsx 不會替你改信任紀錄。opsx 自己的設定寫在使用者層，不受影響" ;;
  esac
}

# 一句話：只准單行、去掉空白後非空（會寫進 inbox.md 的 ## 一句話）
single_line() { # <text>，不合格就 die
  case "$1" in *$'\n'*|*$'\r'*) die "一句話不能有換行" ;; esac
  [ -n "${1//[[:space:]]/}" ] || die "一句話是空的"
}

# repo 根：有 openspec/changes/ 的目錄，印實體路徑
opsx_repo_top() { # <path>
  [ -d "$1/openspec/changes" ] || die "不是 opsx repo（沒有 openspec/changes/）：$1"
  ( cd "$1" && pwd -P )
}

# 分支尾巴的名字：OPSX_USER，沒設就是 git user.name（空白換 -、轉小寫）。沒有名字、或是 git 的占位字「Your Name」時印空行。
branch_user() { # <top>
  local u="${OPSX_USER:-$(git -C "$1" config user.name 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]')}"
  [ "$u" != your-name ] || u=""
  printf '%s\n' "$u"
}

# <slug> 的第 <n> 個候選：n=1 是 slug 本身，之後加 -<n>。
# 總長超過 32 時截中段、保留最後一段（issue 編號）：gh-<repo>-1 撞名要變 gh-<re>-1-2，不能變成 issue #2 的 gh-<repo>-2。
# 沒有 - 或最後一段太長（留不下開頭至少一個字）時，改成截尾再加 -N。
slug_candidate() { # <slug> <n>
  local s="$1" sfx="" head tail keep
  [ "$2" -eq 1 ] || sfx="-$2"
  if [ $(( ${#s} + ${#sfx} )) -le 32 ]; then printf '%s\n' "$s$sfx"; return; fi
  head="${s%-*}"; tail="${s##*-}"; keep=$((32 - ${#tail} - ${#sfx} - 1))
  if [ "$head" != "$s" ] && [ "$keep" -ge 1 ]; then
    head="${head:0:$keep}"; printf '%s\n' "${head%-}-$tail$sfx"
  else
    s="${s:0:$((32 - ${#sfx}))}"; printf '%s\n' "${s%-}$sfx"
  fi
}

# 在 <top> 用 openspec 建殼，inbox.md 寫成 <內容檔>；slug 已被占用就依序加 -2、-3，總長照 slug_candidate 截到 32 字以內。印實際的 slug。
# 占用：殼已在、歸檔過（archive/<日期>-<slug>）、workplan 有同名 feature、PR 或 change、或有 */<slug>/* 或 */<slug> 分支。
# 後三者會讓新卡的 PR 名、branch 名跟舊的撞在一起，卡名就不再等於 PR 名和 branch 名（有 feat/<slug> 時 git 建不出 feat/<slug>/<user>）。
# workplan 讀不了時 names 只警告、不印名字：照樣建殼，只少了 workplan 名字的撞名檢查。
# 建好就掛進 workplan（workplanwrite.py attach），<父卡> 沒給時從卡的 source: agent:<卡> 取。
# 掛不進去只警告、照樣印 slug：卡已經建好，退出非零會讓呼叫端或 agent 再建一張。
# 並行呼叫挑同一個 slug：先 mkdir <top>/openspec/.reserve-<slug>（原子）拿到保留，才建殼；建完或失敗都放掉。
# 不能預先 mkdir changes/<slug>：openspec new change 看到已存在會拒絕。
new_shell() { # <top> <slug> <inbox 內容檔> [<父卡>]
  local top="$1" slug n=1 res err wp refs heads='refs/heads/*'
  wp="$("$OPSX_PY" -I "$(dirname "${BASH_SOURCE[0]}")/workplanwrite.py" names "$top")" || die "讀不到 ${top} 的 workplan（上面是原因）"
  slug="$(slug_candidate "$2" 1)"
  while :; do
    res="$top/openspec/.reserve-$slug"
    if err="$(mkdir "$res" 2>&1)"; then
      refs="$(git -C "$top" for-each-ref --format='%(refname)' "$heads/$slug/*" "$heads/$slug")" || { rmdir "$res"; die "讀不到 ${top} 的分支（上面是原因）"; }
      [ -e "$top/openspec/changes/$slug" ] || [ -n "$refs" ] || [[ $'\n'"$wp"$'\n' == *$'\n'"$slug"$'\n'* ]] \
        || compgen -G "$top/openspec/changes/archive/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-$slug" > /dev/null || break
      rmdir "$res"
    elif [ ! -w "$top/openspec" ]; then
      die "建不了保留目錄 ${res}（${top}/openspec 不可寫）"
    fi
    n=$((n+1))
    [ "$n" -le 1000 ] || die "試了 1000 個 slug 都拿不到保留（最後一個 ${res}）：${err}"
    slug="$(slug_candidate "$2" "$n")"
  done
  ( cd "$top" && openspec new change "$slug" --schema opsx >/dev/null ) || { rmdir "$res"; die "openspec new change $slug 失敗（${top}）"; }
  cp "$3" "$top/openspec/changes/$slug/inbox.md" || { rmdir "$res"; die "寫不進 $top/openspec/changes/$slug/inbox.md"; }
  rmdir "$res"
  "$OPSX_PY" -I "$(dirname "${BASH_SOURCE[0]}")/workplanwrite.py" attach "$top" "$slug" "${4:-}" "$(branch_user "$top")" "" \
    || warn "已建 ${slug}，但沒掛進 workplan（上面是原因）"
  printf '%s\n' "$slug"
}

# 有 common 就有 runtime：bin/opsx 與 hooks 都只 source 這個檔
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"
