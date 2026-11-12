// Settings window: the things you set once (which HomePod is left, Mac speaker offset, language).
// The menu bar keeps only what you use every day: picking outputs and their volume.
import AVFoundation
import AppKit
import SwiftUI

let leftFile = wantFile.deletingLastPathComponent().appendingPathComponent("left")
let syncFile = wantFile.deletingLastPathComponent().appendingPathComponent("mac-sync-ms")
let alignRestoreFile = wantFile.deletingLastPathComponent().appendingPathComponent("align-restore")

func readSetting(_ url: URL) -> String {
    ((try? String(contentsOf: url, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}
@discardableResult
func writeSetting(_ url: URL, _ text: String) -> Bool {
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    } catch {
        NSSound.beep()  // nothing changed on screen either, so the user can just try again
        return false
    }
}

final class SettingsModel: ObservableObject {
    // The service reads both files when it (re)starts the stream and restarts on change
    @Published var left = readSetting(leftFile)  // a speaker id; the service falls back to the first of the pair
    @Published var pair: [String] = []  // the two speakers playing as a stereo pair, sorted by id
    @Published var names: [String: String] = [:]
    @Published var sync = Int(readSetting(syncFile)) ?? 0
    @Published var appliedSync = Int(readSetting(syncFile)) ?? 0
    @Published var pairPlaying = false
    @Published var canAlign = false  // the Mac and at least one HomePod are playing
    @Published var aligning = false
    @Published var alignStatus = ""
    @Published var service = ""  // status line 1: "missing", "noservice", or on/off
    @Published var helper = "ok"  // "missing", "outdated", "stopped", "ok"
    @Published var helperBusy = false
    @Published var lang = langSetting { didSet { langSetting = lang; onLangChange() } }
    var onLangChange: () -> Void = {}
    var leftID: String { pair.contains(left) ? left : pair.first ?? "" }
    var rightID: String { pair.first { $0 != leftID } ?? "" }
    func name(_ id: String) -> String { names[id] ?? (id.isEmpty ? "—" : id) }

    func swap() {
        let r = rightID
        if !r.isEmpty, writeSetting(leftFile, r) { left = r }
    }
    func applySync() {
        if writeSetting(syncFile, String(sync)) { appliedSync = sync }
    }
}

/// Plays a soft chime on the left channel, then a higher one on the right, through the normal system
/// output, so it takes the same path as everything else and comes out of whichever HomePod has that channel.
final class ChannelTest {
    private var players: [AVAudioPlayer] = []

    /// A small bell: two notes a third apart, a few milliseconds of fade-in, a gentle decay,
    /// and a quiet octave partial for warmth. Mono 16-bit WAV in memory.
    static func chime(_ notes: [Double], fs: Double = 44100, seconds: Double = 1.2) -> Data {
        let n = Int(fs * seconds)
        var pcm = [Int16](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            var x = 0.0
            for (k, f) in notes.enumerated() {
                let start = Double(k) * 0.07  // the upper note rolls in just after the lower one
                guard t >= start else { continue }
                let u = t - start
                let env = min(1, u / 0.005) * exp(-u / 0.32)
                x += env * (sin(2 * .pi * f * u) + 0.22 * sin(4 * .pi * f * u) * exp(-u / 0.12))
            }
            pcm[i] = Int16(max(-1, min(1, x * 0.22)) * 32767)
        }
        var d = Data()
        func put<T>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + n * 2).littleEndian)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16).littleEndian)
        put(UInt16(1).littleEndian); put(UInt16(1).littleEndian)
        put(UInt32(fs).littleEndian); put(UInt32(fs * 2).littleEndian)
        put(UInt16(2).littleEndian); put(UInt16(16).littleEndian)
        d.append(contentsOf: Array("data".utf8)); put(UInt32(n * 2).littleEndian)
        return wav(pcm, fs: fs)
    }

    static func wav(_ pcm: [Int16], fs: Double) -> Data {
        let n = pcm.count
        var d = Data()
        func put<T>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + n * 2).littleEndian)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); put(UInt32(16).littleEndian)
        put(UInt16(1).littleEndian); put(UInt16(1).littleEndian)
        put(UInt32(fs).littleEndian); put(UInt32(fs * 2).littleEndian)
        put(UInt16(2).littleEndian); put(UInt16(16).littleEndian)
        d.append(contentsOf: Array("data".utf8)); put(UInt32(n * 2).littleEndian)
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    func play() {
        // A major, rising: left A4 + C#5, then right E5 + G#5, so "left, then right" also sounds like it goes somewhere
        players = [[440.0, 554.37], [659.26, 830.61]].compactMap { try? AVAudioPlayer(data: Self.chime($0)) }
        guard players.count == 2 else { NSSound.beep(); return }
        players[0].pan = -1
        players[1].pan = 1
        players[0].play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.players[1].play() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let playTest: () -> Void
    let autoAlign: () -> Void
    let openLogs: () -> Void
    let copyDiagnostics: () -> Void
    let installHelper: () -> Void
    let uninstallHelper: () -> Void

    var body: some View {
        let _ = model.lang  // t() reads the global language; this makes the view redraw when it changes
        Form {
            Section {
                LabeledContent(t("Left channel", "左聲道"), value: model.name(model.leftID))
                LabeledContent(t("Right channel", "右聲道"), value: model.name(model.rightID))
                HStack {
                    Button(t("Play Test Sound", "播放測試音"), action: playTest).disabled(!model.pairPlaying)
                    Button(t("Swap Left and Right", "交換左右"), action: model.swap).disabled(model.pair.count != 2)
                }
            } header: {
                Text(t("Stereo Pair", "左右聲道"))
            } footer: {
                Text(model.pairPlaying
                     ? t("A chime plays on the left channel, then a higher one on the right. If the first one doesn't come from the HomePod on your left, swap them. Swapping reconnects the speakers for a few seconds.",
                         "會先在左聲道響一聲，再在右聲道響一聲較高的音。如果先響的不是左邊那台，就按交換。交換時喇叭會重新連線幾秒。")
                     : t("Select two speakers in the menu bar to set up left and right.",
                         "在選單列勾選兩台喇叭，才能設定左右聲道。"))
                    .foregroundStyle(.secondary)
            }
            Section {
                Stepper(value: $model.sync, in: -100...100) {
                    LabeledContent(t("Offset", "對齊微調"), value: "\(model.sync) ms")
                }
                HStack {
                    Button(t("Apply", "套用")) { model.applySync() }.disabled(model.sync == model.appliedSync || model.aligning)
                    Button(t("Align Automatically", "自動對齊"), action: autoAlign).disabled(!model.canAlign || model.aligning)
                }
                if !model.alignStatus.isEmpty {
                    Text(model.alignStatus).foregroundStyle(.secondary)
                }
            } header: {
                Text(t("This Mac's Speakers", "這台 Mac 的喇叭"))
            } footer: {
                Text(t("Auto-align uses the microphone for about a minute: keep the room quiet. It needs this Mac and a HomePod both selected. You can also adjust by hand: negative plays the Mac earlier. Either way the speakers reconnect for a few seconds.",
                       "自動對齊會用麥克風錄約一分鐘，請保持安靜，而且要同時勾選這台 Mac 和 HomePod。也可以手動調整，負數讓 Mac 提早。兩種方式喇叭都會重新連線幾秒。"))
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker(t("Language", "語言"), selection: $model.lang) {
                    Text(t("Follow System", "跟隨系統")).tag(Lang.system)
                    Text("English").tag(Lang.en)
                    Text("中文").tag(Lang.zh)
                }
                LabeledContent(t("Background helper", "背景服務")) {
                    HStack {
                        Text(model.helper == "missing" ? t("Not installed", "未安裝")
                             : model.helper == "outdated" ? t("Differs from this app", "和這個 App 的版本不同")
                             : model.helper == "stopped" ? t("Not running", "沒在跑") : t("Running", "執行中"))
                            .foregroundStyle(.secondary)
                        Button(model.helper == "missing" ? t("Install", "安裝")
                               : model.helper == "outdated" ? t("Update", "更新") : t("Reinstall", "重新安裝"),
                               action: installHelper)
                            .disabled(model.helperBusy)
                        if model.helper != "missing" {
                            Button(t("Remove", "移除"), action: uninstallHelper).disabled(model.helperBusy)
                        }
                    }
                }
                HStack {
                    Button(t("Open Log Folder", "打開 log 資料夾"), action: openLogs)
                    Button(t("Copy Diagnostics", "複製診斷資訊"), action: copyDiagnostics)
                }
            } header: {
                Text(t("General", "一般"))
            } footer: {
                Text(t("Diagnostics are plain text for reporting a problem: recent sessions and events. IP addresses, device IDs, host names, and the names of speakers found now are replaced by placeholders; check it once more before sending.",
                       "診斷資訊是回報問題用的純文字：最近幾段播放與事件。IP、裝置 ID、主機名稱、目前找到的喇叭名稱會換成代號，送出前請自己再看一次。"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
