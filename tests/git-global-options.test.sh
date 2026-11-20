#!/usr/bin/env bash
# git 與子命令之間夾全域選項時，security guard 與授權閘門的判斷。
# 驗收：openspec/changes/agent-20261112-1103/specs/git-global-options/spec.md
source "$(dirname "${BASH_SOURCE[0]}")/grant-gate-fixture.sh"
sd() { run_hook security-guard.sh "$(j "$R" Bash "$(cmdj "$1")")"; }

# guard 認得夾全域選項的 push / add / commit
for c in 'git -C /tmp/r push origin main' 'git -c a=b push --force origin feat' 'git --no-pager push -f origin feat' 'git -C /tmp/r add .env' 'git -C /tmp/r commit -m x -m "Co-Authored-By: Claude <a@b.c>"' 'git --git-dir=/tmp/r/.git push origin HEAD:main' 'git -C /tmp/r -c a=b push origin main'; do
  out="$(sd "$c")"; assert_eq "$(decision "$out")" deny "guard 要擋（${c}）"
done
# 引號、反斜線、引號內的 & 都照 shell 解析完的樣子認
for c in "git -C '/tmp/a b' push -f origin feat" 'git -C "/tmp/a b" push origin main' 'git push -o "merge_request.title=A & B" --force origin feat' '"git" push --force origin feat' 'g\it push -f origin feat' 'git push origin feat 2>&1 --force' 'git push 2>&1 --force origin feat' 'git push origin feat >/dev/null 2>&1 -f' 'bash -c "git push -f origin feat"'; do
  out="$(sd "$c")"; assert_eq "$(decision "$out")" deny "guard 要擋（${c}）"
done
for c in 'git -C /tmp/r push origin feat/x' 'git -C claude-wt commit -m "fix: clean"' 'git -C /tmp/r log --oneline' 'echo "git -C x push origin main"' 'git push gitlab feat/x-main' 'git push origin feat && rm -f x' 'git commit -m "git push -f origin main" && git push origin feat'; do
  out="$(sd "$c")"; assert_eq "$(decision "$out")" allow "guard 要放行（${c}）: $(reason "$out")"
done

# push 帶設定注入是第三級
for c in "git -c remote.origin.receivepack='sh -c evil' push origin feat" "git -c credential.helper='!evil' push origin feat" 'git -c core.hooksPath=/tmp/h push origin feat' 'git --exec-path=/tmp/x push origin feat' 'git --exec-path /tmp/x push origin feat' 'GIT_EXEC_PATH=/tmp/x git push origin feat' 'git --config-env=core.hooksPath=H push origin feat' "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/tmp/h'\" git push origin feat" 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/h git push origin feat' 'git -c http.extraHeader=x push origin feat' 'git -C /tmp/r -c a=b push origin feat' "git -c protocol.ext.allow=always push 'ext::sh -c evil' feat"; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "設定注入要擋（${c}）"
  reason "$out" | grep -qF '第三級' || fail "設定注入要是第三級（${c}）: $(reason "$out")"
done
# 不帶設定注入的 push 照第二級授權放行
for c in 'git -C /tmp/r push origin feat/x' 'git --no-pager push origin feat/x' 'git push origin feat/x' 'echo GIT_EXEC_PATH=x && git push origin feat'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" allow "沒有設定注入要放行（${c}）: $(reason "$out")"
done

# 選項值含空白時仍認得 force 與 main
for c in "git -C '/tmp/a b' push -f origin feat" 'git -C "/tmp/a b" push origin main' 'git -C /tmp/a\ b push --force origin feat'; do
  out="$(gg "$c")"; assert_eq "$(decision "$out")" deny "含空白的選項值也要認得（${c}）"
done
out="$(gg "git -C '/tmp/a main' push origin feat")"; assert_eq "$(decision "$out")" allow "引號內的 main 不是 refspec: $(reason "$out")"
