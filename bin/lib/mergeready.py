"""一張卡算不算「可以合併」，collect、opsx merge 與 Stop hook 共用。只看傳進來的值，不讀檔、不跑指令。

blockers(...) 回傳沒過的條件，空清單才是可以合併：
  MR 五條件全綠（mr.state 是 ready）
  agent 沒在改：主殼與子殼都沒有 open gate，pane 不是 working 或 blocked（unknown、done、讀不到都不擋）
  card_blockers(...) 的三條，只看卡目錄：
    邏輯表對應 MR 最新 head：卡目錄有 logic-map.md，report.md `## 邏輯表` 那一行的 sha（7 碼以上）是 MR head 的開頭
    邏輯表沒經過決定的項都處理了：logic-map.md 每一段 `### ⚠ 要看的地方` 的「沒經過決定」項（未分類表是 bug、程式整理以外的每一項）行尾都是「· 開卡 <slug>」或「· gate <id>」，
      而且那個 gate 在 gates.md 裡開著或已經寫回
    review 留給人決定的項處理完：`### 待修（範圍內）` 沒有項目，`### Consider` 每一項行尾都是「· 開卡 <slug>」或「· 接受」
"""
import re

NOT_READY = "MR 五條件沒全綠"
OPEN_GATE = "有 open gate"
WORKING = "agent 還在改（pane working）"
WAITING_INPUT = "agent 在終端機等輸入（pane blocked）"
STALE_MAP = "邏輯表不是 MR 最新 head"
UNHANDLED_MAP = "邏輯表有沒經過決定的項目沒處理"
OPEN_REVIEW = "report.md 有留給人決定的項目"

HANDLED = re.compile(r"· (開卡 \S+|接受)\s*$")
MAP_HANDLED = re.compile(r"· (開卡|gate) (\S+)\s*$")
MAP_HEADING = "### ⚠ 要看的地方"
UNSORTED = "沒有 design.md，未分類"
MAP_LINE = re.compile(r"^openspec/changes/(\S+)/logic-map\.md · ([0-9a-f]{7,40})$")


def agent_status_of(agents, pane):
    """herdr agent list 裡 pane_id 對到 pane 的 agent_status；agents 是 None（herdr 讀不到）時回 None，對不到時回 unknown。"""
    if agents is None:
        return None
    hit = [a for a in agents if str(a.get("pane_id")) == str(pane)]
    return (hit[0].get("agent_status") or "unknown") if hit else "unknown"


def section_lines(report, heading):
    """heading 那一行底下、到下一個標題之前的非空行，保留行首縮排；沒有這個標題時回 []。"""
    lines = report.split("\n")
    head = next((i for i, l in enumerate(lines) if l.strip() == heading), None)
    if head is None:
        return []
    out = []
    for l in lines[head + 1:]:
        if l.startswith("#"):
            break
        if l.strip():
            out.append(l.rstrip())
    return out


def logic_map_line(report):
    """report.md `## 邏輯表` 底下第一個非空行；沒有這一段，或段裡沒有字時回 None。"""
    got = section_lines(report, "## 邏輯表")
    return got[0].strip() if got else None


def map_matches(slug, line, head_sha):
    m = MAP_LINE.match(line or "")
    return bool(m and m[1] == slug and head_sha and head_sha.startswith(m[2]))


def open_review_items(report):
    """行首沒有縮排的 `- ` 才是一項；縮排的子項目屬於上一項。"""
    pending = [l for l in section_lines(report, "### 待修（範圍內）") if l.startswith("- ")]
    consider = [l for l in section_lines(report, "### Consider") if l.startswith("- ") and not HANDLED.search(l)]
    return pending + consider


def map_sections(map_text):
    """每一段 `### ⚠ 要看的地方`（每個功能一段，標題去頭尾空白比對）底下、到下一個標題之前的非空行，保留行首縮排。"""
    out = []
    cur = None
    for l in map_text.split("\n"):
        if l.strip() == MAP_HEADING:
            cur = []
            out.append(cur)
        elif l.startswith("#"):
            cur = None
        elif cur is not None and l.strip():
            cur.append(l.rstrip())
    return out


def settled_gates(gates_text):
    """gates.md 裡開著、或答了而且有「寫回:」行的 gate id。答了還沒寫回的不算：答案還沒進 design.md。"""
    out = set()
    for block in ("\n" + gates_text).split("\n## ")[1:]:
        lines = block.split("\n")
        if any(l.strip() == "status: open" for l in lines) or any(l.startswith("寫回:") for l in lines):
            out.add(lines[0].strip())
    return out


def unhandled_map_items(map_text, gates_text):
    """行首沒有縮排的 `- ` 才是一項，只寫「- 無」的不算。任一段的第一行是「沒有 design.md，未分類」時整張表都是未分類，
    bug、程式整理以外的每一項都要標記；否則只看「沒經過決定」項。「· gate <id>」要 settled_gates 裡有那個 id 才算處理過。"""
    sections = map_sections(map_text)
    unsorted = any(s and s[0].strip() == UNSORTED for s in sections)
    settled = settled_gates(gates_text)
    out = []
    for s in sections:
        items = [l for l in s if l.startswith("- ") and l.strip() != "- 無"]
        if unsorted:
            need = [l for l in items if not l.startswith(("- bug：", "- 程式整理"))]
        else:
            need = [l for l in items if l.startswith("- 沒經過決定")]
        for l in need:
            m = MAP_HANDLED.search(l)
            if not m or (m[1] == "gate" and m[2] not in settled):
                out.append(l)
    return out


def card_blockers(slug, report, map_text, gates_text, head_sha):
    """map_text 是卡目錄 logic-map.md 的全文，沒有這個檔時是 None；gates_text 是 gates.md 的全文，沒有這個檔時是空字串。"""
    out = []
    if map_text is None or not map_matches(slug, logic_map_line(report), head_sha):
        out.append(STALE_MAP)
    if map_text is not None and unhandled_map_items(map_text, gates_text):
        out.append(UNHANDLED_MAP)
    if open_review_items(report):
        out.append(OPEN_REVIEW)
    return out


def blockers(slug, mr, has_open_gate, agent_status, report, map_text, gates_text):
    out = []
    if not mr or mr.get("state") != "ready":
        out.append(NOT_READY)
    if has_open_gate:
        out.append(OPEN_GATE)
    if agent_status == "working":
        out.append(WORKING)
    if agent_status == "blocked":
        out.append(WAITING_INPUT)
    return out + card_blockers(slug, report, map_text, gates_text, mr.get("head_sha") if mr else None)
