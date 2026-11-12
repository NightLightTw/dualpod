"""左右偏差與端到端延遲量測。chirp、matched filter、拋物線內插、扣漂移後取中位數都照 Windows 端 stereo_sync2.py。

  python measure.py gen <out_dir>                              產生 chirps.raw（44.1 kHz s16le 立體聲，餵 cliairplay）與 chirps.wav（48 kHz，給 afplay）
  python measure.py analyze <rec.wav> [first_sample_unix play_unix]  算右減左偏差；給了兩個時間就再算端到端延遲

訊號：前置 1.0 s，之後每 1.0 s 一對 10 ms chirp（1.5→6 kHz，兩邊同一個），左在 +0.0 s、右在 +0.3 s，共 30 對。
全程疊 0.02 振幅 200 Hz，避免接收端在靜音時休眠。
和 Windows 唯一的差別是左右間距 0.3 s（Windows 是 0.5 s 交替）：間距不對稱，只靠時間就分得出左右，
不必假設延遲 < 0.5 s。曾試過左右用上行／下行 chirp 來分，但在有回音的房間裡兩者的相關值只差 1.2 倍，分不出來。
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, correlate, find_peaks, hilbert, sosfiltfilt

LEAD, PERIOD, R_OFF, PAIRS, CH_LEN = 1.0, 1.0, 0.3, 30, 0.010


def chirp(fs):
    t = np.arange(int(CH_LEN * fs)) / fs
    return 0.5 * np.hanning(len(t)) * np.sin(2 * np.pi * (1500.0 * t + 0.5 * 450000.0 * t * t))


def signal(fs):
    total = int((LEAD + PERIOD * PAIRS + 1.0) * fs)
    t = np.arange(total) / fs
    out = np.tile(0.02 * np.sin(2 * np.pi * 200 * t), (2, 1))
    c = chirp(fs)
    for i in range(PAIRS):
        for ch, off in ((0, 0.0), (1, R_OFF)):
            s = int((LEAD + i * PERIOD + off) * fs)
            out[ch, s:s + len(c)] += c
    return out.T


def gen(out_dir):
    for fs, name in ((44100, "chirps.raw"), (48000, "chirps.wav")):
        pcm = (signal(fs) * 32767).astype("<i2")
        if name.endswith(".raw"):
            pcm.tofile(f"{out_dir}/{name}")
        else:
            wavfile.write(f"{out_dir}/{name}", fs, pcm)


def envelope(x, tpl):
    a = correlate(x, tpl, mode="valid")
    b = correlate(x, np.imag(hilbert(tpl)), mode="valid")
    return np.hypot(a, b)


def events(env, fs):
    """所有 chirp：高於門檻、彼此相隔 ≥ 0.15 s 的局部最大值，再做三點拋物線內插。"""
    idx, _ = find_peaks(env, height=0.3 * np.percentile(env, 99.9), distance=int(0.15 * fs))
    idx = idx[(idx > 0) & (idx < len(env) - 1)]
    y0, y1, y2 = env[idx - 1], env[idx], env[idx + 1]
    den = y0 - 2 * y1 + y2
    d = np.where(den != 0, 0.5 * (y0 - y2) / np.where(den != 0, den, 1), 0.0)
    snr = np.median(env[idx]) / np.median(env) if len(idx) else 0.0
    return (idx + d) / fs, snr


def pair_up(ev):
    """後面 0.3 s（±50 ms）有另一個事件的就是左，那個事件是它配對的右。"""
    left, right = [], []
    for i, t in enumerate(ev):
        nxt = ev[i + 1:i + 3]
        hit = nxt[abs(nxt - t - R_OFF) < 0.05]
        if len(hit):
            left.append(t)
            right.append(hit[0])
    return np.array(left), np.array(right)


def analyze(path, first_sample_unix=None, play_unix=None):
    fs, x = wavfile.read(path)
    x = x.astype(float)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = sosfiltfilt(butter(4, 1000, "highpass", fs=fs, output="sos"), x)  # 去掉 200 Hz 導頻；零相位，不改到達時間
    ev, snr = events(envelope(x, chirp(fs)), fs)
    left, right = pair_up(ev)
    print(f"錄音 {len(x)/fs:.1f} s @ {fs} Hz，事件 {len(ev)} 個，配成 {len(left)} 對，峰值/中位數 {snr:.0f}")
    if snr < 5 or len(left) < 10:
        sys.exit("錄音裡沒抓到足夠的 chirp 對，結果不可信：檢查麥克風權限、音量或距離")
    d = np.diff(left)
    d = d[abs(d - PERIOD) < 0.05]  # 相鄰左 chirp 的間隔，漏抓造成的怪間隔不算
    slip = np.median(d) / PERIOD - 1.0  # 每秒漂移（s/s）
    off_ms = (right - (left + R_OFF * (1 + slip))) * 1000
    print(f"漂移 {slip*1000:+.3f} ms/s")
    print(f"右減左（R − L）中位數 {np.median(off_ms):+.2f} ms，範圍 {off_ms.min():+.2f} 到 {off_ms.max():+.2f} ms，n={len(off_ms)}")
    print("逐對：", " ".join(f"{v:+.1f}" for v in off_ms))
    if first_sample_unix and play_unix:
        # 端到端延遲（同 Windows 定義）：播放呼叫 → 左 chirp 到達麥克風。用播放時間編號，假設延遲 < 1 s
        since = float(first_sample_unix) + left - (float(play_unix) + LEAD)
        since = since[since > 0]
        lat = (since - np.floor(since / PERIOD) * PERIOD) * 1000
        print(f"端到端延遲（左）中位數 {np.median(lat):.0f} ms，範圍 {lat.min():.0f}–{lat.max():.0f} ms，n={len(lat)}")


if __name__ == "__main__":
    {"gen": gen, "analyze": analyze}[sys.argv[1]](*sys.argv[2:])
