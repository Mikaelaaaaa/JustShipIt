"""opsx backfill 的本體：各 repo 不在 workplan 的卡，每張印一行 <repo>\\t<卡>\\t<動作>\\t<原因>；write 時照同一個動作呼叫 workplanwrite.attach。
歸屬只看 workplanwrite.placement，跟建卡、派工同一份規則。預覽時把預定要加的 feature／PR 疊進記憶體裡的 workplan，
所以「父卡也是散卡」的子卡在預覽與寫入算出同一個結果。

用法：$OPSX_PY -I backfill.py <code root> <state dir> <write：1 或空字串> <repo 根或空字串>
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
import jsonfile  # noqa: E402
import priority  # noqa: E402
import sync  # noqa: E402
import workplanwrite  # noqa: E402

# split-out.sh 寫進新卡 decisions.tsv 說明欄的固定格式
SPLIT_FROM = re.compile(r"^從 (\S+) 拆出（id ")


def branch_user(top: str) -> str:
    """跟 common.sh 的 branch_user 同一條規則：OPSX_USER，沒設就是 git user.name 空白換 -、轉小寫；占位字 Your Name 當成沒有。"""
    u = os.environ.get("OPSX_USER") or subprocess.run(
        ["git", "-C", top, "config", "user.name"], capture_output=True, text=True).stdout.strip().replace(" ", "-").lower()
    return "" if u == "your-name" else u


def split_parent(card: str) -> str:
    for line in priority.read_text(os.path.join(card, "decisions.tsv")).split("\n"):
        cols = line.split("\t")
        m = SPLIT_FROM.match(cols[3]) if len(cols) > 3 else None
        if m:
            return m.group(1)
    return ""


def parent_of(fm: dict, card: str, top: str, known: set, in_plan: set) -> str:
    """先看 source: agent:<卡>，找不到再看 decisions.tsv 的「從 <卡> 拆出」（D3）。
    候選是 known（in_plan 加上本批散卡）裡的名字就用它；候選已拆時用它 split_into 裡第一個在 in_plan（workplan 的 PR／change／feature 名）的（D14）。
    都找不到就回第一個候選，placement 會當成沒有父卡、原因欄寫「不在 workplan」。"""
    src = fm.get("source") or ""
    cands = [c for c in [src[len("agent:"):].split("--")[0] if src.startswith("agent:") else "", split_parent(card)] if c]
    for c in cands:
        if c in known:
            return c
        hit = next((t for t in chain.split_into(top, c) if t in in_plan), None)
        if hit:
            return hit
    return cands[0] if cands else ""


def known_branch(top: str, repo: str, slug: str, dispatch: dict):
    """回 (branch, 略過原因)。dispatch.json 的紀錄優先，再來是本地唯一一條 <前綴>/<slug>/<尾巴>；都沒有回 ("", "")。"""
    rec = dispatch.get("%s/%s" % (repo, slug))
    if isinstance(rec, dict) and rec.get("branch"):
        return rec["branch"], ""
    out = subprocess.run(["git", "-C", top, "for-each-ref", "--format=%(refname:short)", "refs/heads/"],
                         capture_output=True, text=True, check=True).stdout.split()
    hits = sorted(b for b in out if len(b.split("/")) >= 3 and b.split("/")[1] == slug)
    if len(hits) > 1:
        return "", "branch 有兩條以上：%s" % "、".join(hits)
    return (hits[0] if hits else ""), ""


def order(parents: dict) -> list:
    """parents 是 散卡 到 父卡名；父卡也是散卡的，排在子卡前面，其餘照名字排序。父卡鏈繞回自己時在繞回處停。"""
    seen, out = set(), []
    for s in sorted(parents):
        chain = []
        while s is not None and s not in seen and s not in chain:
            chain.append(s)
            s = parents[s] if parents[s] in parents else None
        for c in reversed(chain):
            seen.add(c)
            out.append(c)
    return out


def run_repo(name: str, top: str, write: bool, dispatch: dict, out: list, failed: list) -> None:
    if not os.path.exists(os.path.join(top, "openspec", "workplan.yaml")):
        out.append((name, "-", "略過", "repo 沒有 workplan"))
        return
    try:
        plan = priority.load_plan(top)
        levels = priority.levels(top)
    except priority.PriorityError as e:
        failed.append("%s: %s" % (name, e))
        return
    features = plan["features"]
    own = priority.owners(features)
    changes = os.path.join(top, "openspec", "changes")
    cards = {}
    for s in sorted(os.listdir(changes)):
        d = os.path.join(changes, s)
        if s.startswith(".") or s == "archive" or not os.path.isdir(d) or s in own:
            continue
        inbox = os.path.join(d, "inbox.md")
        if not os.path.exists(inbox):
            out.append((name, s, "略過", "沒有 inbox.md"))
            continue
        fm, _ = priority.frontmatter(priority.read_text(inbox))
        if chain.split_into(top, s):
            out.append((name, s, "略過", "已拆"))
            continue
        cards[s] = (fm, d)
    in_plan = set(own) | {f.get("name") for f in features}
    parents = {s: parent_of(fm, d, top, in_plan | set(cards), in_plan) for s, (fm, d) in cards.items()}
    user = branch_user(top)
    bad = set()
    for s in order(parents):
        parent = parents[s]
        why_bad = ""
        got = levels[s]
        if parent in bad:
            why_bad = "父卡 %s 寫入失敗" % parent
        elif "error" in got:
            why_bad = got["error"]
        if why_bad:
            failed.append("%s/%s: %s" % (name, s, why_bad))
            bad.add(s)
            continue
        branch, skip = known_branch(top, name, s, dispatch)
        if skip:
            out.append((name, s, "略過", skip))
            failed.append("%s/%s: %s" % (name, s, skip))
            bad.add(s)
            continue
        into, milestone = workplanwrite.placement(features, got["level"], parent, "")
        # 預覽也要擋下 --write 時 attach 會拒絕的卡，預覽與寫入才印同樣的結果
        names = set(priority.owners(features)) | ({f.get("name") for f in features} if into is None else set())
        if s in names:
            why_bad = "workplan 已經有 %s" % s
        elif not branch and not user:
            why_bad = "分支尾巴沒有名字：OPSX_USER 沒設，git config user.name 是空的或占位字「Your Name」"
        if not why_bad and write:
            try:
                workplanwrite.attach(top, s, parent, user, "", branch, "")
            except (workplanwrite.WorkplanError, priority.PriorityError) as e:
                why_bad = str(e)
        if why_bad:
            failed.append("%s/%s: %s" % (name, s, why_bad))
            bad.add(s)
            continue
        found = parent in priority.owners(features) or any(f.get("name") == parent for f in features)
        why = "沒有父卡" if not parent else ("父卡 %s" % parent if found else "父卡 %s 不在 workplan" % parent)
        if got["level"] != "P2":
            why += "，等級 %s" % got["level"]
        if into is not None:
            act = "掛進 feature %s" % into
        else:
            act = "自成 feature" + ("（milestone %s）" % milestone if milestone else "")
        out.append((name, s, act, why))
        pr = {"name": s, "changes": [{"name": s}]}
        if into is not None:
            next(f for f in features if f.get("name") == into).setdefault("prs", []).append(pr)
        else:
            feature = {"name": s, "status": "active", "prs": [pr]}
            if milestone:
                feature["milestone"] = milestone
            features.append(feature)


def main(code_root: str, state: str, write: str, top: str) -> int:
    out, failed = [], []
    if top:
        repos = {os.path.basename(top): top}
    else:
        # repo 清單讀錯時那些 repo 沒被掃，算成失敗（D15）
        try:
            sources = sync.source_paths(pathlib.Path(state))
        except ValueError as e:
            failed.append(sync.sources_message(e))
            sources = []
        found, conflicts, _, skipped = sync.scan_repos(pathlib.Path(code_root).resolve(), sources)
        repos = {n: str(p) for n, p in sorted(found.items())}
        failed += [sync.conflict_message(n, ps) for n, ps in conflicts.items()] + list(skipped.values())
    dispatch = jsonfile.load(os.path.join(state, "dispatch.json"))
    for name, path in repos.items():
        run_repo(name, path, bool(write), dispatch, out, failed)
    for row in out:
        print("\t".join(row))
    for f in failed:
        print("backfill: %s" % f, file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("用法：backfill.py <code root> <state dir> <write：1 或空字串> <repo 根或空字串>")
    sys.exit(main(*sys.argv[1:]))
