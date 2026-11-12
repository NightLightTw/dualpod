"""跟 Apple Music 比同步用的測試音：每 1.0 s 一個 chirp（左右相同），前置 1.0 s，共 N 個；疊 200 Hz 導頻讓接收端不睡。
播放中途把一台靜音、換另一台出聲，就能在同一條時間軸上分別量兩台。

  python switchtest.py gen <out.wav> [N=40]
  python switchtest.py analyze <rec.wav> <first_sample_unix> <play_unix> <switch_index>
    switch_index 之前只有 A 台出聲、之後只有 B 台；換手前後各 2 個不用。
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt
sys.path.insert(0, __file__.rsplit("/", 2)[0])
from measure import chirp, envelope, events

LEAD, PERIOD = 1.0, 1.0


def gen(out, n=40, fs=48000):
    total = int((LEAD + PERIOD * n + 1.0) * fs)
    x = 0.02 * np.sin(2 * np.pi * 200 * np.arange(total) / fs)
    c = chirp(fs)
    for i in range(n):
        s = int((LEAD + i * PERIOD) * fs)
        x[s:s + len(c)] += c
    pcm = (np.tile(x, (2, 1)).T * 32767).astype("<i2")
    wavfile.write(out, fs, pcm)


def analyze(path, first_unix, play_unix, switch):
    fs, x = wavfile.read(path)
    x = x.astype(float)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = sosfiltfilt(butter(4, 1000, "highpass", fs=fs, output="sos"), x)
    ev, snr = events(envelope(x, chirp(fs)), fs)
    t = ev + first_unix - play_unix                      # 相對播放指令的秒數
    # 第 0 個 chirp：後面連續兩個間隔都接近 1 s 的第一個事件（之前的是起播雜音）
    d = np.diff(t)
    first = next(i for i in range(len(d) - 1) if abs(d[i] - PERIOD) < 0.02 and abs(d[i + 1] - PERIOD) < 0.02)
    idx = np.round((t - t[first]) / PERIOD).astype(int)  # 每個事件是第幾個 chirp
    ok = (idx >= 0) & (np.abs(t - t[first] - idx * PERIOD) < 0.1)
    t, idx = t[ok], idx[ok]
    a = (idx < switch - 2)
    b = (idx > switch + 2)
    # 兩段一起擬合：到達時間 = 截距 + 斜率×序號 + 差值×[B 段]，扣掉麥克風與播放端的時脈漂移
    X = np.column_stack([np.ones(a.sum() + b.sum()), np.r_[idx[a], idx[b]], np.r_[np.zeros(a.sum()), np.ones(b.sum())]])
    y = np.r_[t[a], t[b]] - LEAD - np.r_[idx[a], idx[b]] * PERIOD
    coef, *_ = np.linalg.lstsq(X, y, rcond=None)
    res = y - X @ coef
    print(f"事件 {len(ev)} 個，A 段 {a.sum()}、B 段 {b.sum()} 個，峰值/中位數 {snr:.0f}")
    print(f"延遲（A 台，播放指令→麥克風）{(coef[0]) * 1000:.0f} ms")
    print(f"B 減 A {coef[2] * 1000:+.2f} ms，殘差標準差 {res.std() * 1000:.2f} ms，漂移 {coef[1] * 1000:+.3f} ms/s")


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 40)
    else:
        analyze(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5]))
