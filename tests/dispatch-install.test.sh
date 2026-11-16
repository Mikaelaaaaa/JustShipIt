#!/usr/bin/env bash
# dispatch 新建的 worktree 根目錄有 pnpm-lock.yaml 時，開 pane 前裝一次依賴；失敗照派、在卡上開 needs: run gate。
# 驗收：openspec/changes/me-20261116-1650-4/specs/opsx-dispatch/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela OPSX_DISPATCH_RETRY_SLEEP=0
mkdir -p "$OPSX_STATE_DIR"

# 假 pnpm 跟假 herdr 寫同一個 log，才比得出誰先誰後；結束碼讀 $FX/pnpm-rc
echo 0 > "$FX/pnpm-rc"
cat > "$FX/fakebin/pnpm" <<EOF
#!/usr/bin/env bash
printf 'pnpm %s\n' "\$*" >> "$OPSX_FAKE_LOG"
echo "ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with frozen-lockfile"
exit "\$(cat "$FX/pnpm-rc")"
EOF
chmod +x "$FX/fakebin/pnpm"

new_repo() { # <repo name> <card> <lockfile path relative to repo root, or empty>
  local r; r="$(mk_repo "$1" "git@gitlab.example.com:acmecorp/$1.git")"
  mkdir -p "$r/openspec/changes/$2"
  printf 'schema: opsx\n' > "$r/openspec/changes/$2/.openspec.yaml"
  printf '"%s" = "acmecorp-ai"\n' "$1" >> "$OPSX_STATE_DIR/workspaces.toml"
  if [ -n "$3" ]; then
    mkdir -p "$(dirname "$r/$3")"; echo "lockfileVersion: '9.0'" > "$r/$3"
    git -C "$r" add "$3"; git -C "$r" commit -q -m lock
  fi
  printf '%s' "$r"
}
line_of() { grep -n -- "$1" "$OPSX_FAKE_LOG" | head -1 | cut -d: -f1; }
printf '[repos]\n' > "$OPSX_STATE_DIR/workspaces.toml"

# 新 worktree 有 pnpm-lock.yaml 就裝完才開 pane
R="$(new_repo Inst-A ok-card pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch ok-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_eq "$(grep -c '^pnpm ' "$OPSX_FAKE_LOG")" 1 "pnpm 要剛好叫一次：$(cat "$OPSX_FAKE_LOG")"
assert_grep "^pnpm --dir $R/.claude/worktrees/ok-card install --frozen-lockfile\$" "$OPSX_FAKE_LOG"
p="$(line_of '^pnpm ')"; a="$(line_of '^agent start ok-card')"
[ -n "$a" ] && [ "$p" -lt "$a" ] || fail "pnpm 要在 agent start 之前：$(cat "$OPSX_FAKE_LOG")"
assert_no_file "$R/openspec/changes/ok-card/gates.md"

# 既有 worktree 不裝
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-B old-card pnpm-lock.yaml)"
git -C "$R" worktree add -q "$R/.claude/worktrees/old-card" -b feat/old-card/mikaela
out="$(cd "$R" && opsx dispatch old-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_not_grep '^pnpm ' "$OPSX_FAKE_LOG"

# 根目錄沒有 pnpm-lock.yaml（只有子目錄有）不裝
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-C sub-card frontend/pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch sub-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_not_grep '^pnpm ' "$OPSX_FAKE_LOG"

# install 失敗照樣派、開 needs: run gate：pnpm 結束碼 1
: > "$OPSX_FAKE_LOG"; echo 1 > "$FX/pnpm-rc"
R="$(new_repo Inst-D bad-card pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch bad-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "install 失敗 dispatch 也要成功：$out"
assert_grep '^agent start bad-card' "$OPSX_FAKE_LOG"
assert_grep '^agent prompt bad-card ' "$OPSX_FAKE_LOG"
G="$R/openspec/changes/bad-card/gates.md"; assert_file "$G"
assert_grep '^status: open$' "$G"
assert_grep '^type: decision$' "$G"
assert_grep '^needs: run$' "$G"
assert_grep "pnpm install --frozen-lockfile" "$G"
assert_grep "$R/.claude/worktrees/bad-card" "$G"
assert_grep 'ERR_PNPM_OUTDATED_LOCKFILE' "$G"
echo "$out" | grep -q 'pnpm install' || fail "dispatch 輸出要說 install 失敗：$out"
python3 -I -c 'import json,sys;assert "Inst-D/bad-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json" || fail "install 失敗也要寫 dispatch.json"

# install 失敗照樣派、開 needs: run gate：PATH 上找不到 pnpm
: > "$OPSX_FAKE_LOG"; rm "$FX/fakebin/pnpm"
mkdir -p "$FX/tools"; ln -s "$(command -v jq)" "$FX/tools/jq"; ln -s "$(command -v git)" "$FX/tools/git"
NOPNPM="$FX/tools"
IFS=: read -ra dirs <<< "$PATH"
for dir in "${dirs[@]}"; do [ -x "$dir/pnpm" ] || NOPNPM="$NOPNPM:$dir"; done
R="$(new_repo Inst-E nopnpm-card pnpm-lock.yaml)"
out="$(cd "$R" && PATH="$NOPNPM" opsx dispatch nopnpm-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "找不到 pnpm dispatch 也要成功：$out"
assert_grep '^agent start nopnpm-card' "$OPSX_FAKE_LOG"
G="$R/openspec/changes/nopnpm-card/gates.md"; assert_file "$G"
assert_grep '^needs: run$' "$G"
assert_grep '找不到 pnpm' "$G"

echo "dispatch-install ok"
