#!/usr/bin/env bash
# launch_args：dispatch 與 relaunch 共用的 agent 啟動參數。主殼 relaunch-cmd D1。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
source "$OPSX_ROOT/bin/lib/common.sh"
source "$OPSX_ROOT/bin/lib/python.sh"
opsx_python_load || fail "python 載不起來：$OPSX_PY_ERR"
source "$OPSX_ROOT/bin/lib/launch.sh"

# 主 repo 路徑帶空白：陣列元素不能被拆開
TOP="$FX/my repo"; mkdir -p "$TOP/openspec"
SD="$OPSX_STATE_DIR"

# --- claude autopilot ---
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS retry-backoff "$TOP"
S="$SD/settings/Acmecorp-CS-retry-backoff-autopilot.json"
assert_eq "${#LAUNCH_ARGS[@]}" 10 "claude autopilot 參數個數"
assert_eq "${LAUNCH_ARGS[*]}" "--model claude-sonnet-5-5 --permission-mode dontAsk --settings $S --add-dir $TOP/openspec --add-dir $SD"
assert_eq "${LAUNCH_ARGS[7]}" "$TOP/openspec" "含空白的路徑要是同一個元素"
assert_file "$S"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "allow" in d and "deny" in d,d;assert d["additionalDirectories"]==[sys.argv[2],sys.argv[3]],d' "$S" "$TOP/openspec" "$SD" || fail "autopilot settings 內容不對"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["env"]=={"OPSX_CARD":"retry-backoff","VITEST_MAX_FORKS":"2","VITEST_MAX_THREADS":"1"},d' "$S" || fail "autopilot settings 要帶 env OPSX_CARD 與 vitest worker 上限"
# 同一組輸入呼叫兩次（dispatch 一次、relaunch 一次）：逐字相同
first=("${LAUNCH_ARGS[@]}")
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS retry-backoff "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "${first[*]}" "dispatch 與 relaunch 要拿到同一串參數"
assert_eq "${#LAUNCH_ARGS[@]}" "${#first[@]}" "第二次呼叫不能接在上一次的陣列後面"

# --- claude interactive：沒有 --permission-mode，settings 檔按模式分名 ---
launch_args claude claude-opus-5-5 interactive Acmecorp-CS retry-backoff "$TOP"
SI="$SD/settings/Acmecorp-CS-retry-backoff-interactive.json"
assert_eq "${LAUNCH_ARGS[*]}" "--model claude-opus-5-5 --settings $SI --add-dir $TOP/openspec --add-dir $SD"
assert_file "$SI"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert d=={"additionalDirectories":[sys.argv[2],sys.argv[3]]},d' "$SI" "$TOP/openspec" "$SD" || fail "interactive settings 只該有可寫目錄"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["env"]=={"OPSX_CARD":"retry-backoff","VITEST_MAX_FORKS":"2","VITEST_MAX_THREADS":"1"},d' "$SI" || fail "interactive settings 要帶 env OPSX_CARD 與 vitest worker 上限"
assert_file "$S"   # 另一個模式那份不被蓋掉

# --- codex：不寫 settings ---
launch_args codex gpt-5-codex autopilot Acmecorp-CS codex-card "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "-a never -s workspace-write --add-dir $TOP/openspec --add-dir $SD"
launch_args codex gpt-5-codex interactive Acmecorp-CS codex-card "$TOP"
assert_eq "${LAUNCH_ARGS[*]}" "-a on-request -s workspace-write --add-dir $TOP/openspec --add-dir $SD"
assert_no_file "$SD/settings/Acmecorp-CS-codex-card-autopilot.json"
assert_no_file "$SD/settings/Acmecorp-CS-codex-card-interactive.json"

# --- autopilot-test-allow：ring3 測試前綴只比對前綴，設定檔不含連線字串或密碼 ---
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(TEST_DATABASE_URL=* pnpm vitest:*)" in a and "Bash(TEST_DATABASE_URL=* pnpm test:*)" in a,a' "$S" || fail "autopilot allow 缺 TEST_DATABASE_URL 前綴規則"
python3 -I -c 'import json,sys;a=[r for r in json.load(open(sys.argv[1]))["permissions"]["allow"] if r.startswith("Bash(TEST_DATABASE_URL=")];assert a and all(r.startswith("Bash(TEST_DATABASE_URL=* pnpm ") for r in a),a' "$S" || fail "TEST_DATABASE_URL 規則的值只能是 *"
assert_eq "$(grep -c 'TEST_DATABASE_URL' "$SI")" 0 "interactive 不放行 ring3 測試指令"

# --- orca-autopilot-allow：autopilot 放行 orca 子指令，interactive 不放行 ---
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];w=["Bash(orca status:*)","Bash(orca repo list:*)","Bash(orca repo add:*)","Bash(orca repo set:*)","Bash(orca worktree list:*)","Bash(orca tab create:*)","Bash(orca terminal read:*)"];assert [r for r in a if "orca" in r]==w,a' "$S" || fail "autopilot allow 的 orca 規則要剛好是七條子指令"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"].get("allow",[]);assert not [r for r in a if "orca" in r],a' "$SI" || fail "interactive 不放行 orca"
assert_eq "$(grep -c '://' "$S")" 0 "settings 不含連線字串（任何 scheme://）"

# --- D11：glab ci 只放行唯讀子指令，不放行整個 glab ci（run、delete、cancel 在沙盒外會真的打到 forge）---
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];w=["Bash(glab ci view:*)","Bash(glab ci status:*)","Bash(glab ci list:*)","Bash(glab ci get:*)","Bash(glab ci trace:*)"];assert [r for r in a if r.startswith("Bash(glab ci")]==w,a' "$S" || fail "autopilot allow 的 glab ci 規則要剛好是五條唯讀子指令"

# --- docs-api-autopilot-allow：主 checkout 根目錄 package.json 的 scripts 有 docs:api 才放行；不放行整個 pnpm、tsx 與其他 tsx script；interactive 不放行 ---
# 邊界：沒有 package.json（上面那張卡的 TOP）
assert_eq "$(grep -c 'pnpm docs:api' "$S")" 0 "沒有 package.json 的 repo 不放行 pnpm docs:api"
# 一般：scripts 只有 build 與 test
printf '{"scripts":{"build":"tsc","test":"vitest"}}\n' > "$TOP/package.json"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS no-docs "$TOP"
assert_eq "$(grep -c 'pnpm docs:api' "$SD/settings/Acmecorp-CS-no-docs-autopilot.json")" 0 "scripts 沒有 docs:api 的 repo 不放行"
# 邊界："docs:api" 只出現在 scripts 以外
printf '{"description":"run docs:api by hand","scripts":{"build":"tsc"},"docs:api":"x"}\n' > "$TOP/package.json"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-CS docs-outside "$TOP"
assert_eq "$(grep -c 'pnpm docs:api' "$SD/settings/Acmecorp-CS-docs-outside-autopilot.json")" 0 "docs:api 只在 scripts 以外時不放行"
# 正例
printf '{"scripts":{"build":"tsc","docs:api":"tsx scripts/api-docs/gen.ts"}}\n' > "$TOP/package.json"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI docs-card "$TOP"
SA="$SD/settings/Acmecorp-AI-docs-card-autopilot.json"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(pnpm docs:api:*)" in a,a' "$SA" || fail "根目錄 package.json 有 docs:api 時 allow 要有 Bash(pnpm docs:api:*)"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(pnpm:*)" not in a and "Bash(tsx:*)" not in a,a;assert not [r for r in a if r.startswith(("Bash(pnpm i18n:split","Bash(pnpm seed:e2e","Bash(pnpm docs:*"))],a' "$SA" || fail "autopilot allow 不能放行整個 pnpm、tsx、pnpm docs:* 或其他 tsx script"
launch_args claude claude-opus-5-5 interactive Acmecorp-AI docs-card "$TOP"
assert_eq "$(grep -c 'pnpm docs:api' "$SD/settings/Acmecorp-AI-docs-card-interactive.json")" 0 "interactive 不放行 pnpm docs:api"
# 主 checkout 的 package.json 壞掉：失敗、點名檔案、不寫 settings
printf '{bad' > "$TOP/package.json"
SB="$SD/settings/broken-json.json"
assert_rc 1 write_settings "$SB" Acmecorp-AI "$TOP/openspec" autopilot broken-json
write_settings "$SB" Acmecorp-AI "$TOP/openspec" autopilot broken-json 2>&1 | grep -qF "$TOP/package.json" || fail "壞 JSON 的錯誤訊息要含 package.json 路徑"
assert_no_file "$SB"
printf '{"scripts":null}\n' > "$TOP/package.json"
SN="$SD/settings/null-scripts.json"
assert_rc 1 write_settings "$SN" Acmecorp-AI "$TOP/openspec" autopilot null-scripts
write_settings "$SN" Acmecorp-AI "$TOP/openspec" autopilot null-scripts 2>&1 | grep -qF "$TOP/package.json" || fail "scripts 不是物件的錯誤訊息要含 package.json 路徑"
assert_no_file "$SN"
rm -f "$TOP/package.json"

# --- migrate 授權：filter 寫法只在 grants.toml 開 migrate 時出現 ---
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI no-grant "$TOP"
assert_eq "$(grep -c 'db:migrate' "$SD/settings/Acmecorp-AI-no-grant-autopilot.json")" 0 "沒有 migrate 授權就沒有 migrate 規則"
printf '[repos.Acmecorp-AI]\nmigrate = true\n' > "$SD/grants.toml"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI with-grant "$TOP"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert "Bash(pnpm --filter * run db:migrate:*)" in a and "Bash(pnpm db:migrate:*)" in a,a' "$SD/settings/Acmecorp-AI-with-grant-autopilot.json" || fail "migrate 授權要放行 filter 寫法與原本的 db:migrate"
rm -f "$SD/grants.toml"

# --- autopilot-forge-access：有 push 或 mr 授權時放行主要 remote 的主機，glab 在沙盒外 ---
forge_repo() { # <目錄> [<remote 名>=<url> …]：造一個帶 remote 的 git repo
  local dir="$1"; shift
  mkdir -p "$dir/openspec"; git -C "$dir" init -q
  local kv; for kv in "$@"; do git -C "$dir" remote add "${kv%%=*}" "${kv#*=}"; done
}
sandbox_of() { python3 -I -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])).get("sandbox","MISSING"),sort_keys=True))' "$1"; }
GLAB_EXCLUDED='["glab mr *", "glab ci *", "glab issue *"]'

# Scenario Outline：有授權且有 gitlab remote 時放行該主機（一般＋邊界）
# 欄位：授權 | 卡名 | remotes（以 ; 分隔）| 放行主機
while IFS='|' read -r grant card remotes host; do
  printf '[repos.Forge]\n%b\n' "$grant" > "$SD/grants.toml"
  IFS=';' read -r -a rs <<< "$remotes"
  forge_repo "$FX/forge-$card" "${rs[@]}"
  launch_args claude claude-sonnet-5-5 autopilot Forge "$card" "$FX/forge-$card"
  assert_eq "$(sandbox_of "$SD/settings/Forge-$card-autopilot.json")" "{\"excludedCommands\": $GLAB_EXCLUDED, \"network\": {\"allowedDomains\": [\"$host\"]}}" "${card}：放行主機與 glab 沙盒外"
done <<'ROWS'
push = true|g-push|gitlab=https://gitlab.example.com/acme/app.git;origin=https://github.com/acme/app.git|gitlab.example.com
mr = true|g-mr|gitlab=https://gitlab.example.com/acme/app.git|gitlab.example.com
push = true\nmr = true|g-scp|gitlab=git@gitlab.example.com:acme/app.git|gitlab.example.com
push = true|g-port|gitlab=https://gitlab.example.com:8443/acme/app.git|gitlab.example.com
mr = true|g-user|gitlab=https://user@gitlab.example.com/acme/app.git|gitlab.example.com
ROWS
rm -f "$SD/grants.toml"

# Scenario：沒有 mr 授權不放行 MR 留言（反例）：g-push 那列只有 push 授權
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];assert not [x for x in a if "glab mr note" in x],a;assert not [x for x in a if "glab api" in x],a' "$SD/settings/Forge-g-push-autopilot.json" || fail "只有 push 授權不放行 glab mr note 與 glab api"

# Scenario：沒有 gitlab remote 時用 origin 的主機
printf '[repos.Forge]\npush = true\n' > "$SD/grants.toml"
forge_repo "$FX/forge-origin" origin=https://github.com/acme/app.git
launch_args claude claude-sonnet-5-5 autopilot Forge origin-only "$FX/forge-origin"
assert_eq "$(sandbox_of "$SD/settings/Forge-origin-only-autopilot.json")" "{\"excludedCommands\": $GLAB_EXCLUDED, \"network\": {\"allowedDomains\": [\"github.com\"]}}" "只有 origin 時放行 origin 的主機"

# Scenario：git 與 glab api 不在沙盒外（反例）
python3 -I -c 'import json,sys;e=json.load(open(sys.argv[1]))["sandbox"]["excludedCommands"];assert not [x for x in e if x.startswith("git")],e;assert "glab api *" not in e and "glab *" not in e,e' "$SD/settings/Forge-origin-only-autopilot.json" || fail "excludedCommands 不能有 git、glab api 或整個 glab"

# Scenario：沒有 remote 時不寫沙盒設定（反例）
printf '[repos.Forge]\npush = true\nmr = true\n' > "$SD/grants.toml"
forge_repo "$FX/forge-none"
assert_rc 0 launch_args claude claude-sonnet-5-5 autopilot Forge no-remote "$FX/forge-none"
assert_eq "$(sandbox_of "$SD/settings/Forge-no-remote-autopilot.json")" '"MISSING"' "沒有 remote 不寫 sandbox"

# D6、D7：remote URL 取不到主機名（file://、本機路徑）時當作沒有主機，不報錯、不寫 sandbox
forge_repo "$FX/forge-file" gitlab=file:///srv/app.git
assert_rc 0 launch_args claude claude-sonnet-5-5 autopilot Forge file-remote "$FX/forge-file"
assert_eq "$(sandbox_of "$SD/settings/Forge-file-remote-autopilot.json")" '"MISSING"' "file:// remote 不寫 sandbox"
forge_repo "$FX/forge-path" gitlab=/srv/app.git
assert_rc 0 launch_args claude claude-sonnet-5-5 autopilot Forge path-remote "$FX/forge-path"
assert_eq "$(sandbox_of "$SD/settings/Forge-path-remote-autopilot.json")" '"MISSING"' "本機路徑 remote 不寫 sandbox"
forge_repo "$FX/forge-rel" gitlab=../app.git
assert_rc 0 launch_args claude claude-sonnet-5-5 autopilot Forge rel-remote "$FX/forge-rel"
assert_eq "$(sandbox_of "$SD/settings/Forge-rel-remote-autopilot.json")" '"MISSING"' "相對路徑 remote 不寫 sandbox"

# Scenario：interactive 不寫沙盒設定（反例）
forge_repo "$FX/forge-inter" gitlab=https://gitlab.example.com/acme/app.git
launch_args claude claude-opus-5-5 interactive Forge inter "$FX/forge-inter"
assert_eq "$(sandbox_of "$SD/settings/Forge-inter-interactive.json")" '"MISSING"' "interactive 不寫 sandbox"

# Scenario：沒有授權時不寫沙盒設定（反例）
printf '[repos.Forge]\nmigrate = true\n' > "$SD/grants.toml"
launch_args claude claude-sonnet-5-5 autopilot Forge no-grant "$FX/forge-inter"
assert_eq "$(sandbox_of "$SD/settings/Forge-no-grant-autopilot.json")" '"MISSING"' "沒有 push / mr 授權不寫 sandbox"
rm -f "$SD/grants.toml"

# --- autopilot-local-ops：本地小操作不看授權都放行；interactive 不放行；不放過寬的寫法 ---
LOCAL_OPS='["Bash(chmod +x:*)","Bash(git switch:*)","Bash(bash evals/prepare-run.sh:*)","Bash(git mv:*)","Bash(git rm:*)"]'
has_local_ops() { python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];m=[r for r in json.loads(sys.argv[2]) if r not in a];assert not m,m' "$1" "$LOCAL_OPS"; }
printf '[repos.Other]\npush = true\n' > "$SD/grants.toml"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI no-entry "$TOP"
has_local_ops "$SD/settings/Acmecorp-AI-no-entry-autopilot.json" || fail "grants.toml 沒有這個 repo 也要放行本地小操作"
printf '[repos.Acmecorp-AI]\npush = true\nmr = true\nmigrate = true\n' > "$SD/grants.toml"
launch_args claude claude-sonnet-5-5 autopilot Acmecorp-AI all-grant "$TOP"
has_local_ops "$SD/settings/Acmecorp-AI-all-grant-autopilot.json" || fail "有其他授權時照樣放行本地小操作"
rm -f "$SD/grants.toml"
has_local_ops "$S" || fail "沒有 grants.toml 也要放行本地小操作"
python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]))["permissions"];assert "allow" not in d,d' "$SI" || fail "interactive 不放行本地小操作"
python3 -I -c 'import json,sys;a=json.load(open(sys.argv[1]))["permissions"]["allow"];w=[r for r in ("Bash(rm:*)","Bash(chmod:*)","Bash(bash evals/:*)","Bash(bash evals/run-candidate.sh:*)") if r in a];assert not w,w' "$S" || fail "不放行 rm 字首或過寬的 chmod、evals 寫法"

echo ok
