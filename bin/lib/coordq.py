"""送給協調者 session 的事件先看它的輸入框：空的就送，有字或看不出來就排進 <state>/coordinator-queue，空了再合成一則送。

herdr agent prompt 不看輸入框，直接打字加 enter，使用者打到一半的字會跟事件一起送出。
bash 的 coordinator_say 走命令列，coordinate 直接 import；兩邊共用這裡的判讀與佇列，才不會判得不一樣。
執行器由呼叫者傳入：run 給唯讀的 get 與讀畫面，act 給送 prompt（coordinate 的 act 會記 log）。都回 (rc, stdout, stderr)。
用法：coordq.py say <state dir> <一行> | coordq.py flush <state dir>
規則：openspec/specs/opsx-coordinate/spec.md「協調者輸入框有字時事件排隊，空了合成一則送出」。
"""
import fcntl
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import runtime  # noqa: E402
import safefile  # noqa: E402

COORDINATOR = "opsx-coordinator"
# herdr 收不下 prompt 的兩種情形：沒有這個 agent、或它卡在對話框。呼叫者各有退路，不排隊
UNAVAILABLE = ("agent_not_found", "agent_blocked")
QUEUE = "coordinator-queue"
SENDING = QUEUE + ".sending."
LOCK = QUEUE + ".lock"
RULE = re.compile(r"^\s*─{3,}\s*$")
PROMPT = "❯"
SGR = re.compile(r"\x1b\[([0-9;]*)m")


def run(argv):
    p = subprocess.run(argv, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def dim_flag(params, dim):
    """一個 SGR 序列套用後的 dim 狀態。38、48 的參數（38;2;r;g;b、38;5;n）要整段跳過，裡面的 2 不是 dim。"""
    codes = params.split(";") if params else ["0"]
    i = 0
    while i < len(codes):
        code = codes[i]
        if code in ("38", "48"):
            i += 5 if i + 1 < len(codes) and codes[i + 1] == "2" else 3
            continue
        if code in ("0", ""):
            dim = False
        elif code == "2":
            dim = True
        elif code == "22":
            dim = False
        i += 1
    return dim


def bright_text(line):
    """去掉 ANSI 色碼，也去掉 dim 的字。Claude Code 空輸入框裡的提示字（Press up to edit queued messages）是 dim。"""
    out, dim, pos = [], False, 0
    for m in SGR.finditer(line):
        if not dim:
            out.append(line[pos:m.start()])
        dim = dim_flag(m.group(1), dim)
        pos = m.end()
    if not dim:
        out.append(line[pos:])
    return "".join(out)


def box_text(screen):
    """Claude Code 的輸入框是兩條 ─ 橫線夾住、第一行以 ❯ 開頭。只看畫面最下面那一個框。
    畫面是 --format ansi：dim 的提示字不算使用者打的字。
    回框裡的字（折行接起來），找不到這樣的框（在對話框裡、或不是 Claude Code）回 None。"""
    lines = [bright_text(line) for line in screen.splitlines()]
    rules = [i for i, line in enumerate(lines) if RULE.match(line)]
    if len(rules) < 2:
        return None
    body = lines[rules[-2] + 1:rules[-1]]
    if not body or not body[0].lstrip().startswith(PROMPT):
        return None
    return body[0].lstrip()[len(PROMPT):] + "".join(body[1:])


def box_state(screen):
    """回 empty、typed，或 unknown（找不到輸入框）。"""
    text = box_text(screen)
    if text is None:
        return "unknown"
    return "typed" if text.strip() else "empty"


def look(read):
    """回 (empty | typed | unknown | unavailable | error, herdr 的錯)。讀不到畫面算 unknown：寧可晚送，不搶使用者打字。
    agent get 本身失敗是 error，不排隊：herdr 叫不通時呼叫者會重試同一則，排了就會跟重試的那則重複送。"""
    rc, out, err = read(runtime.get(agent=COORDINATOR))
    if rc != 0:
        if any(code in out + err for code in UNAVAILABLE):
            return "unavailable", (err or out).strip()
        return "error", (err or out).strip()
    try:
        agent = json.loads(out)["result"]["agent"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return "unknown", "herdr agent get 讀不懂：%s" % out.strip()[:200]
    if agent.get("agent_status") == "blocked":
        return "unavailable", "agent_blocked（%s 卡在對話框）" % COORDINATOR
    if not agent.get("pane_id"):
        return "unknown", "herdr agent get 沒有 pane_id"
    rc, out, err = read(runtime.screen(agent["pane_id"]))
    if rc != 0:
        return "unknown", (err or out).strip()
    return box_state(out), ""


def one_line(text):
    return " ".join(text.splitlines())


def merge(lines):
    if len(lines) == 1:
        return lines[0]
    return "排隊 %d 則：%s" % (len(lines), "；".join(lines))


def queue_lock(state):
    """寫入與取走佇列共用的獨占鎖，關掉檔就放掉。沒有它，寫入者開了檔之後、寫入之前，佇列可能已被換名讀走，
    寫進去的那則會跟著批次檔被刪掉。只包住檔案操作，不包 herdr 呼叫。"""
    f = safefile.open_lock(os.path.join(state, LOCK))
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def append(state, lines):
    with queue_lock(state), safefile.open_append(os.path.join(state, QUEUE)) as f:
        f.write("".join(line + "\n" for line in lines))


def pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def take(state):
    """把佇列換名成自己的補送批次（rename 是原子的，同時補送的人只有一個拿得到），再撿回已經不在的程序留下的批次。
    回 (事件, 批次檔)；殘留的批次排在前面，因為它們比佇列裡的舊。"""
    with queue_lock(state):
        return take_locked(state)


def take_locked(state):
    files = []
    for path in sorted(glob.glob(os.path.join(state, SENDING + "*"))):
        pid = path.rsplit(".", 1)[1]
        if pid.isdigit() and not pid_alive(int(pid)):
            mine = "%s.%d" % (path, os.getpid())
            try:
                os.rename(path, mine)
            except FileNotFoundError:
                continue
            files.append(mine)
    own = os.path.join(state, SENDING + str(os.getpid()))
    try:
        os.rename(os.path.join(state, QUEUE), own)
        files.append(own)
    except FileNotFoundError:
        pass
    lines = []
    for path in files:
        with open(path, encoding="utf-8") as f:
            lines += [line for line in f.read().splitlines() if line]
    return lines, files


def done(files):
    for path in files:
        os.remove(path)


def give_back(state, lines, files):
    """送不出去：事件寫回佇列再刪批次檔。中間被殺最多重送一次，不會丟。"""
    if lines:
        append(state, lines)
    done(files)


def has_queued(state):
    return os.path.exists(os.path.join(state, QUEUE)) or bool(glob.glob(os.path.join(state, SENDING + "*")))


def send(state, new, read, act):
    """輸入框空時把佇列與 new（可為空清單）合成一則送出。回 (sent | queued | unavailable | error, herdr 的錯)。
    new 送不出去時不寫進佇列，交回呼叫者照原本的方式重試；只有輸入框有字或看不出來時才排隊。"""
    state_now, why = look(read)
    if state_now in ("unavailable", "error"):
        return state_now, why
    if state_now != "empty":
        if new:
            append(state, new)
        return "queued", why
    lines, files = take(state)
    if not lines + new:
        done(files)
        return "sent", ""
    rc, out, err = act(runtime.prompt(merge(lines + new), "nowait", agent=COORDINATOR))
    if rc == 0:
        done(files)
        return "sent", ""
    give_back(state, lines, files)
    why = (err or out).strip()
    return ("unavailable" if any(code in why for code in UNAVAILABLE) else "error"), why


def say(state, line, read=run, act=run):
    return send(state, [one_line(line)], read, act)


def flush(state, read=run, act=run):
    """佇列空時不讀畫面，不多叫 herdr。"""
    if not has_queued(state):
        return "sent", ""
    return send(state, [], read, act)


def main(argv):
    if len(argv) == 4 and argv[1] == "say":
        result, why = say(argv[2], argv[3])
    elif len(argv) == 3 and argv[1] == "flush":
        result, why = flush(argv[2])
    else:
        print("usage: coordq.py say <state dir> <一行> | coordq.py flush <state dir>", file=sys.stderr)
        return 64
    print(result)
    if why:
        print(why, file=sys.stderr)
    return 0 if result in ("sent", "queued") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
