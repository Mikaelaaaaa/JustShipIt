#!/usr/bin/env bash
# 複合指令逐段判斷：有一段有授權不能替整串放行；每一段都要有授權、或在 dispatch 給這個 agent 的 settings allow 裡。
# 驗收：openspec/changes/me-20261111-1824/specs/grant-gate-segments/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/grant-gate-fixture.sh"

# 有授權的段（repo 永遠 push）帶出 settings allow 外的段：deny，點名那一段
out="$(gg 'git -C . merge origin/main && git push')"; assert_eq "$(decision "$out")" deny "settings allow 外的段不能跟著放行: $(reason "$out")"
reason "$out" | grep -qF 'git -C . merge origin/main' || fail "deny 要點名沒涵蓋的那一段: $(reason "$out")"
out="$(gg 'git push; git -c core.x=y merge origin/main')"; assert_eq "$(decision "$out")" deny "順序反過來也一樣: $(reason "$out")｜$(head -c 300 "$FX/hook.err")"

# mr 有授權（這張卡），後面接沒分類、不在 allow 的 glab api 寫入：deny
card_grants '["mr"]'
out="$(gg 'gh pr create --title x; glab api --method PUT projects/1/merge_requests/999/merge')"
assert_eq "$(decision "$out")" deny "glab api 寫入不能跟著 mr 授權放行: $(reason "$out")"
reason "$out" | grep -qF 'glab api' || fail "deny 要點名 glab api: $(reason "$out")"
card_grants '[]'

# 都涵蓋的串接照放行
for c in 'git add a.txt && git commit -m x && git push' 'git merge -s ours origin/main && git push' 'cd /x && git push' 'git push && echo done' 'git push 2>&1' 'git status && git push 2>&1 | cat'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的串接要放行（${c}）: $(reason "$out")"
  assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" allow "要明說 allow（${c}）"
done

# 命令替換與反引號裡的指令也逐段查：藏在允許的前綴或 echo 底下也要擋
for c in 'git push && git add $(rm -rf important)' 'git push && git add `rm -r important`' 'git push $(rm -rf important)' 'git push && echo $(./evil.sh)' 'git push && git status $(touch .env)' 'git push && (./evil.sh)' 'git push && cat <(./evil.sh)'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "命令替換裡沒涵蓋的指令要擋（${c}）: $(reason "$out")"
done
# heredoc、算術、小指令帶重導向、分行、前綴子串：後面的指令仍逐段查（骨架已移掉 heredoc，這一層不能再移一次）
for c in $'git push\ncat <<EOF\nx\nEOF\n./evil' $'git push && cat <<EOF > notes.txt\nhello\nEOF\ngit status; ./evil' $'git push\ncat <<<foo\n./evil\nfoo' $'git push\necho $((1<<2))\n./evil\necho 2' $'git push && cd /tmp && bash <<EOF\n./evil\nEOF' 'git push && echo $((1+$(./evil)))' 'git push && echo $((./evil) )' 'git push && echo $(( $(./evil) ))' 'git push && echo x > .husky/pre-commit' 'git push && cd . > src/important.ts' $'git push\n./evil' 'git push && git status `./evil`' 'git push && echo "`./evil`"' 'git push && git addx' 'git push && echo `echo \`./evil\``' 'git push && echo `echo \`echo \\\`./evil\\\`\``'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "要擋（${c}）: $(reason "$out")"
done
for c in $'git push && cat <<EOF > notes.txt\nhello\nEOF\ngit status' 'git push && echo $((1+2))' 'git push && echo \`literal\` ./evil'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的要放行（${c}）: $(reason "$out")"
done
# 命令替換裡是涵蓋的指令、子 shell 裡是涵蓋的指令：放行
for c in 'git push origin $(git branch --show-current)' 'git push && echo $(date)' '( cd /x && git push )' 'git push origin "$(git branch --show-current)"'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "涵蓋的命令替換與子 shell 要放行（${c}）: $(reason "$out")"
done
# 只有 mr 授權：管線與背景符號緊接在前面的 push、rebase、rm 一樣要授權
printf '[repos."Acmecorp-AI"]\npush = false\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
card_grants '["mr"]'
for c in 'gh pr create --title x; echo |git push' 'gh pr create --title x ||git push origin feat' 'gh pr create --title x &git push' 'gh pr create --title x; echo|rm -rf important' 'gh pr create --title x; git status|git rebase main'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "沒授權的類別不能跟著 mr 授權放行（${c}）: $(reason "$out")"
done
card_grants '[]'
printf '[repos."Acmecorp-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"

# 單段指令不需要 settings：沒有 settings 檔也照放行
rm -f "$SETTINGS"
out="$(gg 'git push')"; assert_eq "$(decision "$out")" allow "單段不讀 settings: $(reason "$out")"
out="$(gg 'cd /x && git push')"; assert_eq "$(decision "$out")" allow "cd 與授權的段不讀 settings: $(reason "$out")"
# 串了需要查 settings 的段、settings 讀不到：deny，說明原因
out="$(gg 'git add a.txt && git push')"; assert_eq "$(decision "$out")" deny "讀不到 settings 要擋: $(reason "$out")"
reason "$out" | grep -qF "$SETTINGS" || fail "deny 要點名 settings 路徑: $(reason "$out")"
# feature session：dispatch 條目的 herdr_name 是 feature 名，settings 檔在 feature 名之下（dispatch.sh 以 feature 當 slug 寫）
printf '{"Acmecorp-AI/eval-core":{"mode":"autopilot","grants":[],"herdr_name":"fsess","feature":"fsess","via":"@fsess"}}' > "$OPSX_STATE_DIR/dispatch.json"
printf '{"permissions":{"allow":["Bash(git add:*)","Bash(git commit:*)"]}}' > "$OPSX_STATE_DIR/settings/Acmecorp-AI-fsess-autopilot.json"
out="$(gg 'git add a.txt && git commit -m x && git push')"; assert_eq "$(decision "$out")" allow "feature session 要用 feature 名找 settings: $(reason "$out")"
out="$(gg 'git -C . merge origin/main && git push')"; assert_eq "$(decision "$out")" deny "feature session 的 settings 也要擋 allow 外的段"
# MR 留言不是第二級：有 mr 授權時閘門也不輸出 allow，交給 dontAsk 的 settings 去拒
printf '[repos."Acmecorp-AI"]\npush = false\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
card_grants '["mr"]'
for c in 'gh pr comment 159 --body-file openspec/changes/x/logic-map.md' 'gh pr comment 159 --edit-last --body-file x.md'; do
  out="$(gg "$c")"; assert_eq "$out" "" "MR 留言閘門不放行（${c}）"
done
card_grants '[]'

# command-gate-bypass：git 與 push 之間夾全域選項，一樣是 push（沒有 push 授權要擋）
printf '[repos."Acmecorp-AI"]\npush = false\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
# 帶 -c 的 push 是設定注入、第三級，在 tests/git-global-options.test.sh
for c in 'git -C /tmp/r push origin feat/x' 'git --git-dir=/tmp/r/.git push origin feat/x' 'git --git-dir /tmp/r/.git push origin feat/x' 'git --work-tree=/tmp/r push origin feat/x' 'git --no-pager push origin feat/x'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "沒有 push 授權，夾全域選項的 push 要擋：${c}｜$(reason "$out")"
  case "$(reason "$out")" in *第二級*) ;; *) fail "要說這是第二級的 push：${c}｜$(reason "$out")" ;; esac
done
out="$(gg 'git -C /tmp/r log --oneline')"; assert_eq "$out" "" "夾全域選項的非 push 不出聲"
out="$(gg 'git -C /tmp/r status && echo push')"; assert_eq "$out" "" "push 字樣只出現在別的指令不算"
# 有 push 授權：夾全域選項的 push 放行，危險的寫法仍擋（第三級，授權不夠）
printf '[repos."Acmecorp-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
out="$(gg 'git -C /tmp/r push origin feat/x')"
printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="allow"' >/dev/null || fail "有 push 授權的 -C push 要明說放行（輸出：${out}）"
for c in 'git -C /tmp/r push --force origin feat' 'git -c core.x=1 push -f origin feat' 'git --git-dir=/tmp/r/.git push --force origin feat' 'git -C /tmp/r push origin main' 'git --no-pager push origin HEAD:main' 'git push --receive-pack=evil origin feat' 'git push --exec=evil origin feat' 'git -C /tmp/r push --all origin' 'git push --mirror origin' "GIT_SSH_COMMAND='sh -c evil' git push origin feat" "git -c core.sshCommand='sh -c evil' push origin feat" "git -c core.sshcommand='sh -c evil' push origin feat" "GIT_SSH=./evil git push origin feat"; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "push 授權不夠，危險的寫法要擋：${c}｜$(reason "$out")"
  case "$(reason "$out")" in *第三級*) ;; *) fail "要說這是第三級：${c}｜$(reason "$out")" ;; esac
done
# autopilot-local-ops：權限檔不放 rm，閘門只對派工 session（OPSX_CARD 的卡是 autopilot／drive）的嚴格普通 rm 明說 allow
explicit() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
printf '[repos."Acmecorp-AI"]\npush = true\nmr = false\nmigrate = false\n' > "$OPSX_STATE_DIR/grants.toml"
printf '{"Acmecorp-AI/eval-core":{"mode":"autopilot","grants":[]},"Acmecorp-AI/interactive-card":{"mode":"interactive","grants":[]},"Acmecorp-AI/@feat-x":{"mode":"autopilot"}}' > "$OPSX_STATE_DIR/dispatch.json"
git -C "$R" worktree add -q "$R/.claude/worktrees/agent-x" -b worktree-agent-x
UW="$(cd "$R/.claude/worktrees/agent-x" && pwd -P)"
export OPSX_CARD=eval-core
for c in 'rm tests/zz-probe.test.sh' 'rm a.txt b.txt' 'rm -v tests/zz-probe.test.sh' 'rm -i tests/zz-probe.test.sh' 'rm tests/from-rfc.txt'; do
  out="$(gg "$c")"; assert_eq "$(explicit "$out")" allow "派工 session 的普通 rm 要明說放行（${c}）: $(reason "$out")"
done
out="$(gg 'rm tests/zz-probe.test.sh' "$UW")"; assert_eq "$(explicit "$out")" allow "subagent worktree 帶 OPSX_CARD 的普通 rm 要明說放行: $(reason "$out")"
export OPSX_CARD=feat-x
out="$(gg 'rm tests/zz-probe.test.sh')"; assert_eq "$(explicit "$out")" allow "feature session（條目只有 <repo>/@feat-x）的普通 rm 要明說放行: $(reason "$out")"
export OPSX_CARD=eval-core
for c in 'rm \-rf build' 'rm -rf>x build' 'rm $(cat list)' 'rm tests/zz-*.test.sh' "rm 'a b.txt'" 'rm x -rf' 'rm --recur build' $'rm a.txt\ngrep -rn foo .' 'rm a.txt; ls'; do
  out="$(gg "$c")"; [ "$(explicit "$out")" != allow ] || fail "形狀不嚴格的 rm 不能明說放行（${c}）"
done
for c in 'rm .env' 'rm src/.env.local' 'rm a.txt .Env'; do
  out="$(gg "$c")"; [ "$(explicit "$out")" != allow ] || fail "刪 .env 不能明說放行（${c}）"
done
for c in 'rm /tmp/state/dispatch.json' 'rm ../x.txt' 'rm a/../../x.txt' 'rm config/secrets.yaml' 'rm x.sops.yaml' 'rm infra/sops/key' 'rm sops/key'; do
  out="$(gg "$c")"; [ "$(explicit "$out")" != allow ] || fail "刪工作目錄外或 secrets 的檔不能明說放行（${c}）"
done
for c in 'rm .env.example' 'rm foo.envrc' 'rm a..b.txt'; do
  out="$(gg "$c")"; assert_eq "$(explicit "$out")" allow "範例檔或只含 env 字樣的檔照舊放行（${c}）: $(reason "$out")"
done
for c in 'rm -rf build' 'rm -r tests/tmp' 'rm -f tests/zz-probe.test.sh' 'git status && rm -rf build' 'git rm -f old.txt' 'git rm -r old-dir' 'git rm -rf old-dir' 'git status && git rm -f old.txt'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "沒有 delete 授權的 rm -r／-f 要擋（${c}）: $(reason "$out")"
  reason "$out" | grep -qF 'action: delete' || fail "deny 要是 delete 授權（${c}）: $(reason "$out")"
done
for c in 'git rm -q old.txt' 'git mv a.txt b.txt' 'git rm --cached old.txt'; do
  out="$(gg "$c")"; [ "$(decision "$out")" != deny ] || fail "普通 git rm 與 git mv 閘門不擋（${c}）: $(reason "$out")"
done
for card in interactive-card no-such-card; do
  export OPSX_CARD="$card"
  out="$(gg 'rm tests/zz-probe.test.sh')"; [ "$(explicit "$out")" != allow ] || fail "OPSX_CARD=${card} 不是派工的 autopilot 卡，不能放行 rm"
done
unset OPSX_CARD
out="$(gg 'rm tests/zz-probe.test.sh')"; [ "$(explicit "$out")" != allow ] || fail "沒有 OPSX_CARD 不能放行 rm"
out="$(gg 'rm tests/zz-probe.test.sh' "$UW")"; [ "$(explicit "$out")" != allow ] || fail "使用者自己的 subagent 沒有 OPSX_CARD 不能放行 rm"
echo "grant-gate-segments ok"
