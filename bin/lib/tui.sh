#!/usr/bin/env bash

opsx_tui() {
  [ "$#" -eq 0 ] || die "tui: 不接受參數，收到：$*"
  exec bash "$OPSX_ROOT/herdr-board/scripts/open-pane.sh"
}
