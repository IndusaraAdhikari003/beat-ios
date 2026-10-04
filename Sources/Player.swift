import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Position/duration live in their own object so lists don't redraw twice a second.
final class PlayClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

final class PlayerModel: ObservableObject {
    static let shared = PlayerModel()

    @Published var queue: [Track] = []
    @Published var index: Int = -1
    @Published var isPlaying = false
    @Published var loading = false
    @Published var shuffle = false
    @Published var repeatMode = 0          // 0 off, 1 all, 2 one
    @Published var error: String?
    @Published var showFull = false
    @Published var sleepAt: Date?

    let clock = PlayClock()
    private let player = AVPlayer()
    private var endObs: NSObjectProtocol?
    private var itemObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var generation = 0
    private var history: [Int] = []
    private var radioFor = ""
    private var sleepTimer: Timer?
    private var artwork: MPMediaItemArtwork?

    var current: Track? {
        (index >= 0 && index < queue.count) ? queue[index] : nil
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [])
        try? s.setActive(true)

        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let playing = p.timeControlStatus != .paused
            DispatchQueue.main.async {
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }

        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] t in
            guard let self = self else { return }
            if t.seconds.isFinite { self.clock.position = t.seconds }
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.clock.duration = d
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                let optRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume) {
                    self?.player.play()
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable { self?.player.pause() }
        }

        setupRemote()
    }

    // MARK: remote / lock screen

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        _ = c.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        _ = c.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.player.pause() }
            return .success
        }
        _ = c.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.toggle() }
            return .success
        }
        _ = c.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        _ = c.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.prev() }
            return .success
        }
        _ = c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let ev = e as? MPChangePlaybackPositionCommandEvent {
                DispatchQueue.main.async { self?.seek(ev.positionTime) }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: clock.duration > 0 ? clock.duration : t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: clock.position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let a = artwork { info[MPMediaItemPropertyArtwork] = a }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ t: Track) {
        artwork = nil
        guard !t.art.isEmpty, let u = URL(string: t.art) else { return }
        let id = t.id
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            DispatchQueue.main.async {
                guard let self = self, self.current?.id == id else { return }
                self.artwork = art
                self.updateNowPlaying()
            }
        }.resume()
    }

    // MARK: playback

    func play(_ list: [Track], at i: Int) {
        guard !list.isEmpty else { return }
        queue = list
        history = []
        radioFor = ""
        start(min(max(i, 0), list.count - 1))
    }

    private func start(_ i: Int) {
        guard i >= 0 && i < queue.count else { return }
        index = i
        let t = queue[i]
        generation += 1
        let gen = generation
        error = nil
        clock.position = 0
        clock.duration = t.duration
        loading = true
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(true)
        loadArtwork(t)
        updateNowPlaying()
        let local: URL? = t.isYT ? nil : Store.shared.url(for: t)

        Task {
            do {
                let item: AVPlayerItem
                if t.isYT {
                    let u = try await YStream.shared.url(for: t.videoId)
                    let asset = AVURLAsset(
                        url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": YStream.ua]]
                    )
                    item = AVPlayerItem(asset: asset)
                } else {
                    guard let u = local else { throw YErr.msg("File not found") }
                    item = AVPlayerItem(url: u)
                }
                await MainActor.run {
                    if gen == self.generation { self.attach(item) }
                }
            } catch {
                await MainActor.run {
                    if gen == self.generation { self.failed() }
                }
            }
        }
    }

    private func attach(_ item: AVPlayerItem) {
        if let o = endObs { NotificationCenter.default.removeObserver(o) }
        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.ended() }
        itemObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            if it.status == .failed {
                DispatchQueue.main.async { self?.failed() }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        loading = false
        maybeAutoplay()
    }

    private func failed() {
        loading = false
        error = "Couldn't play this song"
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if let self = self, self.generation == gen { self.error = nil }
        }
        // skip to the next song (never wraps around, so it can't loop forever)
        if index + 1 < queue.count {
            let n = index + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self, self.generation == gen else { return }
                self.history.append(self.index)
                self.start(n)
            }
        }
    }

    private func ended() {
        if repeatMode == 2 {
            seek(0)
            player.play()
        } else {
            next(auto: true)
        }
    }

    private func resume() {
        if player.currentItem == nil, current != nil { start(index) } else { player.play() }
    }

    func toggle() {
        if isPlaying { player.pause() } else { resume() }
    }

    func next(auto: Bool = false) {
        guard !queue.isEmpty else { return }
        var n = index + 1
        if shuffle && queue.count > 1 {
            repeat { n = Int.random(in: 0..<queue.count) } while n == index
        } else if n >= queue.count {
            if repeatMode == 1 {
                n = 0
            } else {
                if auto { player.pause(); seek(0) }
                return
            }
        }
        history.append(index)
        start(n)
    }

    func prev() {
        if clock.position > 3 || queue.isEmpty {
            seek(0)
            return
        }
        if let h = history.popLast() {
            start(h)
        } else if index > 0 {
            start(index - 1)
        } else {
            seek(0)
        }
    }

    func seek(_ s: Double) {
        player.seek(to: CMTime(seconds: s, preferredTimescale: 600))
        clock.position = s
        updateNowPlaying()
    }

    func toggleShuffle() { shuffle.toggle() }
    func cycleRepeat() { repeatMode = (repeatMode + 1) % 3 }

    func playNext(_ t: Track) {
        if queue.isEmpty { play([t], at: 0) } else { queue.insert(t, at: min(index + 1, queue.count)) }
    }

    func enqueue(_ t: Track) {
        if queue.isEmpty { play([t], at: 0) } else { queue.append(t) }
    }

    func setSleep(_ minutes: Int) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        if minutes <= 0 { sleepAt = nil; return }
        sleepAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            self?.player.pause()
            self?.sleepAt = nil
        }
    }

    // MARK: autoplay (similar songs)

    private func maybeAutoplay() {
        guard let t = current, t.isYT, Store.shared.autoplay, repeatMode == 0,
              index >= queue.count - 2, radioFor != t.id else { return }
        radioFor = t.id
        let seed = t.videoId
        Task {
            let more = (try? await YM.radio(videoId: seed, playlistId: nil)) ?? []
            await MainActor.run {
                let have = Set(self.queue.map { $0.id })
                let fresh = more.filter { !have.contains($0.id) }.prefix(25)
                if !fresh.isEmpty { self.queue.append(contentsOf: fresh) }
            }
        }
    }
}
