// Mac 喇叭和 HomePod 同步播放：stdin 讀 s16le 44.1 kHz 立體聲，樣本 0 在 START_UNIX_MS 從 Mac 喇叭出聲。
// 用法：localplay <clock_offset_ns> [adjust_ms]，stdin 第一行是「START <unix_ms>」，之後是 PCM。
// 先啟動、印出 pid，起播時間之後才給：run_pair.sh 要先拿 pid 叫 audiotee 排除它，才決定共同的 START。
// 時鐘和 run_pair.sh 相同：CLOCK_UPTIME_RAW（＝mach host time）加 offset 等於 Unix 時間。
// 引擎一啟動就在 stderr 印 pid，run_pair.sh 拿去叫 audiotee 排除這個行程，否則會把自己的聲音再錄回去。
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 2, let offsetNs = Int64(args[1]) else {
    FileHandle.standardError.write("用法: localplay <clock_offset_ns> [adjust_ms]\n".data(using: .utf8)!)
    exit(2)
}
let adjustMs = args.count > 2 ? Double(args[2]) ?? 0 : 0
func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let fs = 44100.0
let format = AVAudioFormat(standardFormatWithSampleRate: fs, channels: 2)!
let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: format)
try engine.start()

let latency = engine.outputNode.presentationLatency
log(String(format: "localplay: pid=%d ready output_latency_ms=%.1f", getpid(), latency * 1000))

// 直接用 read(2)，不經 FileHandle，確保標頭後面的 PCM 一個 byte 都不會被多讀走
func readExact(_ n: Int) -> Data {
    var d = Data(count: n), got = 0
    d.withUnsafeMutableBytes { p in
        while got < n {
            let r = read(0, p.baseAddress! + got, n - got)
            if r <= 0 { break }
            got += r
        }
    }
    return d.prefix(got)
}
var header = Data()
while header.count < 64, let b = readExact(1).first, b != 10 { header.append(b) }
guard let line = String(data: header, encoding: .utf8), line.hasPrefix("START "),
      let startMs = Int64(line.dropFirst(6)) else { log("localplay: 標頭不是 START <ms>"); exit(2) }

// 播放節點在 renderStart 開始算樣本，再過輸出延遲才真的從喇叭出來
let renderStart = Double(startMs * 1_000_000 - offsetNs) / 1e9 - latency + adjustMs / 1000
player.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: renderStart)))

// Mac 的音訊時脈和系統時鐘會慢慢漂開；每秒比一次「該播到哪」和「實際播到哪」，差超過 1 ms 就補或丟 1 ms
// shortcut: 補的是靜音、丟是硬切，修正那一下可能有極小的喀聲；要更乾淨再改成微調重取樣
let chunkFrames = 882  // 20 ms，和 split.py 寫入的節奏一致
let step: Int64 = 44   // 每次最多修 1 ms
var net: Int64 = 0     // 已補（正）或已丟（負）的 frame 數，播放器第 s 個樣本＝內容第 s − net 個
var chunks = 0
var worst = 0.0
var scheduled: Int64 = 0
while true {
    let data = readExact(chunkFrames * 4)
    if data.isEmpty { break }
    var skip = 0, pad = 0
    chunks += 1
    if chunks % 50 == 0, let nt = player.lastRenderTime, nt.isHostTimeValid,
       let pt = player.playerTime(forNodeTime: nt), pt.sampleTime > 0 {
        let expected = (AVAudioTime.seconds(forHostTime: nt.hostTime) - renderStart) * fs
        let error = Double(pt.sampleTime - net) - expected  // 正＝內容播得太早
        worst = max(worst, abs(error))
        if error > Double(step) { pad = Int(step); net += step }
        if error < -Double(step) { skip = Int(step); net -= step }
        if chunks % 500 == 0 {
            log(String(format: "localplay: 誤差 %.1f ms，最大 %.1f ms，累計修正 %.1f ms",
                       error / fs * 1000, worst / fs * 1000, Double(net) / fs * 1000))
            worst = 0
        }
    }
    let frames = data.count / 4 - skip
    guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames + pad))
    else { continue }
    buf.frameLength = AVAudioFrameCount(frames + pad)
    let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
    for i in 0..<pad { l[i] = 0; r[i] = 0 }
    data.withUnsafeBytes { raw in
        let s = raw.bindMemory(to: Int16.self)
        for i in 0..<frames {
            l[pad + i] = Float(Int16(littleEndian: s[2 * (skip + i)])) / 32768
            r[pad + i] = Float(Int16(littleEndian: s[2 * (skip + i) + 1])) / 32768
        }
    }
    player.scheduleBuffer(buf)
    scheduled += Int64(buf.frameLength)
}
// 輸入結束：等已排程的都播完再停（測試時整段一次寫進來，不等就什麼都沒播）
let end = renderStart + Double(scheduled) / fs + latency
let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
if end > now { Thread.sleep(forTimeInterval: end - now) }
engine.stop()
