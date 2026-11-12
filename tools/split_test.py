# 用法：python3 -I tools/split_test.py <暫存資料夾> tools/stereotool（或舊的 tools/split.py）
# 自測 split.py：L/R/LR 三種輸出的內容正確（開頭可能先補靜音，比對前先去掉）
import os, subprocess, sys, array, threading, time
d, split = sys.argv[1], sys.argv[2]
paths = [f"{d}/sp-{n}" for n in "abc"]
for p in paths:
    if os.path.exists(p): os.remove(p)
    os.mkfifo(p)
n = 4410
src = array.array("h")
for k in range(1, n + 1): src.extend([k, -k])  # L=k, R=-k
cmd = [sys.executable, "-I", split] if split.endswith(".py") else [split, "split"]  # split.py 或 stereotool
pr = subprocess.Popen(cmd + [paths[0] + ":L", paths[1] + ":R", paths[2] + ":LR"],
                      stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
got = [b"", b"", b""]
def reader(i):
    fd = os.open(paths[i], os.O_RDONLY)
    end = time.time() + 1.5
    while time.time() < end:
        try: got[i] += os.read(fd, 65536)
        except BlockingIOError: pass
threads = [threading.Thread(target=reader, args=(i,)) for i in range(3)]
for t in threads: t.start()
time.sleep(0.2)
b = src.tobytes()
for i in range(0, len(b), 3528):  # 和 tap 一樣每 20 ms 送一塊；一次全塞會被當成超前而丟掉
    pr.stdin.write(b[i:i + 3528]); pr.stdin.flush(); time.sleep(0.02)
for t in threads: t.join()
pr.kill()
def body(b):
    a = array.array("h", b[: len(b) // 2 * 2]); i = 0
    while i < len(a) and a[i] == 0: i += 1
    return list(a[i: i + len(src)])
L, R = list(src[0::2]), list(src[1::2])
dup = lambda x: [v for v in x for _ in (0, 1)]
assert body(got[0]) == dup(L), "L"
assert body(got[1]) == dup(R), "R"
assert body(got[2]) == list(src), "LR"
print("split self-test ok")
