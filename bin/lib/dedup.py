"""收件匣判過重複的記號：lead 判完的卡蓋 dedup_checked，coordinate 只補有記號的卡。specs/inbox-dedup-stamp。

用法：
    $OPSX_PY -I dedup.py stamp <top> <ISO 時間> <slug>…
        每張卡的 inbox.md frontmatter 寫 dedup_checked: <ISO 時間>（已有就換掉）。先驗每張卡都在、有 frontmatter、沒有 tasks.md，
        任何一張不合格就退出 1、stderr 點名，一張都不寫。
    $OPSX_PY -I dedup.py candidates <top> < <opsx collect 的 JSON>
        <top> 裡每張沒有記號的 P0/P1 收件匣卡印一行 <slug><TAB><跟它提到同一個檔案的其他收件匣卡，逗號分隔>。
"""
from __future__ import annotations

import json
import operator
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inboxmerge  # noqa: E402
import mergematch  # noqa: E402
import safefile  # noqa: E402

KEY = "dedup_checked"


def check(top: str, slug: str) -> str:
    """卡能蓋記號時回 None，不能時回原因。"""
    card_dir = os.path.join(top, "openspec", "changes", slug)
    inbox = os.path.join(card_dir, "inbox.md")
    if not os.path.isfile(inbox):
        return "沒有這張卡（%s 不存在）" % inbox
    if os.path.exists(os.path.join(card_dir, "tasks.md")):
        return "已有 tasks.md，不在收件匣"
    with open(inbox, encoding="utf-8") as f:
        text = f.read()
    try:
        inboxmerge.rewrite_frontmatter(text, {KEY: "x"}, inbox)
    except ValueError as e:
        return str(e)
    return None


def stamp(top: str, when: str, slugs: list) -> None:
    reasons = {s: check(top, s) for s in slugs}
    bad = [s for s in slugs if reasons[s]]
    if bad:
        for s in bad:
            print("dedup: %s：%s" % (s, reasons[s]), file=sys.stderr)
        sys.exit(1)
    for s in slugs:
        card_dir = os.path.join(top, "openspec", "changes", s)
        inbox = os.path.join(card_dir, "inbox.md")
        with safefile.CardLock(card_dir):
            with open(inbox, encoding="utf-8") as f:
                text = f.read()
            safefile.write_atomic(inbox, inboxmerge.rewrite_frontmatter(text, {KEY: when}, inbox))


def candidates(top: str, data: dict) -> list:
    real = os.path.realpath(top)
    repos = [r for r, p in data["repo_paths"].items() if os.path.realpath(p) == real]
    inbox = [c for c in data["cards"] if c["repo"] in repos and c["section"] == "收件匣"]
    files = {}
    for c in inbox:
        with open(os.path.join(c["path"], "inbox.md"), encoding="utf-8") as f:
            files[c["slug"]] = mergematch.files_in(top, mergematch.card_text(f.read()))
    lines = []
    for c in sorted(inbox, key=operator.itemgetter("slug")):
        if c["dedup_checked"] or not c["priority"] or c["priority"]["level"] not in ("P0", "P1"):
            continue
        same = sorted(o for o in files if o != c["slug"] and files[o] & files[c["slug"]])
        lines.append("%s\t%s" % (c["slug"], ",".join(same)))
    return lines


def main() -> None:
    args = sys.argv[1:]
    if len(args) >= 4 and args[0] == "stamp":
        stamp(args[1], args[2], args[3:])
    elif len(args) == 2 and args[0] == "candidates":
        for line in candidates(args[1], json.load(sys.stdin)):
            print(line)
    else:
        sys.exit("用法：dedup.py stamp <top> <ISO 時間> <slug>… | candidates <top> < <collect JSON>")


if __name__ == "__main__":
    main()
