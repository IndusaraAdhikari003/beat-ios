import Foundation
import AVFoundation
import SwiftUI

struct SavedState: Codable {
    var playlists: [Playlist] = []
    var hidden: [String] = []
    var theme: Int = 0
    var autoplay: Bool = true
}

final class Store: ObservableObject {
    static let shared = Store()
    static let favID = "fav"
    static var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    @Published var playlists: [Playlist] = [] { didSet { saveIfReady() } }
    @Published var hidden: Set<String> = [] { didSet { saveIfReady() } }
    @Published var theme: Int = 0 { didSet { saveIfReady() } }       // 0 system, 1 light, 2 dark
    @Published var autoplay: Bool = true { didSet { saveIfReady() } }
    @Published var library: [Track] = []
    @Published var loadingLibrary = false
    @Published var pickTrack: Track?
    var localURLs: [String: URL] = [:]

    private var ready = false
    private let key = "beat.state.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(SavedState.self, from: d) {
            playlists = s.playlists
            hidden = Set(s.hidden)
            theme = s.theme
            autoplay = s.autoplay
        }
        if !playlists.contains(where: { $0.id == Store.favID }) {
            playlists.insert(Playlist(id: Store.favID, name: "Favourites", tracks: []), at: 0)
        }
        ready = true
    }

    private func saveIfReady() {
        guard ready else { return }
        let s = SavedState(playlists: playlists, hidden: Array(hidden), theme: theme, autoplay: autoplay)
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    // MARK: playlists

    @discardableResult
    func createPlaylist(_ name: String) -> String {
        let id = UUID().uuidString
        let n = name.trimmed
        playlists.append(Playlist(id: id, name: n.isEmpty ? "Playlist" : n, tracks: []))
        return id
    }

    func deletePlaylist(_ id: String) {
        guard id != Store.favID else { return }
        playlists.removeAll { $0.id == id }
    }

    func rename(_ id: String, _ name: String) {
        let n = name.trimmed
        guard !n.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = n
    }

    func add(_ t: Track, to id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        if !playlists[i].tracks.contains(where: { $0.id == t.id }) {
            playlists[i].tracks.append(t)
        }
    }

    func removeTracks(at offsets: IndexSet, from id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.remove(atOffsets: offsets)
    }

    func removeTrack(_ trackId: String, from id: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.removeAll { $0.id == trackId }
    }

    func moveTracks(in id: String, from: IndexSet, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].tracks.move(fromOffsets: from, toOffset: to)
    }

    func isFav(_ trackId: String) -> Bool {
        playlists.first(where: { $0.id == Store.favID })?.tracks.contains(where: { $0.id == trackId }) ?? false
    }

    func toggleFav(_ t: Track) {
        if isFav(t.id) { removeTrack(t.id, from: Store.favID) } else { add(t, to: Store.favID) }
    }

    func hide(_ id: String) { hidden.insert(id) }
    func unhide(_ id: String) { hidden.remove(id) }
    func unhideAll() { hidden = [] }

    // MARK: local library (files inside the app's Documents folder)

    func url(for t: Track) -> URL? { localURLs[t.id] }

    func reloadLibrary() {
        if loadingLibrary { return }
        loadingLibrary = true
        DispatchQueue.global(qos: .userInitiated).async {
            let exts: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]
            var tracks: [Track] = []
            var urls: [String: URL] = [:]
            if let e = FileManager.default.enumerator(
                at: Store.docsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) {
                while let obj = e.nextObject() {
                    guard let u = obj as? URL, exts.contains(u.pathExtension.lowercased()) else { continue }
                    let id = "L:" + u.lastPathComponent
                    if urls[id] != nil { continue }
                    let m = Store.meta(u)
                    urls[id] = u
                    tracks.append(Track(id: id, title: m.title, artist: m.artist, duration: m.duration))
                }
            }
            tracks.sort { $0.title.lowercased() < $1.title.lowercased() }
            DispatchQueue.main.async {
                self.library = tracks
                self.localURLs = urls
                self.loadingLibrary = false
            }
        }
    }

    private static func meta(_ u: URL) -> (title: String, artist: String, duration: Double) {
        var title = u.deletingPathExtension().lastPathComponent
        var artist = "Unknown artist"
        let asset = AVURLAsset(url: u)
        for item in asset.commonMetadata {
            if item.commonKey == .commonKeyTitle, let s = item.stringValue, !s.trimmed.isEmpty { title = s }
            if item.commonKey == .commonKeyArtist, let s = item.stringValue, !s.trimmed.isEmpty { artist = s }
        }
        let d = CMTimeGetSeconds(asset.duration)
        return (title, artist, d.isFinite ? d : 0)
    }

    func importFiles(_ urls: [URL]) {
        let fm = FileManager.default
        for u in urls {
            var dest = Store.docsURL.appendingPathComponent(u.lastPathComponent)
            var n = 1
            while fm.fileExists(atPath: dest.path) {
                let base = u.deletingPathExtension().lastPathComponent
                dest = Store.docsURL.appendingPathComponent("\(base) (\(n)).\(u.pathExtension)")
                n += 1
            }
            try? fm.copyItem(at: u, to: dest)
        }
        reloadLibrary()
    }
}
