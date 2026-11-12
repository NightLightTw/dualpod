"""系統錄音（audiotee）這一段的音質：播已知的多音訊號，錄 audiotee 吐出的 44.1 kHz s16，扣掉理想正弦後算剩下的失真＋雜訊。
ALAC 到 HomePod 是無損（之前驗過逐位元相同），所以這一段就是我們這條路上唯一會動到聲音的地方。

  python tapquality.py gen <out.wav>             48 kHz 立體聲：997 Hz、5 kHz、12 kHz 各 −12 dBFS，6 秒
  python tapquality.py analyze <capture.raw>     audiotee 輸出（s16le 44.1 kHz 立體聲）
"""
import sys
import numpy as np
from scipy.io import wavfile

TONES = (997.0, 5000.0, 12000.0)
AMP = 10 ** (-12 / 20)


def gen(out, fs=48000, sec=6.0):
    t = np.arange(int(fs * sec)) / fs
    x = sum(AMP * np.sin(2 * np.pi * f * t) for f in TONES)
    wavfile.write(out, fs, (np.tile(x, (2, 1)).T * 32767).astype("<i2"))


def analyze(path, fs=44100):
    x = np.fromfile(path, "<i2").astype(float).reshape(-1, 2)[:, 0] / 32768
    on = np.flatnonzero(np.abs(x) > 0.05)
    x = x[on[0] + fs // 2: on[-1] - fs // 2]  # 去頭去尾半秒，避開起播與結尾
    t = np.arange(len(x)) / fs
    basis = np.column_stack([g(2 * np.pi * f * t) for f in TONES for g in (np.sin, np.cos)] + [np.ones_like(t)])
    coef, *_ = np.linalg.lstsq(basis, x, rcond=None)
    res = x - basis @ coef
    sig = np.sqrt(np.mean((basis @ coef) ** 2))
    print(f"長度 {len(x) / fs:.1f} s，訊號 {20 * np.log10(sig):.1f} dBFS，"
          f"失真＋雜訊比 {20 * np.log10(sig / np.sqrt(np.mean(res ** 2))):.1f} dB"
          f"（16-bit 理論上限約 98 dB）")
    spec = np.abs(np.fft.rfft(res * np.hanning(len(res))))
    fr = np.fft.rfftfreq(len(res), 1 / fs)
    top = np.argsort(spec)[-5:][::-1]
    print("殘差最大的頻率：" + "、".join(f"{fr[i]:.0f} Hz" for i in top))


if __name__ == "__main__":
    gen(sys.argv[2]) if sys.argv[1] == "gen" else analyze(sys.argv[2])
