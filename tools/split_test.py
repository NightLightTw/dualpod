# 用法：python3 -I tools/split_test.py <暫存資料夾> tools/stereotool（或舊的 tools/split.py）
# 自測 split：(1) L/R/LR 三種輸出的內容正確（開頭可能先補靜音，比對前先去掉）(2) --routes 即時改路由：換路由後
# 留下的輸出時間軸連續、被 X 的輸出不再收到資料也不卡住其他輸出
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
nxt = time.time()
for i in range(0, len(b), 3528):  # 和 tap 一樣每 20 ms 送一塊（照絕對時間，免得 sleep 誤差累積成補靜音）；一次全塞會被當成超前而丟掉
    nxt += 0.02
    pr.stdin.write(b[i:i + 3528]); pr.stdin.flush(); time.sleep(max(0, nxt - time.time()))
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


# (2) 即時改路由。每個 FIFO 另外留一個 O_RDWR（和 run_pair 一樣），所以 b 的讀端停了也不會 EPIPE，只會寫滿卡住
import select
names = ["a", "b", "m"]
fp = {k: f"{d}/rt-{k}" for k in names}
for p in fp.values():
    if os.path.exists(p): os.remove(p)
    os.mkfifo(p)
routes = f"{d}/routes"
def put_routes(text):
    with open(routes + ".tmp", "w") as f: f.write(text)
    os.rename(routes + ".tmp", routes)
put_routes(f"{fp['a']}:L {fp['b']}:R {fp['m']}:0")
holders = [os.open(p, os.O_RDWR) for p in fp.values()]
pr = subprocess.Popen([split, "split", "--routes", routes, f"{fp['a']}:L", f"{fp['b']}:R", f"{fp['m']}:0"],
                      stdin=subprocess.PIPE, stderr=subprocess.DEVNULL)
chunks = {k: [] for k in names}  # (收到時間, bytes)
stop = {k: False for k in names}
def rd(k):
    fd = os.open(fp[k], os.O_RDONLY | os.O_NONBLOCK)
    while not stop[k]:
        if select.select([fd], [], [], 0.05)[0]:
            try: b = os.read(fd, 65536)
            except BlockingIOError: continue
            if b: chunks[k].append((time.time(), b))
    os.close(fd)
threads = [threading.Thread(target=rd, args=(k,)) for k in names]
for t in threads: t.start()
time.sleep(0.2)
W = 32000
k0 = 0
def feed(secs):  # 照絕對時間送，不累積 sleep 的誤差，輸入才不會比牆鐘慢而被補靜音
    global k0
    nxt = time.time()
    for _ in range(int(secs / 0.02)):
        nxt += 0.02
        a = array.array("h")
        for k in range(k0, k0 + 882): a.extend([k % W + 1, -(k % W + 1)])
        k0 += 882
        pr.stdin.write(a.tobytes()); pr.stdin.flush(); time.sleep(max(0, nxt - time.time()))
feed(1.0)
t_switch = time.time()
put_routes(f"{fp['a']}:LR {fp['b']}:X {fp['m']}:LR")
threading.Timer(0.3, lambda: stop.__setitem__("b", True)).start()  # b 的讀端死掉；這段不能停餵，否則會被補靜音
feed(1.5)
t_end = time.time()
time.sleep(0.2)
stop["a"] = stop["m"] = True
for t in threads: t.join()
pr.kill()
def frames(k):
    a = array.array("h", b"".join(b for _, b in chunks[k])); return list(zip(a[0::2], a[1::2]))
fa, fb, fm = frames("a"), frames("b"), frames("m")
sw_a = next(i for i, (l, r) in enumerate(fa) if l != r)  # a 從 L 變 LR 的第一個 frame
sw_m = next(i for i, (l, r) in enumerate(fm) if l != 0 or r != 0)
assert sw_a == sw_m, f"a、m 切換點的 frame 數要一樣（同一條時間軸）：{sw_a} vs {sw_m}"
assert all(l == r and l >= 0 for l, r in fa[:sw_a]), "a 切換前是 L 複製成雙聲道"
assert all(f == (0, 0) for f in fm[:sw_m]), "m 切換前全是靜音"
assert all(r == -l and l >= 0 for l, r in fa[sw_a:]) and fa[sw_a:] == fm[sw_m:] and len(fa) == len(fm), "切換後 a、m 都是原樣立體聲且一模一樣"
assert all(l == r and l <= 0 for l, r in fb) and len(fb) == sw_a, f"b 只收到切換前的 R，之後什麼都沒有：{len(fb)} vs {sw_a}"
src_l = [l for l, _ in fa if l != 0]
assert all((y - x) % W == 1 for x, y in zip(src_l, src_l[1:])), "a 的樣本編號跨過切換仍連續（沒丟沒重複）"
after = [t for t, _ in chunks["a"] if t_switch < t < t_end]
gap = max(y - x for x, y in zip(after, after[1:]))
assert gap < 0.06, f"a 切換後的最大到達間隔 {gap:.3f}s"
print(f"split reroute self-test ok (switch at frame {sw_a}, b frames {len(fb)}, a gap {gap*1000:.0f} ms)")
