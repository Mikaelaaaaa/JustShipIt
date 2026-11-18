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

# --- 大小寫不同的寫法登記 root 底下的 a：同一個目錄，不是同名的兩個 repo（分大小寫的檔案系統上跳過）---
if [ -d "$FX/CODE/a" ]; then
  { source_entry z "$Z"; source_entry a "$FX/CODE/a"; } > "$OPSX_STATE_DIR/sources.toml"
  J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "大小寫不同 collect: $J"
  assert_eq "$(scope_repos "$J")" "['a', 'b', 'z']" "大小寫不同的同一個 a 只算一次"
  assert_eq "$(errors_of "$J")" '[]' "大小寫不同的同一個 a 不是同名衝突"
  { source_entry z "$Z"; source_entry a "$RA"; source_entry gone "$FX/gone"; } > "$OPSX_STATE_DIR/sources.toml"
fi

# --- 登記的 x/a 跟 root 底下的 a 同名：兩個都不收、errors 一筆含兩個路徑與改名，其餘照常 ---
DA="$(mkrepo "$FX/dup/a" c2)"
source_entry dupa "$DA" >> "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "同名時 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['b', 'z']" "同名的 a 兩個都不在 scopes"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print("a" in d["repo_paths"], sorted(c["slug"] for c in d["cards"]))')" "False ['c3', 'z1']" "a 不在 repo_paths，c1、c2 不在 cards"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;e=json.load(sys.stdin)["errors"];print(len(e), all(p in e[0]["message"] for p in sys.argv[1:]))' "$RA" "$DA" "改名")" "1 True" "errors 一筆，含兩個路徑與改名：$(errors_of "$J")"
# 同名被丟掉的 a 上還有活的 session pane：不能算成孤兒，不然 reap 會關掉它
printf '{"a/@f":{"pane":"w1:p7","mode":"autopilot","worktree":"%s/.claude/worktrees/f"}}' "$RA" > "$OPSX_STATE_DIR/dispatch.json"
printf '{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","pane_id":"w1:p7","agent_status":"working","cwd":"%s/.claude/worktrees/f","foreground_cwd":"%s/.claude/worktrees/f","terminal_title_stripped":"t"}],"type":"agent_list"}}' "$RA" "$RA" > "$FX/agents.json"
J="$(HERDR_ENV=1 OPSX_TEST_HERDR_AGENTS="$FX/agents.json" opsx collect --root "$ROOT")"; assert_eq "$?" 0 "同名 session collect: $J"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["orphans"])')" "[]" "同名被丟掉的 repo 的 session pane 不是孤兒"
rm -f "$OPSX_STATE_DIR/dispatch.json"

# --- sources.toml 壞了：記一筆 errors，root 底下的 repo 照列 ---
printf '[[source\n' > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "sources.toml 壞了 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['a', 'b']" "壞掉的 sources.toml 不拖垮 root 的 repo"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;print([e["source"].endswith("sources.toml") for e in json.load(sys.stdin)["errors"]])')" "[True]" "sources.toml 壞了要記 errors：$(errors_of "$J")"

# --- sources.toml 是合法 TOML 但形狀不對：跟寫壞一樣，記一筆 errors 指出那個值，root 底下的 repo 照列 ---
src_errors() { printf '%s' "$1" | python3 -I -c 'import json,sys;e=json.load(sys.stdin)["errors"];print(len(e), e[0]["source"].endswith("sources.toml"), sys.argv[1] in e[0]["message"])' "$2"; }
printf '[[source]]\nkind = "gitlab"\npath = 1\n' > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "path = 1 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['a', 'b']" "path = 1 不拖垮 root 的 repo"
assert_eq "$(src_errors "$J" path)" "1 True True" "path = 1 記一筆、指出 path：$(errors_of "$J")"
printf '[source]\npath = "%s"\n' "$Z" > "$OPSX_STATE_DIR/sources.toml"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "[source] 單表 collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['a', 'b']" "[source] 單表不拖垮 root 的 repo"
assert_eq "$(src_errors "$J" source)" "1 True True" "[source] 單表記一筆、指出 source：$(errors_of "$J")"

# --- root 底下有 openspec/changes 但沒有 .git：不收，記一筆 errors 說它沒有 .git ---
: > "$OPSX_STATE_DIR/sources.toml"
mkdir -p "$ROOT/n/openspec/changes/n1"; NP="$(cd "$ROOT/n" && pwd -P)"
J="$(opsx collect --root "$ROOT")"; assert_eq "$?" 0 "沒有 .git collect 照常：$J"
assert_eq "$(scope_repos "$J")" "['a', 'b']" "沒有 .git 的 n 不收"
assert_eq "$(printf '%s' "$J" | python3 -I -c 'import json,sys;e=json.load(sys.stdin)["errors"];print(len(e), sys.argv[1] in e[0]["message"], "沒有 .git" in e[0]["message"])' "$NP")" "1 True True" "沒有 .git 記一筆、含路徑：$(errors_of "$J")"
rm -rf "$ROOT/n"

echo ok
