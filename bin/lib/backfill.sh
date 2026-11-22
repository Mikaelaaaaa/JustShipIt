#!/usr/bin/env bash
# opsx backfill [--repo <top>] [--write]：各 repo 不在 workplan 的卡補掛進 workplan，歸屬規則跟建卡時一樣（workplanwrite.placement）。
# 不帶 --write 只印預覽，每張一行 <repo>\t<卡>\t<動作>\t<原因>；帶 --write 照同樣的動作寫入。不給 --repo 掃已登記的全部 repo。
# 有卡寫不進去時照樣處理其他卡，最後 stderr 列出、退出 1。specs/workplan-backfill。

opsx_backfill() {
  local top="" write=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || die "backfill: --repo 後面要給 repo 路徑"; top="$(opsx_repo_top "$2")"; shift 2 ;;
      --write) write=1; shift ;;
      *) die "backfill: 不認得的參數：$1" ;;
    esac
  done
  "$OPSX_PY" -I "$OPSX_ROOT/bin/lib/backfill.py" "${OPSX_CODE_ROOT:-$HOME/code}" "$OPSX_STATE_DIR" "$write" "$top"
}
