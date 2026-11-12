// 用預設輸入裝置錄音到 WAV（硬體取樣率、16-bit）。ffmpeg avfoundation 會標錯取樣率又掉 buffer，量測不能用它。
// 用法：rec <out.wav> <秒數>
import AVFoundation

let args = CommandLine.arguments
guard args.count == 3, let seconds = Double(args[2]) else {
    FileHandle.standardError.write("用法: rec <out.wav> <秒數>\n".data(using: .utf8)!)
    exit(2)
}
let engine = AVAudioEngine()
let input = engine.inputNode
let format = input.outputFormat(forBus: 0)
let file = try AVAudioFile(
    forWriting: URL(fileURLWithPath: args[1]),
    settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
    ],
    commonFormat: format.commonFormat, interleaved: format.isInterleaved)

var frames: AVAudioFramePosition = 0
var lastSampleTime: AVAudioFramePosition = -1
var gaps = 0
var firstWall = 0.0
// 主機時鐘（mach）與牆鐘的差，用來把第一個樣本的 hostTime 換成 Unix 時間
let hostToWall = Date().timeIntervalSince1970 - AVAudioTime.seconds(forHostTime: mach_absolute_time())
input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, when in
    if lastSampleTime < 0, when.isHostTimeValid {
        firstWall = AVAudioTime.seconds(forHostTime: when.hostTime) + hostToWall
    }
    if lastSampleTime >= 0, when.sampleTime != lastSampleTime { gaps += 1 }  // 硬體時間軸不連續＝掉 buffer
    lastSampleTime = when.sampleTime + AVAudioFramePosition(buffer.frameLength)
    try? file.write(from: buffer)
    frames += AVAudioFramePosition(buffer.frameLength)
}
let start = Date()
try engine.start()
Thread.sleep(forTimeInterval: seconds)
engine.stop()
input.removeTap(onBus: 0)
file.close()  // 不關的話 WAV 標頭的長度是 0
let wall = Date().timeIntervalSince(start)
print(String(format: "rec: %.0f Hz, %lld frames = %.3f s audio / %.3f s wall, gaps=%d, first_sample_unix=%.6f",
             format.sampleRate, frames, Double(frames) / format.sampleRate, wall, gaps, firstWall))
