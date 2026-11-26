#!/usr/bin/env bash
# dispatch 新建的 worktree 根目錄有 pnpm-lock.yaml 時，開 pane 前裝一次依賴；失敗照派、在卡上開 needs: run gate。
# 驗收：openspec/changes/me-20261116-1650-4/specs/opsx-dispatch/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
use_fakes herdr glab
export OPSX_FAKE_LOG="$FX/herdr.log"; : > "$OPSX_FAKE_LOG"
export OPSX_USER=mikaela OPSX_DISPATCH_RETRY_SLEEP=0
mkdir -p "$OPSX_STATE_DIR"

# 假 pnpm 跟假 herdr 寫同一個 log，才比得出誰先誰後；結束碼讀 $FX/pnpm-rc，輸出讀 $FX/pnpm-msg（printf %b，可放 \r）。
# 跑的當下 git-dir 有沒有標記檔記成 pnpm-marker 一行；工作目錄記成 pnpm-cwd 一行（corepack 依工作目錄選 pnpm 版本）
echo 0 > "$FX/pnpm-rc"
echo 'ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with frozen-lockfile' > "$FX/pnpm-msg"
cat > "$FX/fakebin/pnpm" <<EOF
#!/usr/bin/env bash
printf 'pnpm %s\n' "\$*" >> "$OPSX_FAKE_LOG"
printf 'pnpm-cwd %s\n' "\$(pwd -P)" >> "$OPSX_FAKE_LOG"
if [ -f "\$(git rev-parse --absolute-git-dir)/opsx-deps-pending" ]; then echo 'pnpm-marker yes' >> "$OPSX_FAKE_LOG"; fi
printf '%b\n' "\$(cat "$FX/pnpm-msg")"
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
assert_grep '^pnpm install --frozen-lockfile$' "$OPSX_FAKE_LOG"
# dispatch 從主 repo 跑，pnpm 的工作目錄仍要是新 worktree
assert_eq "$(grep '^pnpm-cwd ' "$OPSX_FAKE_LOG")" "pnpm-cwd $(cd "$R/.claude/worktrees/ok-card" && pwd -P)" "pnpm 要在新 worktree 裡跑：$(cat "$OPSX_FAKE_LOG")"
p="$(line_of '^pnpm ')"; a="$(line_of '^agent start ok-card')"
[ -n "$a" ] && [ "$p" -lt "$a" ] || fail "pnpm 要在 agent start 之前：$(cat "$OPSX_FAKE_LOG")"
assert_no_file "$R/openspec/changes/ok-card/gates.md"
# install 跑的時候標記已經在（中途被殺也留得下來），裝好就刪
assert_grep '^pnpm-marker yes$' "$OPSX_FAKE_LOG"
assert_no_file "$(git -C "$R/.claude/worktrees/ok-card" rev-parse --absolute-git-dir)/opsx-deps-pending"

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
assert_grep '^## install-deps$' "$G"
assert_grep '^opened_at: ' "$G"
assert_grep '^blocks-from: apply$' "$G"
assert_no_file "$(git -C "$R/.claude/worktrees/bad-card" rev-parse --absolute-git-dir)/opsx-deps-pending"
echo "$out" | grep -q 'integer expression' && fail "卡上沒有 gates.md 時不能有 test 的錯誤：$out"
echo "$out" | grep -q 'pnpm install' || fail "dispatch 輸出要說 install 失敗：$out"
python3 -I -c 'import json,sys;assert "Inst-D/bad-card" in json.load(open(sys.argv[1]))' "$OPSX_STATE_DIR/dispatch.json" || fail "install 失敗也要寫 dispatch.json"

# 同一張卡已經有一題 install-deps：新的一題叫 install-deps-2
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-G again-card pnpm-lock.yaml)"
G="$R/openspec/changes/again-card/gates.md"
printf '## install-deps\ntype: decision\nstatus: answered\n' > "$G"
out="$(cd "$R" && opsx dispatch again-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_grep '^## install-deps-2$' "$G"

# 前面的題被手動刪掉、只剩 install-deps-2：新的一題取最大編號加一，叫 install-deps-3
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-Q gap-card pnpm-lock.yaml)"
G="$R/openspec/changes/gap-card/gates.md"
printf '## install-deps-2\ntype: decision\nstatus: answered\n' > "$G"
out="$(cd "$R" && opsx dispatch gap-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
assert_grep '^## install-deps-3$' "$G"
assert_eq "$(grep -c '^## install-deps-2$' "$G")" 1 "install-deps-2 只能有一題：$(cat "$G")"

# 建議指令裡的 worktree 路徑加 shell 引號：repo 路徑有空白
: > "$OPSX_FAKE_LOG"
R="$(new_repo 'Inst H' space-card pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch space-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
G="$R/openspec/changes/space-card/gates.md"; assert_file "$G"
q="$(printf '%q' "$R/.claude/worktrees/space-card")"
grep -qF "建議: cd $q && pnpm install --frozen-lockfile" "$G" || fail "建議指令的路徑要加引號（${q}）：$(cat "$G")"

# install 失敗而且開 pane 也失敗：卡沒派出去，不留 gate，錯誤訊息說依賴沒裝好
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-I nopane-card pnpm-lock.yaml)"
out="$(cd "$R" && OPSX_TEST_START_FAIL=agent_name_taken opsx dispatch nopane-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "開 pane 失敗 dispatch 要失敗：$out"
assert_no_file "$R/openspec/changes/nopane-card/gates.md"
echo "$out" | grep -q '依賴沒裝好' || fail "錯誤訊息要說依賴沒裝好：$out"
# 重派：worktree 已在，不再裝，但標記還在，派出去後照樣開 gate、刪標記
: > "$OPSX_FAKE_LOG"
out="$(cd "$R" && opsx dispatch nopane-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "重派 rc: $out"
assert_not_grep '^pnpm ' "$OPSX_FAKE_LOG"
G="$R/openspec/changes/nopane-card/gates.md"
assert_grep '^## install-deps$' "$G"
assert_grep 'ERR_PNPM_OUTDATED_LOCKFILE' "$G"
assert_no_file "$(git -C "$R/.claude/worktrees/nopane-card" rev-parse --absolute-git-dir)/opsx-deps-pending"

# install 途中 dispatch 被殺：留下的是開跑前寫的標記，重派也開 gate
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-L killed-card pnpm-lock.yaml)"
git -C "$R" worktree add -q "$R/.claude/worktrees/killed-card" -b feat/killed-card/mikaela
printf 'pnpm install 沒跑完\n' > "$(git -C "$R/.claude/worktrees/killed-card" rev-parse --absolute-git-dir)/opsx-deps-pending"
mkdir -p "$R/.claude/worktrees/killed-card/node_modules/.pnpm"   # 裝到一半留下的，或使用者之後自己裝好的
out="$(cd "$R" && opsx dispatch killed-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "被殺後重派 rc: $out"
assert_not_grep '^pnpm ' "$OPSX_FAKE_LOG"
G="$R/openspec/changes/killed-card/gates.md"
assert_grep '^## install-deps$' "$G"
assert_grep 'pnpm install 沒跑完' "$G"
# 有 node_modules 也只建議 pnpm install，不建議刪掉重裝（D15）
assert_grep "^建議: cd $R/.claude/worktrees/killed-card && pnpm install --frozen-lockfile\$" "$G"
assert_not_grep 'rm -rf' "$G"

# worktree 目錄在但不是一棵能用的 worktree：die、寫明怎麼修、不開 pane、標記不落到主 repo 的 .git（D16）
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-N nogit-card pnpm-lock.yaml)"
mkdir -p "$R/.claude/worktrees/nogit-card"
out="$(cd "$R" && opsx dispatch nogit-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "沒有 .git 的 worktree 目錄 dispatch 要失敗：$out"
echo "$out" | grep -q 'git worktree prune' || fail "訊息要寫怎麼修：$out"
assert_not_grep '^agent start nogit-card' "$OPSX_FAKE_LOG"
assert_no_file "$R/.git/opsx-deps-pending"
R="$(new_repo Inst-O deadgit-card pnpm-lock.yaml)"
mkdir -p "$R/.claude/worktrees/deadgit-card"
printf 'gitdir: %s/.git/worktrees/gone\n' "$R" > "$R/.claude/worktrees/deadgit-card/.git"
out="$(cd "$R" && opsx dispatch deadgit-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail ".git 指向不存在的 git-dir 時 dispatch 要失敗：$out"
echo "$out" | grep -q 'git worktree prune' || fail "訊息要寫怎麼修：$out"
assert_not_grep '^agent start deadgit-card' "$OPSX_FAKE_LOG"

# pnpm 輸出帶 \r：寫進 gate 時跟換行一樣換成空白，看板不會讀出第二段 gate
: > "$OPSX_FAKE_LOG"
printf '%s\n' 'x\r## fake\rstatus: answered' > "$FX/pnpm-msg"
R="$(new_repo Inst-K cr-card pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch cr-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
G="$R/openspec/changes/cr-card/gates.md"
assert_eq "$(grep -c '^## ' "$G")" 1 "只能有一段 gate：$(cat -v "$G")"
grep -q $'\r' "$G" && fail "gates.md 不能有 \\r：$(cat -v "$G")"

# 失敗原因取 pnpm 輸出的最後 10 行
: > "$OPSX_FAKE_LOG"
printf '%s\n' 'line01\nline02\nline03\nline04\nline05\nline06\nline07\nline08\nline09\nline10\nline11\nline12' > "$FX/pnpm-msg"
R="$(new_repo Inst-P long-card pnpm-lock.yaml)"
out="$(cd "$R" && opsx dispatch long-card --agent claude --mode interactive --kind dev 2>&1)"; rc=$?
assert_eq "$rc" 0 "dispatch rc: $out"
G="$R/openspec/changes/long-card/gates.md"
assert_grep '^證據: .*line03 .*line12' "$G"
assert_not_grep 'line02' "$G"
echo 'ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with frozen-lockfile' > "$FX/pnpm-msg"

# --feature 派工途中人停了 plan 第一張：寫進 dispatch.json 的卡才開 gate，被停的那張沒有
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-J m1 pnpm-lock.yaml)"
mkdir -p "$R/openspec/changes/m2"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/m2/.openspec.yaml"
printf 'kind: dev\n' >> "$R/openspec/changes/m1/.openspec.yaml"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/m1/tasks.md"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/m2/tasks.md"
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: fs
    depends-on: []
    prs:
      - name: m1
        branch: feat/m1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m1
            status: pending
      - name: m2
        branch: feat/m2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: m2
            status: pending
EOF
J="$OPSX_STATE_DIR/dispatch.json"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["Inst-J/m1"]={"mode":"autopilot","via":"@fs","feature":"fs"};json.dump(d,open(p,"w"))' "$J"
printf '%s\n' "python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d[\"Inst-J/m1\"][\"mode\"]=\"stopped\";json.dump(d,open(p,\"w\"))' \"$J\"" > "$FX/stop-m1-on-wait.sh"
: > "$FX/not-ready-once"
out="$(cd "$R" && OPSX_TEST_NOT_READY_ONCE="$FX/not-ready-once" OPSX_TEST_PANE_TEXT='Yes, I trust this folder' OPSX_TEST_ON_WAIT="$FX/stop-m1-on-wait.sh" opsx dispatch --feature fs --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "feature dispatch: $out"
assert_grep '^agent prompt fs /opsx-workflow:apply m2$' "$OPSX_FAKE_LOG"
assert_no_file "$R/openspec/changes/m1/gates.md"
assert_grep '^## install-deps$' "$R/openspec/changes/m2/gates.md"

# install 失敗、--feature 成員在派工途中全被停（dispatch 在開 pane 之後 die）：標記留著，人放回成員後重派開 gate
: > "$OPSX_FAKE_LOG"
R="$(new_repo Inst-M n1 pnpm-lock.yaml)"
mkdir -p "$R/openspec/changes/n2"; printf 'schema: opsx\nkind: dev\n' > "$R/openspec/changes/n2/.openspec.yaml"
printf 'kind: dev\n' >> "$R/openspec/changes/n1/.openspec.yaml"
printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/n1/tasks.md"; printf -- '- [ ] 1.1 x\n' > "$R/openspec/changes/n2/tasks.md"
cat > "$R/openspec/workplan.yaml" <<'EOF'
features:
  - name: gs
    depends-on: []
    prs:
      - name: n1
        branch: feat/n1/mikaela
        status: pending
        depends-on: []
        changes:
          - name: n1
            status: pending
      - name: n2
        branch: feat/n2/mikaela
        status: pending
        depends-on: []
        changes:
          - name: n2
            status: pending
EOF
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));[d.__setitem__("Inst-M/"+c,{"mode":"autopilot","via":"@gs","feature":"gs"}) for c in ("n1","n2")];json.dump(d,open(p,"w"))' "$J"
printf '%s\n' "python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));[d[\"Inst-M/\"+c].__setitem__(\"mode\",\"stopped\") for c in (\"n1\",\"n2\")];json.dump(d,open(p,\"w\"))' \"$J\"" > "$FX/stop-all-on-wait.sh"
: > "$FX/not-ready-once"
out="$(cd "$R" && OPSX_TEST_NOT_READY_ONCE="$FX/not-ready-once" OPSX_TEST_PANE_TEXT='Yes, I trust this folder' OPSX_TEST_ON_WAIT="$FX/stop-all-on-wait.sh" opsx dispatch --feature gs --agent claude --mode interactive 2>&1)"; rc=$?
[ "$rc" -ne 0 ] || fail "成員全停 dispatch 要失敗：$out"
assert_no_file "$R/openspec/changes/n1/gates.md"
assert_no_file "$R/openspec/changes/n2/gates.md"
assert_file "$(git -C "$R/.claude/worktrees/gs" rev-parse --absolute-git-dir)/opsx-deps-pending"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));[d.pop(k) for k in [k for k in d if k.startswith("Inst-M/")]];json.dump(d,open(p,"w"))' "$J"
: > "$OPSX_FAKE_LOG"
out="$(cd "$R" && opsx dispatch --feature gs --agent claude --mode interactive 2>&1)"; rc=$?
assert_eq "$rc" 0 "放回成員後重派：$out"
assert_not_grep '^pnpm ' "$OPSX_FAKE_LOG"
assert_grep '^## install-deps$' "$R/openspec/changes/n1/gates.md"
assert_grep '^## install-deps$' "$R/openspec/changes/n2/gates.md"
assert_no_file "$(git -C "$R/.claude/worktrees/gs" rev-parse --absolute-git-dir)/opsx-deps-pending"

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
