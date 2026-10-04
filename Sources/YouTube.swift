import Foundation

struct YCard: Identifiable {
    let id = UUID()
    var title: String
    var sub: String
    var thumb: String
    var track: Track?
    var browseId: String
    var playlistId: String
}

struct YShelf: Identifiable {
    let id = UUID()
    var title: String
    var cards: [YCard]
}

enum YErr: LocalizedError {
    case msg(String)
    var errorDescription: String? {
        switch self { case .msg(let s): return s }
    }
}

/// Tiny JSON helpers (YouTube's responses are deeply nested)
enum J {
    static func at(_ root: Any?, _ path: [Any]) -> Any? {
        var cur = root
        for k in path {
            if let s = k as? String, let d = cur as? [String: Any] {
                cur = d[s]
            } else if let i = k as? Int, let a = cur as? [Any] {
                cur = (i >= 0 && i < a.count) ? a[i] : nil
            } else {
                return nil
            }
        }
        return cur
    }

    static func str(_ root: Any?, _ path: Any...) -> String? {
        return at(root, path) as? String
    }

    static func collect(_ node: Any?, _ key: String, _ out: inout [[String: Any]]) {
        if let d = node as? [String: Any] {
            for (k, v) in d {
                if k == key, let o = v as? [String: Any] {
                    out.append(o)
                } else {
                    collect(v, key, &out)
                }
            }
        } else if let a = node as? [Any] {
            for v in a { collect(v, key, &out) }
        }
    }
}

enum YT {
    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func videoId(_ s: String) -> String? {
        return firstMatch(#"(?:v=|youtu\.be/|shorts/)([A-Za-z0-9_-]{11})"#, in: s)
    }

    static func playlistId(_ s: String) -> String? {
        guard let id = firstMatch(#"[?&]list=([A-Za-z0-9_-]+)"#, in: s) else { return nil }
        return (id.hasPrefix("PL") || id.hasPrefix("OLAK5uy")) ? id : nil
    }
}

/// YouTube Music "InnerTube" client: search, home feed, playlists, radio (similar songs).
enum YM {
    static let origin = "https://music.youtube.com"
    static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"

    static func clientVersion() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd"
        return "1.\(f.string(from: Date())).01.00"
    }

    static func post(_ endpoint: String, _ body: [String: Any]) async throws -> Any {
        var b = body
        let client: [String: String] = [
            "clientName": "WEB_REMIX", "clientVersion": clientVersion(), "hl": "en"
        ]
        let user: [String: String] = [:]
        b["context"] = ["client": client, "user": user]
        guard let url = URL(string: "\(origin)/youtubei/v1/\(endpoint)?alt=json") else {
            throw YErr.msg("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.httpShouldHandleCookies = false
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        req.setValue(origin, forHTTPHeaderField: "X-Origin")
        req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YErr.msg("Network error")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: parsing

    static func lastThumb(_ a: Any?) -> String {
        guard let arr = a as? [Any], let last = arr.last as? [String: Any] else { return "" }
        return (last["url"] as? String) ?? ""
    }

    static func dur(_ s: String?) -> Double {
        guard let s = s else { return 0 }
        var t = 0.0
        for p in s.split(separator: ":") {
            t = t * 60 + (Double(p.trimmingCharacters(in: .whitespaces)) ?? 0)
        }
        return t
    }

    static func mk(_ id: String, _ title: String, _ artist: String, _ d: Double, _ thumb: String) -> Track {
        let art = thumb.isEmpty ? "https://i.ytimg.com/vi/\(id)/mqdefault.jpg" : thumb
        return Track(id: "Y:" + id, title: title, artist: artist, duration: d, art: art)
    }

    static func artistAndDuration(_ runs: [Any]?) -> (String, Double) {
        var parts: [String] = []
        for r in (runs ?? []) {
            if let o = r as? [String: Any], let t = o["text"] as? String, t != " • ", t != "•" {
                parts.append(t)
            }
        }
        let labels = ["Song", "Video", "Album", "Single", "EP", "Playlist"]
        if parts.count > 1, let f = parts.first, labels.contains(f) { parts.removeFirst() }
        let artist = parts.first ?? ""
        var d = 0.0
        if let last = parts.last, last.contains(":"), last.allSatisfy({ $0.isNumber || $0 == ":" }) {
            d = dur(last)
        }
        return (artist, d)
    }

    static func listItem(_ r: [String: Any]) -> Track? {
        let id1 = J.str(r, "playlistItemData", "videoId")
        let id2 = J.str(r, "overlay", "musicItemThumbnailOverlayRenderer", "content",
                        "musicPlayButtonRenderer", "playNavigationEndpoint", "watchEndpoint", "videoId")
        guard let id = id1 ?? id2 else { return nil }
        guard let title = J.str(r, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer",
                                "text", "runs", 0, "text") else { return nil }
        let runs = J.at(r, ["flexColumns", 1, "musicResponsiveListItemFlexColumnRenderer", "text", "runs"]) as? [Any]
        let (artist, d0) = artistAndDuration(runs)
        var d = d0
        if d == 0 {
            d = dur(J.str(r, "fixedColumns", 0, "musicResponsiveListItemFixedColumnRenderer",
                          "text", "runs", 0, "text"))
        }
        let th = lastThumb(J.at(r, ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        return mk(id, title, artist, d, th)
    }

    static func twoRow(_ r: [String: Any]) -> YCard? {
        guard let title = J.str(r, "title", "runs", 0, "text") else { return nil }
        var sub = ""
        if let runs = J.at(r, ["subtitle", "runs"]) as? [Any] {
            for x in runs {
                if let o = x as? [String: Any], let t = o["text"] as? String { sub += t }
            }
        }
        let th = lastThumb(J.at(r, ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]))
        let vid = J.str(r, "navigationEndpoint", "watchEndpoint", "videoId")
        let browse = J.str(r, "navigationEndpoint", "browseEndpoint", "browseId") ?? ""
        let pl = J.str(r, "navigationEndpoint", "watchPlaylistEndpoint", "playlistId") ?? ""
        if vid == nil && browse.isEmpty && pl.isEmpty { return nil }
        var track: Track? = nil
        if let v = vid {
            let parts = sub.components(separatedBy: " • ")
            var artist = parts.first ?? ""
            if parts.count > 1 && (parts[0] == "Song" || parts[0] == "Video") { artist = parts[1] }
            track = mk(v, title, artist, 0, th)
        }
        return YCard(title: title, sub: sub, thumb: th, track: track, browseId: browse, playlistId: pl)
    }

    static func panel(_ r: [String: Any]) -> Track? {
        guard let id = J.str(r, "videoId"), let title = J.str(r, "title", "runs", 0, "text") else { return nil }
        let artist = J.str(r, "longBylineText", "runs", 0, "text")
            ?? J.str(r, "shortBylineText", "runs", 0, "text") ?? ""
        let d = dur(J.str(r, "lengthText", "runs", 0, "text"))
        return mk(id, title, artist, d, lastThumb(J.at(r, ["thumbnail", "thumbnails"])))
    }

    // MARK: public API

    static func search(_ q: String) async throws -> [Track] {
        func run(_ params: String?) async throws -> [Track] {
            var body: [String: Any] = ["query": q]
            if let p = params { body["params"] = p }
            let j = try await post("search", body)
            var rs: [[String: Any]] = []
            J.collect(j, "musicResponsiveListItemRenderer", &rs)
            var seen = Set<String>()
            var out: [Track] = []
            for r in rs {
                if let t = listItem(r), seen.insert(t.id).inserted { out.append(t) }
            }
            return out
        }
        let first = (try? await run("EgWKAQIIAWoMEA4QChADEAQQCRAF")) ?? []
        if !first.isEmpty { return first }
        return try await run(nil)
    }

    static func home() async throws -> [YShelf] {
        let j = try await post("browse", ["browseId": "FEmusic_home"])
        var shelves: [[String: Any]] = []
        J.collect(j, "musicCarouselShelfRenderer", &shelves)
        var out: [YShelf] = []
        for s in shelves {
            let title = J.str(s, "header", "musicCarouselShelfBasicHeaderRenderer", "title", "runs", 0, "text") ?? ""
            guard let arr = s["contents"] as? [Any] else { continue }
            var cards: [YCard] = []
            for item in arr {
                guard let o = item as? [String: Any] else { continue }
                if let t = o["musicTwoRowItemRenderer"] as? [String: Any], let c = twoRow(t) {
                    cards.append(c)
                } else if let l = o["musicResponsiveListItemRenderer"] as? [String: Any], let tr = listItem(l) {
                    cards.append(YCard(title: tr.title, sub: tr.artist, thumb: tr.art,
                                       track: tr, browseId: "", playlistId: ""))
                }
            }
            if !cards.isEmpty {
                out.append(YShelf(title: title.isEmpty ? "For you" : title, cards: cards))
            }
        }
        return out
    }

    static func browseTracks(_ browseId: String) async throws -> [Track] {
        let j = try await post("browse", ["browseId": browseId])
        var rs: [[String: Any]] = []
        J.collect(j, "musicResponsiveListItemRenderer", &rs)
        var seen = Set<String>()
        var out: [Track] = []
        for r in rs {
            if let t = listItem(r), seen.insert(t.id).inserted { out.append(t) }
        }
        return out
    }

    /// Songs similar to a video (or to a given mix playlist).
    static func radio(videoId: String?, playlistId: String?) async throws -> [Track] {
        var body: [String: Any] = [
            "playlistId": playlistId ?? "RDAMVM\(videoId ?? "")",
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "enablePersistentPlaylistPanel": true
        ]
        if let v = videoId { body["videoId"] = v }
        let j = try await post("next", body)
        var rs: [[String: Any]] = []
        J.collect(j, "playlistPanelVideoRenderer", &rs)
        var seen = Set<String>()
        var out: [Track] = []
        for r in rs {
            if let t = panel(r), seen.insert(t.id).inserted { out.append(t) }
        }
        return out
    }

    /// Info for a single pasted video link.
    static func songInfo(_ videoId: String) async throws -> Track? {
        let l = try await radio(videoId: videoId, playlistId: nil)
        return l.first(where: { $0.id == "Y:" + videoId }) ?? l.first
    }
}

/// Finds a playable audio URL for a video. YouTube changes this often.
actor YStream {
    static let shared = YStream()
    static let ua = "com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
    private var cache: [String: (URL, Date)] = [:]

    func url(for id: String) async throws -> URL {
        if let c = cache[id], Date().timeIntervalSince(c.1) < 1800 { return c.0 }
        let u = try await resolve(id)
        cache[id] = (u, Date())
        return u
    }

    private func probe(_ u: URL) async -> Bool {
        var r = URLRequest(url: u)
        r.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        r.setValue(YStream.ua, forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 12
        guard let result = try? await URLSession.shared.data(for: r),
              let h = result.1 as? HTTPURLResponse else { return false }
        return h.statusCode == 200 || h.statusCode == 206
    }

    private func resolve(_ id: String) async throws -> URL {
        let client: [String: Any] = [
            "clientName": "ANDROID_VR", "clientVersion": "1.60.19",
            "deviceMake": "Oculus", "deviceModel": "Quest 3",
            "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L",
            "hl": "en", "gl": "US"
        ]
        let body: [String: Any] = [
            "videoId": id, "contentCheckOk": true, "racyCheckOk": true,
            "context": ["client": client]
        ]
        guard let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else {
            throw YErr.msg("Bad URL")
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(YStream.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("28", forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue("1.60.19", forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = try JSONSerialization.jsonObject(with: data)

        if let status = J.str(j, "playabilityStatus", "status"), status != "OK" {
            throw YErr.msg(J.str(j, "playabilityStatus", "reason") ?? "Not playable")
        }

        var candidates: [URL] = []
        // 1) audio-only (best for data usage)
        if let ad = J.at(j, ["streamingData", "adaptiveFormats"]) as? [[String: Any]] {
            let audio = ad.filter { (($0["mimeType"] as? String) ?? "").hasPrefix("audio/mp4") }
            let sorted = audio.sorted { (($0["bitrate"] as? Int) ?? 0) > (($1["bitrate"] as? Int) ?? 0) }
            for f in sorted {
                if let s = f["url"] as? String, let u = URL(string: s) { candidates.append(u) }
            }
        }
        // 2) muxed 360p (itag 18) is the most reliable
        if let fm = J.at(j, ["streamingData", "formats"]) as? [[String: Any]] {
            for f in fm {
                if let s = f["url"] as? String, let u = URL(string: s) { candidates.append(u) }
            }
        }
        for u in candidates.prefix(4) {
            if await probe(u) { return u }
        }
        if let h = J.str(j, "streamingData", "hlsManifestUrl"), let u = URL(string: h) { return u }
        throw YErr.msg("No playable stream")
    }
}
