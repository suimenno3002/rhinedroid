// Playback behaviour ported from RhineDroid PlaybackService.kt / NativeMusicHost.kt
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import AVFoundation
import Foundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// AVQueuePlayer with the upstream song-transition envelope (450 ms fades), gapless pre-buffering of
/// the next queue entry, the looping ambient BGM, Now Playing / remote commands and Navidrome scrobbling.
@MainActor @Observable
public final class PlaybackEngine {
    public enum Transition: String, CaseIterable, Sendable { case fadeOut = "fade-out", fadeInOut = "fade-in-out", gapless }
    public enum Transport: Sendable { case idle, loading, playing, paused, error }

    public private(set) var queue = PlayQueue()
    public private(set) var transport: Transport = .idle
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var errorMessage: String?
    public private(set) var volume: Float
    public private(set) var transition: Transition
    public private(set) var bgmEnabled: Bool
    public private(set) var bgmVolume: Float
    public var current: Song? { queue.current }
    public var isPlaying: Bool { transport == .playing || transport == .loading }

    @ObservationIgnored public var client: SubsonicClient?
    /// Fires when the playing song changes (nil after stop).
    @ObservationIgnored public var onCurrentChange: ((Song?) -> Void)?
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private let bgm: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var currentItem: AVPlayerItem?
    @ObservationIgnored private var nextItem: AVPlayerItem?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemStatus: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var songGain = AudioEnvelope()
    @ObservationIgnored private var backgroundGain = AudioEnvelope(0)
    @ObservationIgnored private var pending: (() -> Void)?
    @ObservationIgnored private var switchAt = 0.0
    @ObservationIgnored private var fadeWaiting = false
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var scrobbled = false
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let volume = "rhine.volume", transition = "rhine.songTransition", bgm = "rhine.bgm"
        static let bgmVolume = "rhine.bgmVolume", repeatMode = "rhine.repeat", shuffle = "rhine.shuffle"
    }
    /// Codecs AVFoundation cannot decode; Navidrome transcodes these to 320k MP3.
    static let transcoded: Set<String> = ["ape", "wv", "dsf", "dff", "wma", "ogg", "oga", "opus", "tta", "mpc", "tak"]
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    public init(bgm url: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // iPad has hardware volume, so the in-app level starts at full instead of upstream's 0.65.
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 1
        transition = Transition(rawValue: defaults.string(forKey: Keys.transition) ?? "") ?? .fadeInOut
        bgmEnabled = defaults.bool(forKey: Keys.bgm)
        bgmVolume = defaults.object(forKey: Keys.bgmVolume) as? Float ?? 0.18
        var background: AVQueuePlayer?
        var loop: AVPlayerLooper?
        if let url {
            let p = AVQueuePlayer()
            p.volume = 0
            loop = AVPlayerLooper(player: p, templateItem: AVPlayerItem(url: url))
            background = p
        }
        bgm = background
        looper = loop
        queue.repeatMode = PlayQueue.Repeat(rawValue: defaults.string(forKey: Keys.repeatMode) ?? "") ?? .off
        player.volume = volume
        player.actionAtItemEnd = .advance
        observe()
        setupRemoteCommands()
        #if os(iOS)
        configureSession()
        #endif
    }

    // MARK: Commands

    public func play(_ songs: [Song], startAt index: Int = 0) {
        guard !songs.isEmpty else { return }
        var next = PlayQueue(songs: songs, start: index)
        next.repeatMode = queue.repeatMode
        if defaults.bool(forKey: Keys.shuffle) { next.setShuffle(true) }
        switchTrack { [unowned self] in queue = next; load(play: true) }
    }

    public func jump(toSong index: Int) {
        var next = queue
        next.jump(toSong: index)
        switchTrack { [unowned self] in queue = next; load(play: true) }
    }

    public func toggle() { isPlaying ? pause() : resume() }

    public func pause() {
        cancelTransition()
        player.pause()
    }

    public func resume() {
        guard queue.current != nil else { return }
        if currentItem == nil { load(play: true); return }
        activateSession()
        player.play()
    }

    public func next() {
        var next = queue
        guard next.skip() != nil else { return }
        switchTrack { [unowned self] in queue = next; load(play: true) }
    }

    /// Restarts the song after 3 s, like Media3's seekToPrevious.
    public func previous(restart: Bool = true) {
        if restart, currentTime > 3 { seek(to: 0); return }
        var next = queue
        guard next.back() != nil else { return }
        switchTrack { [unowned self] in queue = next; load(play: true) }
    }

    public func seek(to seconds: Double) {
        currentTime = max(0, seconds)
        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    public func stop() {
        cancelTransition()
        player.removeAllItems()
        currentItem = nil; nextItem = nil; itemStatus = nil
        queue = PlayQueue(); queue.repeatMode = PlayQueue.Repeat(rawValue: defaults.string(forKey: Keys.repeatMode) ?? "") ?? .off
        transport = .idle; currentTime = 0; duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateBackground()
        onCurrentChange?(nil)
    }

    public func setRepeat(_ mode: PlayQueue.Repeat) {
        queue.repeatMode = mode
        defaults.set(mode.rawValue, forKey: Keys.repeatMode)
        enqueueNext()
    }

    public func setShuffle(_ on: Bool) {
        queue.setShuffle(on)
        defaults.set(on, forKey: Keys.shuffle)
        enqueueNext()
    }

    public func playNext(_ songs: [Song]) {
        if queue.isEmpty { play(songs); return }
        queue.playNext(songs); enqueueNext()
    }

    public func append(_ songs: [Song]) {
        if queue.isEmpty { play(songs); return }
        queue.append(songs); enqueueNext()
    }

    public func remove(at orderIndex: Int) { queue.remove(at: orderIndex); enqueueNext() }

    public func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        defaults.set(volume, forKey: Keys.volume)
        applyGain(Self.now)
    }

    public func setTransition(_ mode: Transition) { transition = mode; defaults.set(mode.rawValue, forKey: Keys.transition) }

    public func setBackground(enabled: Bool? = nil, volume: Float? = nil) {
        if let enabled { bgmEnabled = enabled; defaults.set(enabled, forKey: Keys.bgm) }
        if let volume { bgmVolume = min(max(volume, 0), 1); defaults.set(bgmVolume, forKey: Keys.bgmVolume) }
        updateBackground()
    }

    /// The library screen is visible (BGM only plays there, like upstream).
    public func setForeground(_ value: Bool) { foreground = value; updateBackground() }

    // MARK: Queue → AVQueuePlayer

    private func load(play: Bool) {
        player.removeAllItems()
        nextItem = nil
        guard let song = queue.current else { stop(); return }
        let item = makeItem(song)
        currentItem = item
        player.insert(item, after: nil)
        watch(item)
        enqueueNext()
        started(song)
        if play { activateSession(); player.play() } else { transport = .paused }
        updateBackground()
    }

    /// Keeps exactly one pre-buffered item after the current one so natural advances are gapless.
    private func enqueueNext() {
        if let item = nextItem { player.remove(item); nextItem = nil }
        guard currentItem != nil, let song = queue.autoNextSong else { return }
        let item = makeItem(song)
        player.insert(item, after: currentItem)
        nextItem = item
    }

    private func makeItem(_ song: Song) -> AVPlayerItem {
        let convert = Self.transcoded.contains(song.suffix?.lowercased() ?? "")
        let url = client?.streamURL(id: song.id, transcodeTo: convert ? "mp3" : nil, maxBitRate: convert ? 320 : nil) ?? URL(string: "about:blank")!
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        item.preferredForwardBufferDuration = 30
        return item
    }

    private func started(_ song: Song) {
        errorMessage = nil
        currentTime = 0
        duration = Double(song.duration ?? 0)
        scrobbled = false
        updateNowPlaying(artwork: true)
        onCurrentChange?(song)
        if let client { Task { try? await client.scrobble(id: song.id, submission: false) } }
    }

    /// AVQueuePlayer moved on by itself: either into the pre-buffered item or off the end of the queue.
    private func currentItemChanged() {
        let item = player.currentItem
        guard item !== currentItem else { return }
        if let item, item === nextItem {
            queue.finish()
            currentItem = item; nextItem = nil
            watch(item)
            enqueueNext()
            if let song = queue.current { started(song) }
        } else if item == nil, currentItem != nil {
            // End of queue with repeat off: stay on the last song, rewound and paused.
            currentItem = nil
            load(play: false)
        }
    }

    private func watch(_ item: AVPlayerItem) {
        itemStatus = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item === self.currentItem, item.status == .failed else { return }
                self.errorMessage = item.error?.localizedDescription ?? "无法播放这首歌"
                self.transport = .error
                self.cancelTransition()
            }
        }
    }

    // MARK: Song transition envelope (PlaybackService.switchTrack)

    private func switchTrack(_ action: @escaping () -> Void) {
        let now = Self.now
        let mode = transition
        fadeWaiting = false
        let next = { [unowned self] in
            bgm?.pause(); backgroundGain.to(0, now: Self.now, seconds: 0)
            let fade = mode == .fadeInOut
            songGain.to(fade ? 0 : 1, now: Self.now, seconds: 0)
            applyGain(Self.now)
            fadeWaiting = fade
            action()
            schedule()
        }
        let fade = mode != .gapless && (player.rate > 0 || pending != nil || (bgm?.rate ?? 0) > 0)
        pending = nil
        if fade {
            songGain.to(0, now: now, seconds: 0.45); backgroundGain.to(0, now: now, seconds: 0.45)
            switchAt = now + 0.45
            pending = next
            schedule()
        } else {
            next()
        }
    }

    private func cancelTransition() {
        pending = nil; fadeWaiting = false
        songGain.to(1, now: Self.now, seconds: 0)
        schedule()
    }

    private func schedule() {
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, self.tick() else { break }
            }
            self?.ticking = nil
        }
    }

    private func tick() -> Bool {
        let now = Self.now
        if let next = pending, now >= switchAt { pending = nil; next() }
        applyGain(now)
        if backgroundGain.target == 0, backgroundGain.settled(now) { bgm?.pause() }
        return pending != nil || !songGain.settled(now) || !backgroundGain.settled(now)
    }

    private func applyGain(_ now: Double) {
        player.volume = volume * songGain.sample(now)
        bgm?.volume = bgmVolume * backgroundGain.sample(now)
    }

    private func updateBackground() {
        guard let bgm else { return }
        let allowed = foreground && bgmEnabled && queue.current == nil && pending == nil
        let target: Float = allowed ? 1 : 0
        if backgroundGain.target != target { backgroundGain.to(target, now: Self.now, seconds: allowed ? 1.2 : 0.45) }
        if allowed && bgm.rate == 0 { activateSession(); bgm.play() }
        schedule()
    }

    // MARK: Observation

    private func observe() {
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.statusChanged() }
        })
        observations.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.progress(time) }
        }
    }

    private func statusChanged() {
        guard transport != .error || player.timeControlStatus == .playing else { return }
        switch player.timeControlStatus {
        case .playing:
            transport = .playing
            if fadeWaiting { fadeWaiting = false; songGain.to(1, now: Self.now, seconds: 0.45); schedule() }
        case .waitingToPlayAtSpecifiedRate: transport = .loading
        case .paused: transport = currentItem == nil && queue.current == nil ? .idle : .paused
        @unknown default: break
        }
        updateNowPlaying()
    }

    private func progress(_ time: CMTime) {
        guard currentItem != nil, player.currentItem === currentItem else { return }
        currentTime = time.seconds.isFinite ? time.seconds : 0
        if let d = currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        // Subsonic convention: submit once past half the song or four minutes.
        if !scrobbled, duration > 0, currentTime >= min(duration / 2, 240), let song = queue.current, let client {
            scrobbled = true
            Task { try? await client.scrobble(id: song.id, submission: true) }
        }
    }

    // MARK: System integration

    private func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    #if os(iOS)
    private func configureSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated {
                if type == .ended, options.contains(.shouldResume) { self?.resume() }
            }
        }
        // Headphones unplugged: pause, like Media3's handleAudioBecomingNoisy.
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated { if reason == .oldDeviceUnavailable { self?.pause() } }
        }
    }
    #endif

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (PlaybackEngine) -> Void) {
            command.addTarget { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
                return .success
            }
        }
        on(center.playCommand) { $0.resume() }
        on(center.pauseCommand) { $0.pause() }
        on(center.togglePlayPauseCommand) { $0.toggle() }
        on(center.nextTrackCommand) { $0.next() }
        on(center.previousTrackCommand) { $0.previous() }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying(artwork: Bool = false) {
        guard let song = queue.current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if artwork { info = [:] }
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = transport == .playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        guard artwork, let cover = song.coverArt, let url = client?.coverURL(id: cover, size: 600) else { return }
        artworkTask?.cancel()
        let id = song.id
        artworkTask = Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0, !Task.isCancelled,
                  let self, self.queue.current?.id == id else { return }
            #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return }
            #else
            guard let image = NSImage(data: data) else { return }
            #endif
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
