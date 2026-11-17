"""一張卡算不算「可以合併」，collect、opsx merge 與 Stop hook 共用。只看傳進來的值，不讀檔、不跑指令。

blockers(...) 回傳沒過的條件，空清單才是可以合併：
  MR 五條件全綠（mr.state 是 ready）
  agent 沒在改：卡上沒有 open gate，pane 不是 working（unknown、done、讀不到都不算 working）
  card_blockers(...) 的兩條，只看卡目錄：
    邏輯表對應 MR 最新 head：卡目錄有 logic-map.md，report.md `## 邏輯表` 那一行的 sha 等於 MR head sha 的前 7 碼
    review 留給人決定的項處理完：`### 待修（範圍內）` 沒有項目，`### Consider` 每一項都標了「開卡 <slug>」或「接受」
"""
import re

NOT_READY = "MR 五條件沒全綠"
OPEN_GATE = "有 open gate"
WORKING = "agent 還在改（pane working）"
STALE_MAP = "邏輯表不是 MR 最新 head"
OPEN_REVIEW = "report.md 有留給人決定的項目"

HANDLED = re.compile(r"開卡 \S+|接受")


def section_lines(report, heading):
    """heading 那一行底下、到下一個標題之前的非空行；沒有這個標題時回 []。"""
    lines = report.split("\n")
    head = next((i for i, l in enumerate(lines) if l.strip() == heading), None)
    if head is None:
        return []
    out = []
    for l in lines[head + 1:]:
        if l.startswith("#"):
            break
        if l.strip():
            out.append(l.strip())
    return out


def logic_map_line(report):
    """report.md `## 邏輯表` 底下第一個非空行；沒有這一段，或段裡沒有字時回 None。"""
    got = section_lines(report, "## 邏輯表")
    return got[0] if got else None


def map_matches(slug, line, head_sha):
    if not line or not head_sha or len(head_sha) < 7:
        return False
    return line == "openspec/changes/%s/logic-map.md · %s" % (slug, head_sha[:7])


def open_review_items(report):
    pending = [l for l in section_lines(report, "### 待修（範圍內）") if l.startswith("- ")]
    consider = [l for l in section_lines(report, "### Consider") if l.startswith("- ") and not HANDLED.search(l)]
    return pending + consider


def card_blockers(slug, report, map_exists, head_sha):
    out = []
    if not map_exists or not map_matches(slug, logic_map_line(report), head_sha):
        out.append(STALE_MAP)
    if open_review_items(report):
        out.append(OPEN_REVIEW)
    return out


def blockers(slug, mr, has_open_gate, agent_status, report, map_exists):
    out = []
    if not mr or mr.get("state") != "ready":
        out.append(NOT_READY)
    if has_open_gate:
        out.append(OPEN_GATE)
    if agent_status == "working":
        out.append(WORKING)
    return out + card_blockers(slug, report, map_exists, mr.get("head_sha") if mr else None)
