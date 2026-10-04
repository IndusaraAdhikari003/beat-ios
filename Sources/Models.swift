import Foundation

struct Track: Codable, Identifiable, Hashable {
    var id: String            // "L:file.mp3" (local file) or "Y:videoId" (YouTube)
    var title: String
    var artist: String
    var duration: Double      // seconds
    var art: String = ""      // thumbnail URL (YouTube only)

    var isYT: Bool { id.hasPrefix("Y:") }
    var videoId: String { String(id.dropFirst(2)) }
}

struct Playlist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var tracks: [Track]
}

struct MenuAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

func formatTime(_ s: Double) -> String {
    if !s.isFinite || s < 0 { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}
