"""report.md 的 `## 邏輯表` 那一行是否對到 MR head。看板快照與 opsx merge 共用，兩邊才不會判斷不一樣。

review 寫的那一行是 `openspec/changes/<slug>/logic-map.md · <head sha 前 7 碼>`；`產表失敗：…` 與任何其他寫法都不算有表。
"""

import re

LINE = re.compile(r"openspec/changes/\S+/logic-map\.md · ([0-9a-f]{7,40})")


def line_of(report):
    """`## 邏輯表` 底下、下一個標題之前的第一個非空行；沒有這段或段裡是空的時 None。"""
    lines = report.split("\n")
    if "## 邏輯表" not in lines:
        return None
    for line in lines[lines.index("## 邏輯表") + 1:]:
        if line.startswith("#"):
            return None
        if line.strip():
            return line.strip()
    return None


def at_head(report, head_sha):
    """report：report.md 全文，沒有檔時 None；head_sha：MR head，forge 沒回時 None。"""
    if report is None or not head_sha:
        return False
    m = LINE.fullmatch(line_of(report) or "")
    return bool(m) and head_sha.startswith(m.group(1))
