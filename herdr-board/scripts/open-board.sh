#!/usr/bin/env bash
# herdr action open-board：起看板 server（已在跑就不重起）+ 開瀏覽器帶 token。herdr-board 5.1、specs/board-plugin。
#   server：python3 herdr-board/server.py --port ${OPSX_BOARD_PORT}（預設 8791），pid 在 $OPSX_STATE_DIR/board-<port>.pid（每個 port 一份），log 在 board.log
#   token：server 第一次啟動寫 $OPSX_STATE_DIR/board-token；拼進 URL，頁面讀一次存 sessionStorage 後抹掉
#   用法：open-board.sh [<repo>/<slug>]，給了就在同一個 fragment 加 card=，網頁開頁後展開那張卡
#   瀏覽器：預設 open / xdg-open；OPSX_BOARD_BROWSER=orca 才開 Orca 內建瀏覽器分頁
set -euo pipefail
card="${1:-}"
# 參數錯不起 server，所以先驗
# slug 照 collect 列出的目錄名收，不套 herdr agent 名的 32 字上限；兩段都會經 quote 編碼
if [ -n "$card" ] && ! [[ "$card" =~ ^[^/]+/[^/]+$ ]]; then
  echo "opsx board: 參數要是 <repo>/<slug>，收到 [$card]" >&2; exit 1
fi
browser="${OPSX_BOARD_BROWSER:-}"
if [ -n "$browser" ] && [ "$browser" != orca ]; then
  echo "opsx board: OPSX_BOARD_BROWSER 只收 orca 或不設，收到 [$browser]" >&2; exit 1
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
state="${OPSX_STATE_DIR:-$HOME/.local/state/opsx}"
port="${OPSX_BOARD_PORT:-8791}"
url="http://127.0.0.1:${port}/"
mkdir -p "$state"
pidfile="$state/board-${port}.pid"; logfile="$state/board.log"

health() { # healthz 回 app opsx-board 時印它的 pid，沒回 pid 的舊版印 legacy；沒回應或不是 opsx-board 什麼都不印
  python3 -I -c '
import json, sys, urllib.request
try:
    with urllib.request.urlopen(sys.argv[1], timeout=1) as r:
        d = json.load(r)
except (OSError, ValueError):
    sys.exit(0)
if isinstance(d, dict) and d.get("app") == "opsx-board":
    print(d["pid"] if isinstance(d.get("pid"), int) else "legacy")
' "${url}healthz"
}

fail_log() { # fail_log <訊息>：起 server 這段的失敗都退出 1，附 board.log 尾巴
  echo "opsx board: $1，看 ${logfile}" >&2; tail -n 20 "$logfile" >&2 || true; exit 1
}

alive() { # 回 healthz 的是 pidfile 那支、token 檔還在（token 被刪就重起，不然新 tab 永遠 401）
  local pid; pid="$(cat "$pidfile" 2>/dev/null || true)"
  [ -n "$pid" ] && [ -s "$state/board-token" ] && [ "$(health)" = "$pid" ]
}

# 兩個 workspace 同時按 open-board：只有一個能進啟動段（mkdir 是原子的）；另一個等它起好
lock="$state/board.lock"
for _ in $(seq 1 100); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
trap 'rmdir "$lock" 2>/dev/null' EXIT
if ! alive; then
  pid="$(cat "$pidfile" 2>/dev/null || true)"; [ -n "$pid" ] && kill "$pid" 2>/dev/null || true   # token 不見或 healthz 不對：重起
  rm -f "$pidfile"
  # port 上還有別支 opsx server（pidfile 沒記到，或剛 kill 還沒退）：停掉它，新 server 才綁得到 port、token 也跟檔案一致
  other="$(health)"
  if [ "$other" = legacy ]; then
    echo "opsx board: port ${port} 上是不回 pid 的舊版 opsx server，先停掉它：kill \$(lsof -tiTCP:${port} -sTCP:LISTEN)，再開一次" >&2; exit 1
  fi
  [ -z "$other" ] || kill "$other" || fail_log "停不掉 port ${port} 上的 opsx server（pid ${other}）"
  for _ in $(seq 1 50); do [ -z "$(health)" ] && break; sleep 0.1; done
  [ -z "$(health)" ] || fail_log "port ${port} 上的 opsx server 5 秒內沒停"
  ( trap '' HUP; exec python3 -I "$root/herdr-board/server.py" --port "$port" --state "$state" ) </dev/null >>"$logfile" 2>&1 &
  new=$!
  printf '%s\n' "$new" > "$pidfile"
  for _ in $(seq 1 50); do
    [ "$(health)" = "$new" ] && break
    kill -0 "$new" 2>/dev/null || { rm -f "$pidfile"; fail_log "server 起不來"; }
    sleep 0.1
  done
  [ "$(health)" = "$new" ] || fail_log "server 10 秒內沒回應"
fi

token="$(cat "$state/board-token" 2>/dev/null || true)"
frag=()   # fragment 不進 server log、不進 Referer
[ -n "$token" ] && frag+=("token=${token}")
[ -n "$card" ] && frag+=("card=$(python3 -I -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$card")")
open_url="$url"; [ ${#frag[@]} -gt 0 ] && open_url="${url}#$(IFS='&'; printf '%s' "${frag[*]}")"

orca_fail() { # orca_fail <步驟> <orca stdout>：不退回系統瀏覽器，免得看板開在使用者沒在看的地方
  echo "opsx board: orca $1 失敗，沒有改用系統瀏覽器" >&2
  [ -n "$2" ] && printf '%s\n' "$2" >&2
  cat "$orca_err" >&2; rm -f "$orca_err"; exit 1
}
# 預設系統瀏覽器：herdr server 的環境可能帶著過期的 ORCA_TERMINAL_HANDLE，不能拿它判斷使用者在不在 Orca。
# tab create 不收 --focus，要拿 browserPageId 再 tab switch
if [ "$browser" = orca ]; then
  orca_err="$(mktemp "${TMPDIR:-/tmp}/opsx-orca-tab.XXXXXX")"
  # Orca 的 Electron 殼成功時也在 stderr 印 codesign 雜訊，JSON 只從 stdout 讀
  created="$(orca tab create --url "$open_url" --json 2>"$orca_err")" || orca_fail "tab create" "$created"
  page="$(python3 -I -c '
import json, sys
raw = sys.argv[1]
try:
    d = json.loads(raw)
except json.JSONDecodeError:
    sys.exit("orca tab create 的輸出不是 JSON，拿不到 result.browserPageId")
result = d["result"] if isinstance(d, dict) and "result" in d else None
if not isinstance(result, dict) or "browserPageId" not in result:
    sys.exit("orca tab create 回的 JSON 沒有 result.browserPageId")
page = result["browserPageId"]
if not isinstance(page, str) or not page:
    sys.exit(f"orca tab create 回的 result.browserPageId 不是非空字串：{page!r}")
print(page)
' "$created")" || orca_fail "tab create" "$created"
  switched="$(orca tab switch --page "$page" --focus 2>"$orca_err")" || orca_fail "tab switch" "$switched"
  rm -f "$orca_err"
elif command -v open >/dev/null 2>&1; then open "$open_url"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$open_url"
else echo "opsx board: 沒有 open 或 xdg-open，自己開 $open_url" >&2; exit 1; fi
echo "opsx 看板：${url}（server pid $(cat "$pidfile")，log ${logfile}）"
