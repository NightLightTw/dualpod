// Auto-align the Mac's speakers to the HomePods with the built-in microphone.
//
// The Mac speakers sit next to the mic and drown the HomePods out, and when the two are aligned their sounds
// overlap and can't be told apart. So, like the manual calibration: shift the Mac 40 ms late on purpose, turn
// the Mac's volume down, play short chirps (a sweep has one sharp correlation peak; the test chime repeats every
// few ms and can't be timed), and measure how far behind the HomePods the Mac lands. If it lands D ms behind with
// a 40 ms shift, the offset that lines them up is 40 − D.
import AVFoundation
import Accelerate
import AppKit

final class AutoAlign {
    static let probeMs = 40
    let fs = 44100.0
    let count = 20  // chirps, one per second
    var onStatus: (String) -> Void = { _ in }
    private var player: AVAudioPlayer?
    private let engine = AVAudioEngine()

    /// 10 ms sweep 1.5→6 kHz under a Hann window; `quad` is the 90° copy for a phase-free envelope
    static func chirp(_ fs: Double, quad: Bool = false) -> [Float] {
        let n = Int(0.010 * fs)
        return (0..<n).map { i in
            let t = Double(i) / fs
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1))
            let ph = 2 * .pi * (1500 * t + 0.5 * 450_000 * t * t)
            return Float(w * (quad ? cos(ph) : sin(ph)))
        }
    }

    func signal() -> Data {
        let total = Int(fs * (Double(count) + 1))
        var pcm = [Int16](repeating: 0, count: total)
        let c = Self.chirp(fs)
        for k in 0..<count {
            let s = Int(fs * (0.5 + Double(k)))
            for i in 0..<c.count { pcm[s + i] = Int16(c[i] * 0.5 * 32767) }
        }
        return ChannelTest.wav(pcm, fs: fs)
    }

    /// Records the default input while the chirps play. Calls back on the main queue.
    func record(_ done: @escaping ([Float], Double) -> Void) {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        var samples: [Float] = []
        samples.reserveCapacity(Int(format.sampleRate * Double(count + 3)))
        let lock = NSLock()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            lock.lock(); samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(buf.frameLength))); lock.unlock()
        }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)  // one tap per bus: a leftover one would crash the next try
            done([], format.sampleRate)
            return
        }
        player = try? AVAudioPlayer(data: signal())
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.player?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(count) + 2.5) {
            self.engine.stop()
            input.removeTap(onBus: 0)
            lock.lock(); let s = samples; lock.unlock()
            done(s, format.sampleRate)
        }
    }

    /// 4th-order Butterworth high-pass at 1 kHz (two biquads), forward and backward so arrival times don't shift.
    /// Drops room rumble that would otherwise leak into the correlation.
    static func highpass(_ x: [Float], fs: Double) -> [Float] {
        let w = 2 * Double.pi * 1000 / fs, cw = cos(w)
        var coeffs: [Double] = []
        for q in [0.5412, 1.3066] {  // Q of the two sections of a 4th-order Butterworth
            let alpha = sin(w) / (2 * q), a0 = 1 + alpha
            coeffs += [(1 + cw) / 2 / a0, -(1 + cw) / a0, (1 + cw) / 2 / a0, -2 * cw / a0, (1 - alpha) / a0]
        }
        func run(_ v: [Float]) -> [Float] {
            guard let setup = vDSP_biquad_CreateSetup(coeffs, 2) else { return v }
            defer { vDSP_biquad_DestroySetup(setup) }
            var delay = [Float](repeating: 0, count: 2 * 2 + 2)
            var out = [Float](repeating: 0, count: v.count)
            vDSP_biquad(setup, &delay, v, 1, &out, 1, vDSP_Length(v.count))
            return out
        }
        return Array(run(Array(run(x).reversed())).reversed())
    }

    /// Per chirp: the strongest arrival, and the strongest other arrival within ±15 ms of `expected` from it
    /// (the shifted Mac and the HomePods, in either order: which is louder depends on where the mic is).
    /// Returns the median gap in ms, the interquartile spread, and how many chirps gave a clean pair.
    static func measure(_ raw: [Float], fs: Double, expected: Double) -> (gap: Double, spread: Double, n: Int)? {
        let x = highpass(raw, fs: fs)
        let a = chirp(fs), b = chirp(fs, quad: true)
        let n = x.count - a.count + 1
        guard n > Int(fs) else { return nil }
        var ca = [Float](repeating: 0, count: n), cb = ca
        vDSP_conv(x, 1, a, 1, &ca, 1, vDSP_Length(n), vDSP_Length(a.count))  // forward filter = correlation
        vDSP_conv(x, 1, b, 1, &cb, 1, vDSP_Length(n), vDSP_Length(b.count))
        let env = zip(ca, cb).map { sqrt($0 * $0 + $1 * $1) }
        let sorted = env.sorted()
        let floor = 0.3 * sorted[Int(Double(sorted.count) * 0.999)]
        var gaps: [Double] = []
        var i = 0
        while i < env.count {
            // next chirp: first point over the floor, then its maximum within 150 ms
            guard env[i] > floor else { i += 1; continue }
            let end = min(env.count, i + Int(0.15 * fs))
            let m = (i..<end).max(by: { env[$0] < env[$1] })!
            let lo = max(1, m - Int(0.09 * fs)), hi = min(env.count - 2, m + Int(0.09 * fs))
            var best: (gap: Double, amp: Float)?
            for q in lo...hi where abs(q - m) > Int(0.001 * fs) && env[q] > env[q - 1] && env[q] >= env[q + 1] && env[q] > 0.3 * env[m] {
                let g = abs(Double(q - m)) / fs * 1000
                if abs(g - expected) <= 15, best == nil || env[q] > best!.amp { best = (g, env[q]) }
            }
            if let best { gaps.append(best.gap) }
            i = m + Int(0.15 * fs)
        }
        guard gaps.count >= 8 else { return nil }
        let s = gaps.sorted()
        return (s[s.count / 2], s[s.count * 3 / 4] - s[s.count / 4], s.count)
    }
}
