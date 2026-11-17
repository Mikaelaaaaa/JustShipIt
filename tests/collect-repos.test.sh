#!/usr/bin/env bash
# opsx collect 的 repo 清單跟 sync 同一份：同名兩個都不收、記 errors；sources.toml 壞了照列 root 的 repo。驗收：specs/board-collect「repo 的來源」
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab gh
export OPSX_FAKE_LOG="$FX/fake.log"; : > "$OPSX_FAKE_LOG"
mkdir -p "$OPSX_STATE_DIR"

scope_repos() { printf '%s' "$1" | python3 -I -c 'import json,sys;print(sorted(r for s in json.load(sys.stdin)["scopes"] for r in s["repos"]))'; }
errors_of() { printf '%s' "$1" | python3 -I -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["errors"],ensure_ascii=False))'; }
mkrepo() { # <dir> <slug>：有 .git 目錄與一張卡的 repo，印實體路徑
  mkdir -p "$1/.git" "$1/openspec/changes/$2"
  printf 'schema: opsx\nkind: dev\n' > "$1/openspec/changes/$2/.openspec.yaml"; printf '## 一句話\n\n%s\n' "$2" > "$1/openspec/changes/$2/inbox.md"
  ( cd "$1" && pwd -P )
}
source_entry() { printf '\n[[source]]\nkind = "gitlab"\nrepo = "%s"\nproject = "g/%s"\npath = "%s"\n' "$1" "$1" "$2"; }

ROOT="$FX/code"
RA="$(mkrepo "$ROOT/a" c1)"; mkrepo "$ROOT/b" c3 >/dev/null
Z="$(mkrepo "$FX/elsewhere/z" z1)"
mkdir -p "$ROOT/a-wt/openspec/changes"; printf 'gitdir: /nowhere\n' > "$ROOT/a-wt/.git"

# --- 登記在 root 之外的 z、指到 root 底下 a 的重複登記、不存在的 path：照舊 ---
{ source_entry z "$Z"; source_entry a "$RA"; source_entry gone "$FX/gone"; } > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "collect: $J"
assert_eq "$(scope_repos "$J")" "['a', 'b', 'z']"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(sum(1 for c in json.load(sys.stdin)["cards"] if c["repo"]=="a"))')" 1 "a 兩邊都有，卡不重複"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["worktrees_skipped"])')" "['a-wt']" "linked worktree 照舊跳過"
assert_eq "$(errors_of "$J")" '[]' "不存在的 path、重複登記都不記 errors"

# --- 登記的 x/a 跟 root 底下的 a 同名：兩個都不收、errors 一筆含兩個路徑與改名，其餘照常 ---
DA="$(mkrepo "$FX/dup/a" c2)"
source_entry dupa "$DA" >> "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "同名時 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['b', 'z']" "同名的 a 兩個都不在 scopes"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print("a" in d["repo_paths"], sorted(c["slug"] for c in d["cards"]))')" "False ['c3', 'z1']" "a 不在 repo_paths，c1、c2 不在 cards"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;e=json.load(sys.stdin)["errors"];print(len(e), all(p in e[0]["message"] for p in sys.argv[1:]))' "$RA" "$DA" "改名")" "1 True" "errors 一筆，含兩個路徑與改名：$(errors_of "$J")"

# --- sources.toml 壞了：記一筆 errors，root 底下的 repo 照列 ---
printf '[[source\n' > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "sources.toml 壞了 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['a', 'b']" "壞掉的 sources.toml 不拖垮 root 的 repo"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print([e["source"].endswith("sources.toml") for e in json.load(sys.stdin)["errors"]])')" "[True]" "sources.toml 壞了要記 errors：$(errors_of "$J")"

echo ok
