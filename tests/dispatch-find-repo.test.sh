#!/usr/bin/env bash
# opsx dispatch 沒給 --repo 時在已登記 repo 找卡（specs/opsx-dispatch「沒給 --repo 時在已登記 repo 找卡」「找不到唯一的 repo 就不派」）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela

# 已登記 repo：OPSX_CODE_ROOT 底下兩個，加上 sources.toml 登記、不在 root 底下的一個
A="$(mk_repo code/Acmecorp-AI)"
C="$(mk_repo code/Acmecorp-CS)"
S="$(mk_repo extra/Acmecorp-Ext)"
P="$FX/plain"; mkdir -p "$P"
printf '[[source]]\nkind = "gitlab"\nrepo = "Acmecorp-Ext"\nproject = "g/ext"\npath = "%s"\n' "$S" > "$OPSX_STATE_DIR/sources.toml"
printf '[repos]\n"Acmecorp-AI" = "acmecorp-ai"\n"Acmecorp-CS" = "acmecorp-ai"\n"Acmecorp-Ext" = "acmecorp-ai"\n' > "$OPSX_STATE_DIR/workspaces.toml"
mkdir -p "$A/openspec/changes" "$C/openspec/changes" "$S/openspec/changes"

card() { # card <repo-dir> <slug>
  mkdir -p "$1/openspec/changes/$2"
  printf 'schema: opsx\ncreated: 2026-11-17\n' > "$1/openspec/changes/$2/.openspec.yaml"
  printf '## 已知\n- x\n\n## 待決\n\n## 不做\n' > "$1/openspec/changes/$2/explore.md"
}
key() { jq -r --arg k "$1" 'has($k)' "$OPSX_STATE_DIR/dispatch.json" 2>/dev/null || echo false; }
dispatch_ok() { # dispatch_ok <cwd> <slug> [args…]：rc 0，回傳 stdout
  local cwd="$1"; shift
  local out; out="$(cd "$cwd" && opsx dispatch "$@" --agent claude --mode interactive --kind dev 2>"$FX/err")" || fail "dispatch $* 從 $cwd 應該成功：$out $(cat "$FX/err")"
  printf '%s' "$out"
}
dispatch_refused() { # dispatch_refused <cwd> <slug> [args…]：rc 非 0，herdr 沒被叫，stderr 留在 $FX/err
  local cwd="$1"; shift
  : > "$OPSX_FAKE_LOG"
  if (cd "$cwd" && opsx dispatch "$@" --agent claude --mode interactive --kind dev >"$FX/out" 2>"$FX/err"); then fail "dispatch $* 從 $cwd 應該被拒：$(cat "$FX/out")"; fi
  assert_eq "$(cat "$OPSX_FAKE_LOG")" "" "被拒的派工不該碰 herdr"
}

# --- 卡在已登記 repo 裡，cwd 的位置不同：一般場景，cwd 是另一個 repo ---
card "$A" card-a
out="$(dispatch_ok "$C" card-a)"
case "$out" in *"卡在 $A"*) ;; *) fail "stdout 要說卡在 ${A}：$out" ;; esac
assert_dir "$A/.claude/worktrees/card-a"
assert_no_file "$C/.claude/worktrees/card-a"
assert_eq "$(key Acmecorp-AI/card-a)" true "dispatch.json 要用卡所在 repo 的 key"
assert_eq "$(key Acmecorp-CS/card-a)" false "不該寫 cwd repo 的 key"

# --- 邊界：cwd 不是 git repo ---
card "$A" card-a2
out="$(dispatch_ok "$P" card-a2)"
case "$out" in *"卡在 $A"*) ;; *) fail "stdout 要說卡在 ${A}：$out" ;; esac
assert_dir "$A/.claude/worktrees/card-a2"
assert_eq "$(key Acmecorp-AI/card-a2)" true

# --- 邊界：卡在 sources.toml 登記、不在 OPSX_CODE_ROOT 底下的 repo ---
card "$S" card-g
out="$(dispatch_ok "$C" card-g)"
case "$out" in *"卡在 $S"*) ;; *) fail "stdout 要說卡在 ${S}：$out" ;; esac
assert_dir "$S/.claude/worktrees/card-g"
assert_eq "$(key Acmecorp-Ext/card-g)" true

# --- cwd 的 repo 有卡就用 cwd 的 repo ---
card "$A" card-b; card "$C" card-b
dispatch_ok "$C" card-b >/dev/null
assert_eq "$(key Acmecorp-CS/card-b)" true
assert_eq "$(key Acmecorp-AI/card-b)" false
assert_no_file "$A/.claude/worktrees/card-b"

# --- 已歸檔的同名卡不算 ---
mkdir -p "$A/openspec/changes/archive/2026-11-01-card-c"
printf 'schema: opsx\n' > "$A/openspec/changes/archive/2026-11-01-card-c/.openspec.yaml"
dispatch_refused "$C" card-c
assert_grep '沒有這張卡' "$FX/err"

# --- 兩個已登記 repo 都有這張卡 ---
card "$A" card-d; card "$C" card-d
dispatch_refused "$P" card-d
assert_grep "$A" "$FX/err"
assert_grep "$C" "$FX/err"
assert_grep '--repo' "$FX/err"
assert_eq "$(key Acmecorp-AI/card-d)" false
assert_eq "$(key Acmecorp-CS/card-d)" false
assert_no_file "$A/.claude/worktrees/card-d"

# --- 哪個 repo 都沒有這張卡 ---
dispatch_refused "$P" card-none
assert_grep '沒有這張卡' "$FX/err"

# --- 給了 --repo 就不去別的 repo 找 ---
card "$A" card-e
dispatch_refused "$P" card-e --repo "$C"
assert_grep '沒有這張卡' "$FX/err"
assert_eq "$(key Acmecorp-AI/card-e)" false

# --- 給了 --repo 且那個 repo 有卡 ---
card "$A" card-f; card "$C" card-f
dispatch_ok "$P" card-f --repo "$A" >/dev/null
assert_eq "$(key Acmecorp-AI/card-f)" true
assert_eq "$(key Acmecorp-CS/card-f)" false

echo ok
