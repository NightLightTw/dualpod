// 背景服務在播放路徑上要用的兩件小事，編成一支執行檔，不依賴 Python（一般使用者的 Mac 沒裝開發工具時 /usr/bin/python3 不能用）。
//
//   stereotool offset                       印出「Unix 時間 − CLOCK_UPTIME_RAW」（ns）。所有行程用同一個原始時鐘加這個位移，
//                                           NTP 調整系統時間時兩台不會一台跳、一台慢慢追
//   stereotool now <offset>                 依上面的時鐘印出現在的 Unix ms
//   stereotool sleepuntil <unix_ms> <offset>  睡到那個時刻
//   stereotool split [--routes <檔>] <路徑:聲道>…   stdin 的 s16le 44.1 kHz 立體聲拆給各輸出：L、R（複製成雙聲道）、LR（原樣）、
//                                           0（寫靜音，時間軸照走）、X（關掉 fd，之後不再寫）
//   --routes 檔內容是空白分隔的「路徑:聲道」，約每 100 ms 看一次有沒有變，變了就套用到已開啟的輸出（不認得的路徑略過）；
//   整個檔格式不對就整份忽略、stderr 記一次。路由只改下一塊起寫給各 fd 的內容，樣本時間軸不動
//
// split 的輸出鎖在牆鐘的 44.1 kHz：process tap 在系統沒出聲時不送資料，這時補靜音，否則 cliairplay 會判定斷流、
// 各自平移時間軸，兩台的對齊就散了。輸入比牆鐘超前太多（tap 恢復時一次湧入，或時脈漂移累積）就丟掉最舊的，延遲維持固定。
// shortcut: 丟樣本／補靜音是整段硬切，漂移累積到門檻時會有一次小爆音；要更乾淨再改成重取樣
import Foundation

func rawNs() -> Int64 { Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) }
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
func usage() -> Never { err("用法: stereotool offset | now <offset> | sleepuntil <unix_ms> <offset> | split [--routes <檔>] <路徑:L|R|LR|0|X>…"); exit(2) }

let args = CommandLine.arguments
guard args.count >= 2 else { usage() }

switch args[1] {
case "offset":
    var tv = timespec()
    clock_gettime(CLOCK_REALTIME, &tv)
    let unixNs = Int64(tv.tv_sec) * 1_000_000_000 + Int64(tv.tv_nsec)
    print(unixNs - rawNs())

case "now":
    guard args.count == 3, let off = Int64(args[2]) else { usage() }
    print((rawNs() + off) / 1_000_000)

case "sleepuntil":
    guard args.count == 4, let ms = Int64(args[2]), let off = Int64(args[3]) else { usage() }
    let wait = ms * 1_000_000 - off - rawNs()
    if wait > 0 { Thread.sleep(forTimeInterval: Double(wait) / 1e9) }

case "split":
    split(Array(args.dropFirst(2)))

default:
    usage()
}

func split(_ argv: [String]) {
    var specs = argv
    var routesFile: String?
    if specs.first == "--routes" {
        guard specs.count >= 2 else { usage() }
        routesFile = specs[1]
        specs.removeFirst(2)
    }
    let fs = 44100.0
    let idle = Int(0.080 * fs)      // 輸入落後超過 80 ms 才當成斷流補靜音；一般抖動（±20 ms）不動作
    let maxAhead = Int(0.060 * fs)  // 輸入比基準超前 60 ms 以上就丟
    enum Mode { case left, right, both, zero, closed }
    func parseMode(_ m: Substring) -> Mode? {
        switch m {
        case "L": return .left
        case "R": return .right
        case "LR": return .both
        case "0": return .zero
        case "X": return .closed
        default: return nil
        }
    }
    func parseSpec(_ spec: Substring) -> (path: String, mode: Mode)? {
        guard let colon = spec.lastIndex(of: ":"), let mode = parseMode(spec[spec.index(after: colon)...]) else { return nil }
        return (String(spec[..<colon]), mode)
    }
    var outputs: [(path: String, fd: Int32, mode: Mode)] = []
    for spec in specs {
        guard let (path, mode) = parseSpec(Substring(spec)) else { err("split: 不認得的輸出 \(spec)"); exit(2) }
        if mode == .closed { outputs.append((path, -1, .closed)); continue }
        let fd = open(path, O_WRONLY)
        guard fd >= 0 else { err("split: 開不了 \(path)"); exit(1) }
        outputs.append((path, fd, mode))
    }
    guard !outputs.isEmpty else { usage() }
    signal(SIGPIPE, SIG_IGN)

    func writeAll(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) {
        var done = 0
        while done < n {
            let r = write(fd, p + done, n - done)
            if r < 0 { if errno == EINTR { continue }; exit(0) }  // 下游關了：播放結束
            done += r
        }
    }
    var dup: [Int16] = []
    func emit(_ pcm: UnsafeBufferPointer<Int16>) {  // pcm：交錯的 L, R
        for (_, fd, mode) in outputs {
            if mode == .closed { continue }
            if mode == .both { writeAll(fd, pcm.baseAddress!, pcm.count * 2); continue }
            if mode == .zero {
                dup.removeAll(keepingCapacity: true)
                dup.append(contentsOf: repeatElement(0, count: pcm.count))
                dup.withUnsafeBytes { writeAll(fd, $0.baseAddress!, $0.count) }
                continue
            }
            let off = mode == .left ? 0 : 1
            dup.removeAll(keepingCapacity: true)
            for i in stride(from: 0, to: pcm.count - 1, by: 2) { dup.append(pcm[i + off]); dup.append(pcm[i + off]) }
            dup.withUnsafeBytes { writeAll(fd, $0.baseAddress!, $0.count) }
        }
    }

    // 路由檔用 mtime（奈秒）加 inode 判斷有沒有換：寫入端是 tmp＋mv，inode 會變
    var routesSig = "", lastPoll: Int64 = 0
    func pollRoutes(_ now: Int64) {
        guard let file = routesFile, now - lastPoll >= 100_000_000 else { return }
        lastPoll = now
        var st = stat()
        guard stat(file, &st) == 0 else { return }
        let sig = "\(st.st_mtimespec.tv_sec).\(st.st_mtimespec.tv_nsec) \(st.st_ino)"
        guard sig != routesSig else { return }
        routesSig = sig
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return }
        var table: [(String, Mode)] = []
        for tok in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }) {
            guard let (path, mode) = parseSpec(tok) else { err("split: 路由檔格式不對，整份忽略（\(tok)）"); return }
            table.append((path, mode))
        }
        for (path, mode) in table {
            guard let i = outputs.firstIndex(where: { $0.path == path }), outputs[i].mode != .closed else { continue }
            if mode == .closed { close(outputs[i].fd); outputs[i].fd = -1 }
            outputs[i].mode = mode
        }
        // 套用完才回報：寫入端等到這份 ack 才能斷開被移除的輸出（斷開後讀端不再讀，FIFO 會寫滿卡住 split）。atomically 即 tmp＋rename
        try? text.write(toFile: file + ".applied", atomically: true, encoding: .utf8)
    }

    _ = fcntl(0, F_SETFL, fcntl(0, F_GETFL) | O_NONBLOCK)
    let t0 = rawNs()
    var tv = timespec()
    clock_gettime(CLOCK_REALTIME, &tv)
    err(String(format: "split: t0_unix=%.6f", Double(tv.tv_sec) + Double(tv.tv_nsec) / 1e9))  // 樣本 0 寫出的時間
    var written = 0                 // 已輸出的 frame 數；基準線＝牆鐘，tap 在系統靜音時（包括剛啟動）完全不送資料，所以一開始就要補
    var pending = [UInt8]()
    var silenceFrames = 0, droppedFrames = 0, lastLog = -1
    var buf = [UInt8](repeating: 0, count: 65536)
    var pfd = pollfd(fd: 0, events: Int16(POLLIN), revents: 0)
    while true {
        _ = poll(&pfd, 1, 5)  // 每 5 ms 檢查一次
        let n = buf.withUnsafeMutableBytes { read(0, $0.baseAddress!, $0.count) }
        if n == 0 { break }  // 上游結束
        if n > 0 { pending.append(contentsOf: buf[0..<n]) }
        let nowNs = rawNs()
        pollRoutes(nowNs)
        let elapsed = Double(nowNs - t0) / 1e9
        let due = Int(elapsed * fs)  // 照牆鐘此刻應該輸出到第幾個 frame
        let frames = pending.count / 4
        if frames > 0 {
            let take = min(frames, max(0, due + maxAhead - written))
            droppedFrames += frames - take
            if take > 0 {  // 丟最舊的、留最新的，延遲才不會被拉長
                pending.withUnsafeBytes { raw in
                    let s = raw.bindMemory(to: Int16.self)
                    emit(UnsafeBufferPointer(rebasing: s[(frames - take) * 2 ..< frames * 2]))
                }
                written += take
            }
            pending.removeFirst(frames * 4)
        } else if written < due - idle {  // 斷流：補靜音到基準線
            let gap = due - written
            let zeros = [Int16](repeating: 0, count: gap * 2)
            zeros.withUnsafeBufferPointer { emit($0) }
            written += gap
            silenceFrames += gap
        }
        let sec = Int(elapsed)
        if sec % 10 == 0, sec != lastLog, silenceFrames > 0 || droppedFrames > 0 {
            lastLog = sec
            err(String(format: "split: 補靜音 %.0f ms，丟棄 %.0f ms",
                       Double(silenceFrames) / fs * 1000, Double(droppedFrames) / fs * 1000))
            silenceFrames = 0
            droppedFrames = 0
        }
    }
}
