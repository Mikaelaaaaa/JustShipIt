"""送給卡的話送出後看輸入框：框裡還是剛送的那句，表示 Enter 沒送到，補按一次。

herdr agent prompt 打字加 Enter，偶爾 Enter 丟了，字就一直留在 Claude Code 的輸入框。
bash 的 runtime_prompt（nowait）與 drive 的 agent_prompt_stalled 走命令列，coordinate 直接 import。
執行器由呼叫者傳入：read 給讀畫面，act 給按 Enter（coordinate 的 act 會記 log）。都回 (rc, stdout, stderr)。
用法：submit.py check <state dir> <卡片身分> <剛送的一行>
規則：openspec/specs/prompt-submit-check/spec.md。
"""
import datetime
import functools
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import coordq  # noqa: E402
import jsonfile  # noqa: E402
import runtime  # noqa: E402


def run(argv):
    p = subprocess.run(argv, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def delay():
    """送出到讀畫面之間等幾秒，讓輸入框來得及重畫；測試設 0。"""
    raw = os.environ.get("OPSX_SUBMIT_SLEEP", "1")
    try:
        secs = float(raw)
    except ValueError as e:
        raise ValueError("OPSX_SUBMIT_SLEEP 要是秒數，收到：%r" % raw) from e
    if secs < 0:
        raise ValueError("OPSX_SUBMIT_SLEEP 不能是負的，收到：%r" % raw)
    return secs


def same(box, text):
    """框裡的字是不是這句：去掉所有空白後完全相同（長句折行會多出空白）。前面相同但多了字的不算。"""
    want = "".join(text.split())
    return box is not None and bool(want) and "".join(box.split()) == want


def box(pane, read):
    """pane 輸入框裡的字；讀不到畫面或找不到輸入框回 None。"""
    rc, out, _ = read(runtime.screen(pane))
    return coordq.box_text(out) if rc == 0 else None


def remember(d, key, text, at):
    """jsonfile.update 的 mutate：有 pane 的條目記下剛送的話與送出時刻（ISO 字串）。讀與寫之間條目可能被拿掉。"""
    entry = d.get(key)
    if entry and entry.get("pane"):
        entry["last_prompt"] = text
        entry["last_prompt_at"] = at


def forget(d, sent):
    """jsonfile.update 的 mutate：sent 是 {條目 key: 那句}。條目的 last_prompt 還是那句才清（連同時刻）；之後又送了別句的留著。"""
    for key, text in sent.items():
        entry = d.get(key)
        if entry and entry.get("last_prompt") == text:
            del entry["last_prompt"]
            entry.pop("last_prompt_at", None)


def check(state, key, text, read, act, sleep):
    """剛對卡 key 送出 text 之後叫：記 last_prompt、看輸入框，框裡是這句就補一次 Enter 再看。
    回 (結果, pane)。結果是 sent（框裡不是這句）、entered（補了 Enter 送出去了）、stuck（補了仍在）、
    unknown（沒有 pane 或讀不出輸入框）；sent 與 entered 清掉 last_prompt，另外兩種留給 coordinate 的 sweep。"""
    path = os.path.join(state, "dispatch.json")
    pane = (jsonfile.load(path).get(key) or {}).get("pane")
    if not pane:
        return "unknown", None
    at = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    jsonfile.update(path, functools.partial(remember, key=key, text=text, at=at))
    sleep(delay())
    first = box(pane, read)
    if first is None:
        return "unknown", pane
    result = "sent"
    if same(first, text):
        act(runtime.send_enter(pane))
        sleep(delay())
        after = box(pane, read)
        if after is None:
            return "unknown", pane
        if same(after, text):
            return "stuck", pane
        result = "entered"
    jsonfile.update(path, functools.partial(forget, sent={key: text}))
    return result, pane


def nudge(pane, texts, read, act, sleep):
    """coordinate 每輪替閒著的 pane 看一次輸入框。texts 是這個 pane 上各條目的 {key: last_prompt}。
    框裡是其中一句才按 Enter，等一下再看一次。回 (結果, 對上的 {key: 那句})；結果是 none（沒對上、沒按）、
    entered（框裡不再是那句）、stuck（還是那句）、unknown（按了之後讀不到輸入框）。"""
    current = box(pane, read)
    matched = {key: text for key, text in texts.items() if same(current, text)}
    if not matched:
        return "none", matched
    act(runtime.send_enter(pane))
    sleep(delay())
    after = box(pane, read)
    if after is None:
        return "unknown", matched
    if any(same(after, text) for text in matched.values()):
        return "stuck", matched
    return "entered", matched


def main(argv):
    if len(argv) != 5 or argv[1] != "check":
        print("usage: submit.py check <state dir> <卡片身分> <剛送的一行>", file=sys.stderr)
        return 64
    state, key, text = argv[2:]
    result, pane = check(state, key, text, run, run, time.sleep)
    if result == "stuck":
        print("opsx: %s 的 pane %s 補按了 Enter，輸入框仍是剛送的「%s」，到 pane 看一下" % (key, pane, text), file=sys.stderr)
    print(result)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
