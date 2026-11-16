// Update check: asks GitHub for the latest stable release and compares it with this build. Nothing is downloaded;
// the menu only links to the release page.
import Foundation

let repoURL = "https://github.com/NightLightTw/dualpod"
let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

enum UpdateState: Equatable {
    case idle, checking, upToDate, failed
    case available(tag: String)  // a validated "vX.Y.Z" or "X.Y.Z"
}

/// "1.2.3" / "v1.2.3" → [1, 2, 3]. `prefix` also accepts a git describe suffix ("v0.1.1-3-gabc-dirty") for dev builds.
func versionNumbers(_ s: String, prefix: Bool = false) -> [Int]? {
    let pattern = #/v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})/#
    guard let m = prefix ? s.prefixMatch(of: pattern) : s.wholeMatch(of: pattern) else { return nil }
    let n = [m.1, m.2, m.3].compactMap { Int($0) }
    return n.count == 3 ? n : nil
}

func checkLatestRelease(_ done: @escaping (UpdateState) -> Void) {
    var req = URLRequest(url: URL(string: "https://api.github.com/repos/NightLightTw/dualpod/releases/latest")!,
                         cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    req.setValue("DualPod-update-check", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: req) { data, response, _ in
        let state: UpdateState
        let code = (response as? HTTPURLResponse)?.statusCode
        if code == 200, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                  let tag = json["tag_name"] as? String, let latest = versionNumbers(tag),
                  let current = versionNumbers(appVersion, prefix: true) {
            state = current.lexicographicallyPrecedes(latest) ? .available(tag: tag) : .upToDate
        } else {
            state = .failed
        }
        DispatchQueue.main.async { done(state) }
    }.resume()
}

/// Built from the repository and the validated tag, never from a URL in the API response.
func releasePage(_ tag: String) -> URL { URL(string: "\(repoURL)/releases/tag/\(tag)")! }
