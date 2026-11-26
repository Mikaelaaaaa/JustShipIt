"""dispatch.json 的 drive_pid 指的程序是不是這張卡的 drive。

drive 被 SIGKILL 或重開機後 pid 會留著，之後可能被別的程序重用，所以只看 signal 0 不夠，還要比對命令列。
比對規則跟 route.sh 的 drive_pid_state 一樣：命令列含 `/opsx drive <slug>`，slug 後面接空格或結尾。
"""
import os
import subprocess

GONE = "gone"
MINE = "mine"
OTHER = "other"
UNKNOWN = "unknown"


def state(pid, slug):
    """回 (狀態, 命令列)，狀態是 GONE、MINE、OTHER、UNKNOWN 之一。
    沒有權限送 signal 的程序（重開機後常是 root 程序拿到這個 pid）一樣要讀命令列。
    沙盒裡 ps 跑不起來時回 UNKNOWN：分不出來，呼叫端不能把它當成死掉。"""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return GONE, ""
    except PermissionError:
        pass
    try:
        r = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True)
    except (PermissionError, FileNotFoundError):
        return UNKNOWN, ""
    cmd = r.stdout.strip()
    if r.returncode != 0 or not cmd:
        return UNKNOWN, ""
    if ("/opsx drive %s " % slug) in cmd + " ":
        return MINE, cmd
    return OTHER, cmd
