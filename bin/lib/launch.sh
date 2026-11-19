#!/usr/bin/env bash
# agent 啟動參數：dispatch 與 relaunch 共用，交給 `herdr agent start … -- "${LAUNCH_ARGS[@]}"`。
# 結果放在全域陣列 LAUNCH_ARGS：bash 函式回傳不了陣列，走 stdout 的話含空白的路徑會被拆開。呼叫完要馬上用。

launch_args() { # <agent> <model> <mode> <repo> <herdr 名> <主 repo>
  local agent="$1" model="$2" mode="$3" repo="$4" name="$5" top="$6"
  LAUNCH_ARGS=()
  # claude 兩種模式都帶 --settings；--permission-mode 與 allow / deny 只有 autopilot 才有。
  # settings 檔按模式分名，重派不會蓋掉 pane 還沒關的另一個模式那份
  if [ "$agent" = claude ]; then
    LAUNCH_ARGS+=(--model "$model")
    local settings="$OPSX_STATE_DIR/settings/$repo-$name-$mode.json"; ensure_dir "$(dirname "$settings")"
    write_settings "$settings" "$repo" "$top/openspec" "$mode" "$name"
    if [ "$mode" != interactive ]; then LAUNCH_ARGS+=(--permission-mode dontAsk); fi   # dontAsk：不在 allow 的直接拒絕不跳框；跳框會讓 herdr 判 blocked，drive 送不進下一句
    LAUNCH_ARGS+=(--settings "$settings")
    # Claude Code 的沙盒只准寫 working directories；卡的檔在主 repo 的 openspec/（worktree 裡沒有），hook 消耗 once 與 status 鏡像寫 state dir。
    # 旗標只活在這個行程；重啟後 --settings 有沒有被帶回、additionalDirectories 還在不在，尚未實測（add-dir-lost 1.1）
    LAUNCH_ARGS+=(--add-dir "$top/openspec" --add-dir "$OPSX_STATE_DIR")
  else
    if [ "$mode" = interactive ]; then LAUNCH_ARGS+=(-a on-request -s workspace-write); else LAUNCH_ARGS+=(-a never -s workspace-write); fi
    # 卡的檔在主 repo 的 openspec/，不在 worktree；沒有這兩個，規則叫它寫的 gates.md / status.json 寫不進
    LAUNCH_ARGS+=(--add-dir "$top/openspec" --add-dir "$OPSX_STATE_DIR")
  fi
}

write_settings() { # <file> <repo> <主 repo openspec 目錄> <mode> <herdr 名>：autopilot 直接做那級 allow，永遠要人那級 deny；repo 永遠的授權也進 allow。interactive 只寫可寫目錄。兩種模式都寫 env OPSX_CARD，opsx new 靠它認出 dispatch 的 agent
  OPSX_REPO="$2" OPSX_SD="$OPSX_STATE_DIR" OPSX_MODE="$4" OPSX_NAME="$5" "$OPSX_PY" -I - "$1" "$3" <<'PY'
import json,os,subprocess,sys,tomllib,urllib.parse
sys.path.insert(0, os.path.join(os.environ["OPSX_ROOT"], "bin", "lib")); import safefile

def remote_host(top):
    """主要 remote（gitlab，沒有就 origin）的主機名；兩個都沒有，或主要 remote 是 file:// 或本機路徑時回 None。"""
    for name in ("gitlab", "origin"):
        r = subprocess.run(["git", "-C", top, "config", "--get", f"remote.{name}.url"], capture_output=True, text=True)
        if r.returncode == 1: continue   # 這個 remote 不存在
        if r.returncode != 0: raise SystemExit(f"{top}: 讀 remote.{name}.url 失敗：{r.stderr.strip()}")
        url = r.stdout.strip()
        if "://" in url: return urllib.parse.urlsplit(url).hostname   # file:// 沒有主機，回 None
        if ":" in url.split("/", 1)[0]: return url.split("@", 1)[-1].split(":", 1)[0]   # git 的規則：第一個 / 之前有 : 才是 scp 寫法 user@host:path
        return None   # 本機路徑
    return None
sd=os.environ["OPSX_SD"]; repo=os.environ["OPSX_REPO"]
dirs=[sys.argv[2],sd]
env={"OPSX_CARD":os.environ["OPSX_NAME"]}
if os.environ["OPSX_MODE"]=="interactive":
    safefile.write_atomic(sys.argv[1], json.dumps({"env":env,"permissions":{"additionalDirectories":dirs}},indent=2))
    sys.exit(0)
allow=["Read","Edit","Write","Glob","Grep","Bash(git status:*)","Bash(git diff:*)","Bash(git log:*)","Bash(git add:*)","Bash(git commit:*)","Bash(git checkout:*)","Bash(git worktree:*)",
       "Bash(pnpm test:*)","Bash(pnpm vitest:*)","Bash(TEST_DATABASE_URL=* pnpm vitest:*)","Bash(TEST_DATABASE_URL=* pnpm test:*)","Bash(pnpm build:*)","Bash(pnpm lint:*)","Bash(pnpm typecheck:*)","Bash(npx vitest:*)","Bash(pytest:*)","Bash(uv run:*)","Bash(ruff:*)","Bash(go test:*)",
       "Bash(openspec:*)","Bash(opsx:*)","Bash(ls:*)","Bash(cat:*)","Bash(grep:*)","Bash(rg:*)","Bash(find:*)","Bash(node:*)","Bash(python3:*)",
       "Bash(jq:*)","Bash(head:*)","Bash(tail:*)","Bash(wc:*)","Bash(sed -n:*)","Bash(diff:*)","Bash(sort:*)","Bash(bash tests/:*)","Bash(bash tests/*)","Bash(tests/run.sh:*)","Bash(herdr agent:*)","Bash(herdr pane read:*)","Bash(orca status:*)","Bash(orca repo list:*)","Bash(orca repo add:*)","Bash(orca repo set:*)","Bash(orca worktree list:*)","Bash(orca tab create:*)","Bash(orca terminal read:*)",
       "Bash(git show:*)","Bash(git branch:*)","Bash(git rev-parse:*)","Bash(git fetch:*)","Bash(git merge-base:*)","Bash(git merge:*)","Bash(git remote:*)","Bash(mkdir:*)",
       "Bash(glab mr view:*)","Bash(glab mr list:*)","Bash(glab mr diff:*)","Bash(glab ci view:*)","Bash(glab ci status:*)","Bash(glab ci list:*)","Bash(glab ci get:*)","Bash(glab ci trace:*)","Bash(gh pr view:*)","Bash(gh pr checks:*)","Bash(gh pr list:*)"]
# merge 不在 deny：settings 的 deny 蓋得過 hook 的放行，所以 merge 交給 opsx-grant-gate.sh 的 merge_gate 單獨把關；
# 放進 allow 是為了閘門放行那一次不再跳 Claude Code 自己的權限框。
allow += ["Bash(glab mr merge:*)", "Bash(gh pr merge:*)"]
# pnpm docs:api 在沙箱外跑（使用者層 excludedCommands）：只放行主 checkout 本來就有這條 script 的 repo，
# 免得 agent 在別的 repo 自己補一條 docs:api 就能在沙箱外跑任意指令。
# 放不放行只看主 checkout；執行時 pnpm 讀的是 worktree 的 package.json，有這條 script 的 repo 擋不了 agent 改它的內容
pkg=os.path.join(os.path.dirname(sys.argv[2]),"package.json")
try:
    data=json.load(open(pkg))
except FileNotFoundError: data={}
except json.JSONDecodeError as e: raise SystemExit(f"{pkg}: 不是合法 JSON：{e}") from e
if not isinstance(data,dict): raise SystemExit(f"{pkg}: 頂層要是物件，拿到 {data!r}")
scripts=data.get("scripts",{})
if not isinstance(scripts,dict): raise SystemExit(f"{pkg}: scripts 要是物件，拿到 {scripts!r}")
if "docs:api" in scripts: allow.append("Bash(pnpm docs:api:*)")
deny=["Bash(git push --force:*)","Bash(git push -f:*)","Bash(deploy.sh:*)","Bash(sops:*)","Bash(rm -rf /:*)"]
try:
    g=tomllib.load(open(os.path.join(sd,"grants.toml"),"rb")).get("repos",{}).get(repo,{})
except FileNotFoundError: g={}
if g.get("push"): allow.append("Bash(git push:*)")
if g.get("mr"): allow+=["Bash(glab mr create:*)","Bash(glab mr update:*)","Bash(glab mr note create:*)","Bash(glab mr note list:*)","Bash(gh pr create:*)","Bash(gh pr edit:*)","Bash(glab issue note:*)","Bash(glab issue comment:*)","Bash(gh issue comment:*)"]   # gh pr comment 與 glab api 不進 allow：規則放行形狀之外的寫法（-R other/repo、merge?x=/notes/1）
if g.get("migrate"): allow+=["Bash(pnpm db:migrate:*)","Bash(pnpm --filter * run db:migrate:*)","Bash(alembic upgrade:*)"]
settings={"env":env,"permissions":{"allow":allow,"deny":deny,"additionalDirectories":dirs}}
# dontAsk 下沒列進 allowedDomains 的網域一律被沙盒拒絕。git 在沙盒內連主機；
# glab 是 Go，沙盒內驗不過 TLS 憑證（gh 撞過 x509 -26276），放沙盒外跑，能不能跑仍由 allow 與 grant hook 決定
host=remote_host(os.path.dirname(sys.argv[2])) if g.get("push") or g.get("mr") else None
if host: settings["sandbox"]={"network":{"allowedDomains":[host]},"excludedCommands":["glab mr *","glab ci *","glab issue *"]}
safefile.write_atomic(sys.argv[1], json.dumps(settings,indent=2))
PY
}
