import Foundation
import Observation
import RhineKit
import SwiftUI

/// App state shared by the shelf and the SwiftUI overlay (the role of music-app.ts upstream).
@MainActor @Observable
final class AppModel {
    enum Theme: String { case day, night }
    enum Panel: Equatable { case library, search, settings, playlists }

    // Session
    private(set) var client: SubsonicClient?
    var loginError: String?
    var loggingIn = false

    // Library
    private(set) var layout = LibraryLayout(albums: [], mode: .genre)
    /// Shelf key of the selected card: the album id, or "list|albumId" in playlist / favourite modes.
    private(set) var selectedId = ""
    private(set) var loading = false
    var libraryError: String?
    private(set) var details: [String: Album] = [:]
    private(set) var playlists: [Playlist] = []
    @ObservationIgnored private var catalogue: [Album] = []
    @ObservationIgnored private var groups: [LibraryGroup] = []
    /// Per column: the full play list it belongs to and where the column starts in it. Card "n|i" is
    /// `groupLists[n][groupOffsets[n] + i]`; favourites share one list split across 12-card columns.
    @ObservationIgnored private var groupLists: [[Song]] = []
    @ObservationIgnored private var groupOffsets: [Int] = []
    private(set) var favoriteCount: Int?
    static let favoritesPerColumn = 12

    // Presentation
    private(set) var mode: ArchiveScene.Mode = .archive
    private(set) var phase: ArchiveScene.Phase = .archive
    private(set) var overview = false
    var panel: Panel?
    private(set) var theme: Theme

    // Preferences (persisted like upstream `rhinedroid-preferences`)
    private(set) var sortMode: SortMode
    var idleMotion: Bool { didSet { save(); shelf?.perform { [idleMotion] in $0.idleEnabled = idleMotion } } }
    var focusDepth: Bool { didSet { save(); shelf?.perform { [focusDepth] in $0.focusDepth = focusDepth } } }
    var decryption: Bool { didSet { save(); shelf?.perform { [decryption] in $0.decryption = decryption } } }
    var renderScale: Double { didSet { save(); shelf?.renderer.renderScale = renderScale; shelf?.wake() } }
    var motionSpeed: Double { didSet { save(); shelf?.perform { [motionSpeed] in $0.animationSpeed = motionSpeed } } }
    var playIntro: Bool { didSet { save() } }

    let player: PlaybackEngine
    let shelf: ShelfController?
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        theme = Theme(rawValue: defaults.string(forKey: "rhine.theme") ?? "") ?? .day
        sortMode = SortMode(rawValue: defaults.string(forKey: "rhine.sort") ?? "") ?? .genre
        playlistId = defaults.string(forKey: "rhine.playlist")
        idleMotion = defaults.object(forKey: "rhine.idle") as? Bool ?? false
        focusDepth = defaults.object(forKey: "rhine.focus") as? Bool ?? true
        decryption = defaults.object(forKey: "rhine.decryption") as? Bool ?? false
        renderScale = defaults.object(forKey: "rhine.renderScale") as? Double ?? 1
        motionSpeed = defaults.object(forKey: "rhine.speed") as? Double ?? 1
        playIntro = defaults.object(forKey: "rhine.intro") as? Bool ?? true
        player = PlaybackEngine(bgm: Bundle.main.url(forResource: "observatory-preview", withExtension: "mp3"))
        shelf = Bundle.main.url(forResource: "music-case-v040", withExtension: "glb").flatMap(ShelfController.init(glb:))
        shelf?.renderer.renderScale = renderScale
        shelf?.scene.idleEnabled = idleMotion
        shelf?.scene.focusDepth = focusDepth
        shelf?.scene.decryption = decryption
        shelf?.scene.animationSpeed = motionSpeed
        shelf?.scene.theme(night: theme == .night, immediate: true)
        shelf?.onPick = { [weak self] key in self?.pick(key) }
        shelf?.onNavigate = { [weak self] axis, direction in
            guard let self else { return }
            if axis == "detail" { if self.mode == .detail { self.navigateDetail(direction) } }
            else { self.navigate(axis: axis, direction: direction) }
        }
        shelf?.onPhase = { [weak self] phase in self?.phase = phase }
        shelf?.onActivate = { [weak self] in self?.activateSelected() }
        player.onCurrentChange = { [weak self] _ in self?.currentSongChanged() }
        restoreSession()
    }

    private func save() {
        defaults.set(idleMotion, forKey: "rhine.idle")
        defaults.set(focusDepth, forKey: "rhine.focus")
        defaults.set(decryption, forKey: "rhine.decryption")
        defaults.set(renderScale, forKey: "rhine.renderScale")
        defaults.set(motionSpeed, forKey: "rhine.speed")
        defaults.set(playIntro, forKey: "rhine.intro")
    }

    // MARK: Session

    var serverURL: String { defaults.string(forKey: "rhine.url") ?? "" }
    var username: String { defaults.string(forKey: "rhine.user") ?? "" }
    var signedIn: Bool { client != nil }

    private func restoreSession() {
        let env = ProcessInfo.processInfo.environment
        if let url = env["RHINE_URL"], let user = env["RHINE_USER"], let pass = env["RHINE_PASS"] {
            // Development launch (simctl SIMCTL_CHILD_*): never persisted.
            connect(url: url, user: user, password: pass)
            #if DEBUG
            if let script = env["RHINE_SCRIPT"] { run(script) }
            #endif
            return
        }
        guard !serverURL.isEmpty, !username.isEmpty, let password = Keychain.password(for: username) else { return }
        connect(url: serverURL, user: username, password: password)
        #if DEBUG
        if let script = env["RHINE_SCRIPT"] { run(script) }
        #endif
    }

    func signIn(url: String, user: String, password: String) {
        loggingIn = true
        loginError = nil
        Task {
            var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.contains("://") { text = "http://" + text }
            guard let base = URL(string: text) else { loginError = "服务器地址无效"; loggingIn = false; return }
            let candidate = SubsonicClient(credentials: .init(baseURL: base, username: user, password: password))
            do {
                _ = try await candidate.ping()
                defaults.set(text, forKey: "rhine.url")
                defaults.set(user, forKey: "rhine.user")
                Keychain.set(password, for: user)
                adopt(candidate)
            } catch {
                loginError = error.localizedDescription
            }
            loggingIn = false
        }
    }

    func signOut() {
        player.stop()
        Keychain.remove(username)
        defaults.removeObject(forKey: "rhine.user")
        client = nil
        player.client = nil
        catalogue = []; groups = []; groupLists = []; groupOffsets = []; favoriteCount = nil
        layout = LibraryLayout(albums: [], mode: sortMode)
        details = [:]
        playlists = []
    }

    private func connect(url: String, user: String, password: String) {
        guard let base = URL(string: url) else { return }
        adopt(SubsonicClient(credentials: .init(baseURL: base, username: user, password: password)))
    }

    private func adopt(_ client: SubsonicClient) {
        self.client = client
        player.client = client
        shelf?.covers.client = client
        if let cached = LibraryCache.load(), !cached.isEmpty { catalogue = cached; apply(keepSelection: false) }
        booting = playIntro
        Task { await refresh() }
    }

    // MARK: Library

    func refresh() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            let albums = try await client.allAlbums()
            LibraryCache.save(albums)
            catalogue = albums
            if sortMode.usesGroups { try await loadGroups(sortMode) }
            apply(keepSelection: true)
            libraryError = nil
            playlists = (try? await client.playlists()) ?? playlists
            if favoriteCount == nil { favoriteCount = (try? await client.starred())?.song?.count }
        } catch {
            libraryError = error.localizedDescription
        }
    }

    /// List modes show one list in its server order, cut into consecutive 12-card columns, so reading
    /// column by column, top to bottom, is the list order. 我喜欢 = starred songs (newest first);
    /// a playlist arrangement = that one playlist.
    private func loadGroups(_ mode: SortMode) async throws {
        guard let client else { return }
        let songs: [Song]
        if mode == .playlists {
            if playlists.isEmpty { playlists = try await client.playlists() }
            guard let id = playlists.first(where: { $0.id == playlistId })?.id ?? playlists.first?.id else {
                groups = []; groupLists = []; groupOffsets = []; return
            }
            playlistId = id
            songs = (try await client.playlist(id: id).entry ?? []).filter { $0.albumId != nil }
        } else {
            songs = (try await client.starred().song ?? []).filter { $0.albumId != nil }
            favoriteCount = songs.count
        }
        var names: [String] = [], ids: [[String]] = [], lists: [[Song]] = [], offsets: [Int] = []
        let per = Self.favoritesPerColumn
        for start in stride(from: 0, to: songs.count, by: per) {
            let end = min(start + per, songs.count)
            names.append(String(format: "%03d–%03d", start + 1, end))
            ids.append(songs[start..<end].compactMap(\.albumId)); lists.append(songs); offsets.append(start)
        }
        groups = zip(names, ids).map { LibraryGroup(name: $0, albumIds: $1) }
        groupLists = lists
        groupOffsets = offsets
    }

    /// Playlist shown by the playlist arrangement.
    private(set) var playlistId: String?

    /// "按流派" / "我喜欢" / the playlist's name.
    var arrangementName: String {
        sortMode == .playlists ? (playlists.first { $0.id == playlistId }?.name ?? "歌单") : sortMode.name
    }

    private func apply(keepSelection: Bool) {
        let previous = layout.albumId(for: selectedId)
        let next = LibraryLayout(albums: catalogue, mode: sortMode, groups: sortMode.usesGroups ? groups : [])
        layout = next
        // Artwork is keyed by cover id, so repeated album covers share one atlas slot.
        shelf?.covers.coverIds = [:]
        var titles: [String: String] = [:]
        for album in catalogue { titles[album.coverArt ?? album.id] = album.name }
        shelf?.covers.titles = titles
        shelf?.scene.coverKey = { [weak self] key in
            guard let album = self?.layout.album(key) else { return key }
            return album.coverArt ?? album.id
        }
        if !keepSelection || next.album(selectedId) == nil {
            selectedId = (keepSelection ? previous.flatMap(next.key(forAlbum:)) : nil) ?? next.columns.first?.first ?? ""
        }
        let key = selectedId
        shelf?.perform { $0.setLibrary(next.columns, selected: key) }
        updatePlayingGlow()
        if let id = next.albumId(for: key) { Task { await loadDetail(id) } }
    }

    /// `playlist` picks which playlist the playlist arrangement shows.
    func setSort(_ mode: SortMode, playlist: String? = nil) {
        let newPlaylist = mode == .playlists && playlist != nil && playlist != playlistId
        guard mode != sortMode || newPlaylist else { return }
        sortMode = mode
        defaults.set(mode.rawValue, forKey: "rhine.sort")
        if mode == .playlists, let playlist { playlistId = playlist; defaults.set(playlist, forKey: "rhine.playlist") }
        guard mode.usesGroups else { apply(keepSelection: true); return }
        Task {
            loading = true
            defer { loading = false }
            do { try await loadGroups(mode); libraryError = nil } catch { libraryError = error.localizedDescription }
            guard sortMode == mode else { return }
            apply(keepSelection: true)
        }
    }

    var selected: Album? { layout.album(selectedId) }
    var selectedLane: Int { layout.lane(of: selectedId) ?? 0 }

    @discardableResult
    func loadDetail(_ id: String) async -> Album? {
        if let album = details[id], album.song != nil { return album }
        guard let client, let album = try? await client.album(id: id) else { return nil }
        details[id] = album
        return album
    }

    private func parse(_ key: String) -> (group: Int, index: Int)? {
        guard sortMode.usesGroups, let bar = key.firstIndex(of: "|"),
              let n = Int(key[..<bar]), let i = Int(key[key.index(after: bar)...]), groupLists.indices.contains(n) else { return nil }
        return (n, i)
    }

    /// The whole playlist / liked list a list-mode card belongs to.
    func listSongs(for key: String) -> [Song] { parse(key).map { groupLists[$0.group] } ?? [] }

    /// Position of a list-mode card in its full list (0-based) and the list length.
    func listPosition(for key: String) -> (index: Int, total: Int)? {
        guard let p = parse(key) else { return nil }
        return (groupOffsets[p.group] + p.index, groupLists[p.group].count)
    }

    /// The song a list-mode card stands for (nil for album cards and catalogue modes).
    func song(for key: String) -> Song? {
        guard let p = parse(key), let position = listPosition(for: key) else { return nil }
        let list = groupLists[p.group]
        return list.indices.contains(position.index) ? list[position.index] : nil
    }

    /// Card key of song `index` in the list that `key` belongs to (crosses columns).
    private func listKey(near key: String, index: Int) -> String? {
        guard parse(key) != nil else { return nil }
        let per = Self.favoritesPerColumn
        return "\(index / per)|\(index % per)"
    }

    var selectedSong: Song? { song(for: selectedId) }

    // MARK: Navigation (music-app.ts select / open / back)

    func select(_ key: String, axis: String = "", direction: Int = 0, immediate: Bool = false) {
        guard layout.album(key) != nil, key != selectedId || immediate else { return }
        selectedId = key
        shelf?.perform { $0.select(key, immediate: immediate, axis: axis, direction: direction) }
        if let id = layout.albumId(for: key) { Task { await loadDetail(id) } }
    }

    /// Search results and the now-playing card refer to albums; find their card on the current shelf.
    @discardableResult
    func selectAlbum(_ id: String) -> Bool {
        guard let key = layout.key(forAlbum: id) else { return false }
        select(key, immediate: true)
        return true
    }

    func navigate(axis: String, direction: Int) {
        touched()
        guard mode == .archive, !overview, let shelf, let next = shelf.scene.neighbour(axis: axis, direction: direction) else { return }
        select(next, axis: axis, direction: direction)
    }

    /// Steps to the neighbouring column's album (genre stepper); also works inside the overview.
    func stepLane(_ direction: Int, inOverview: Bool = false) {
        guard inOverview, overview else { navigate(axis: "lane", direction: direction); return }
        guard let shelf, let next = shelf.scene.neighbour(axis: "lane", direction: direction) else { return }
        select(next, axis: "lane", direction: direction)
    }

    /// Tapping a card brings that card forward: select it and open its detail in one motion.
    /// (Upstream only re-centred the shelf on the first tap, which reads as the card sliding away.)
    func pick(_ key: String) {
        touched()
        if overview { enterFromOverview(key); return }
        guard mode == .archive else { return }
        select(key)
        open()
    }

    func open() {
        guard !selectedId.isEmpty else { return }
        overview = false
        mode = .detail
        shelf?.mode = .detail
        shelf?.perform { $0.setMode(.detail) }
    }

    func back() {
        mode = .archive
        shelf?.mode = .archive
        shelf?.perform { $0.setMode(.archive) }
    }

    func toggleOverview() {
        guard mode == .archive else { return }
        overview.toggle()
        let active = overview
        shelf?.perform { $0.setOverview(active) }
    }

    func enterFromOverview(_ key: String) {
        overview = false
        shelf?.perform { $0.setOverview(false) }
        select(key, immediate: true)
    }

    func toggleTheme() {
        theme = theme == .day ? .night : .day
        defaults.set(theme.rawValue, forKey: "rhine.theme")
        let night = theme == .night
        shelf?.perform { $0.theme(night: night) }
    }

    /// Opening film is on screen (top bar and overlay hidden, like upstream's inert stage).
    private(set) var booting = false

    /// App time 4 s: the native wave starts at scene 21.92 and runs ×1.3 to 27.12 at 8 s.
    func startIntroScene() {
        guard booting else { return }
        shelf?.perform { $0.intro(active: true, time: 21.92, speed: 1.3) }
    }

    func finishBoot() {
        guard booting else { return }
        shelf?.perform { $0.intro(active: false) }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.72)) { booting = false }
    }

    func skipIntro() {
        shelf?.perform { $0.intro(active: false) }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.72)) { booting = false }
    }

    // MARK: Playback

    func play(album id: String, from index: Int = 0) {
        Task {
            guard let album = await loadDetail(id), let songs = album.song, !songs.isEmpty else { return }
            player.play(songs, startAt: index)
        }
    }

    func play(playlist: Playlist, from index: Int = 0) {
        Task {
            guard let client, let full = try? await client.playlist(id: playlist.id), let songs = full.entry, !songs.isEmpty else { return }
            player.play(songs, startAt: index)
        }
    }

    /// List modes: play the whole playlist / liked column, starting at this card's album.
    func playList(from key: String) {
        let songs = listSongs(for: key)
        guard !songs.isEmpty else { play(album: layout.albumId(for: key) ?? key); return }
        player.play(songs, startAt: listPosition(for: key)?.index ?? 0)
    }

    func toggleStar(_ song: Song) {
        Task {
            guard let client else { return }
            try? await client.star(id: song.id, song.starred == nil)
            if let id = song.albumId { details[id] = nil; await loadDetail(id) }
            if sortMode == .favorites, (try? await loadGroups(.favorites)) != nil { apply(keepSelection: true) }
        }
    }

    #if DEBUG
    /// Screenshot driver: comma-separated steps, e.g. "wait:3,night,open,wait:4,play,nowplaying".
    private func run(_ script: String) {
        Task {
            for step in script.split(separator: ",").map(String.init) {
                let parts = step.split(separator: ":").map(String.init)
                let arg = parts.count > 1 ? parts[1] : ""
                switch parts[0] {
                case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
                case "nointro": skipIntro()
                case "night": if theme == .day { toggleTheme() }
                case "day": if theme == .night { toggleTheme() }
                case "sort": if let mode = SortMode(rawValue: arg) { setSort(mode) }
                case "open": open()
                case "back": back()
                case "overview": toggleOverview()
                case "down": navigate(axis: "row", direction: 1)
                case "lane": navigate(axis: "lane", direction: 1)
                case "play": play(album: layout.albumId(for: selectedId) ?? selectedId)
                case "nowplaying": openPlaying()
                case "drawer": setArrangements(true)
                case "panel": panel = ["library": .library, "search": .search, "settings": .settings, "playlists": .playlists][arg]
                default: break
                }
            }
        }
    }
    #endif

    /// ↑ 上一张 / 下一张 ↓ inside the detail view: switch album without leaving detail.
    func navigateDetail(_ direction: Int) {
        touched()
        guard let shelf else { return }
        var next: String?
        var axis = "row"
        if let position = listPosition(for: selectedId) {
            // List modes follow the list, across favourite columns, skipping songs whose album is unknown.
            var index = position.index
            for _ in 0..<position.total {
                index = (index + direction + position.total) % position.total
                if let key = listKey(near: selectedId, index: index), layout.album(key) != nil { next = key; break }
            }
            if let next, layout.lane(of: next) != selectedLane { axis = "" }
        } else {
            next = shelf.scene.neighbour(axis: "row", direction: direction)
        }
        guard let next, next != selectedId else { return }
        moveDetail(to: next, axis: axis, direction: direction)
    }

    private func moveDetail(to next: String, axis: String, direction: Int) {
        guard let shelf else { return }
        selectedId = next
        shelf.perform { $0.select(next, immediate: false, axis: axis, direction: direction) }
        if let id = layout.albumId(for: next) { Task { await loadDetail(id) } }
    }

    // MARK: Now playing on the shelf

    @ObservationIgnored private var lastInteraction = Date.distantPast
    private func touched() { lastInteraction = Date() }

    /// Card of the playing song on the current shelf (prefers the list being browsed), or nil.
    var playingKey: String? {
        guard let song = player.current else { return nil }
        guard sortMode.usesGroups else { return song.albumId.flatMap(layout.key(forAlbum:)) }
        let preferred = parse(selectedId)?.group
        for group in (preferred.map { [$0] } ?? []) + Array(groupLists.indices) {
            guard let index = groupLists[group].firstIndex(where: { $0.id == song.id }),
                  let key = listKey(near: sortMode == .favorites ? "0|0" : "\(group)|0", index: index),
                  layout.album(key) != nil else { continue }
            return key
        }
        return nil
    }

    private func direction(to key: String) -> Int {
        (layout.ordinal(key) ?? 0) >= (layout.ordinal(selectedId) ?? 0) ? 1 : -1
    }

    /// "正在播放 ↩": bring the playing song's card back into the close-up (or centre it on the shelf).
    func jumpToPlaying() {
        guard let key = playingKey, key != selectedId else { return }
        touched()
        let axis = layout.lane(of: key) == selectedLane ? "row" : ""
        if mode == .detail { moveDetail(to: key, axis: axis, direction: direction(to: key)) }
        else { select(key, axis: axis, direction: direction(to: key)) }
    }

    /// Every card showing the playing song gets the accent edge light.
    private func updatePlayingGlow() {
        var keys = Set<String>()
        if let song = player.current {
            if sortMode.usesGroups {
                for key in layout.columns.joined() where self.song(for: key)?.id == song.id { keys.insert(key) }
            } else if let id = song.albumId, let key = layout.key(forAlbum: id) {
                keys.insert(key)
            }
        }
        shelf?.perform { $0.playingKeys = keys }
    }

    /// Explicit previous / next: switch the song and always bring its card along (also under shuffle).
    func skipTrack(_ direction: Int) {
        guard player.current != nil else { navigateDetail(direction); return }
        touched()
        followNext = true
        if direction > 0 { player.next() } else { player.previous(restart: false) }
    }

    @ObservationIgnored private var followNext = false

    /// Follow playback like a stylus: when the song changes after an explicit skip, or while the user
    /// has been idle for 8 s, the selection moves to the new song's card.
    private func currentSongChanged() {
        updatePlayingGlow()
        let follow = followNext || Date().timeIntervalSince(lastInteraction) > 8
        followNext = false
        guard follow, panel == nil, !overview, !booting,
              let key = playingKey, key != selectedId else { return }
        let axis = layout.lane(of: key) == selectedLane ? "row" : ""
        if mode == .detail { moveDetail(to: key, axis: axis, direction: direction(to: key)) }
        else { select(key, axis: axis, direction: direction(to: key)) }
    }

    /// Right-hand list tap in list modes: bring that song's card up in the close-up.
    func focusListSong(_ index: Int) {
        touched()
        guard let current = listPosition(for: selectedId), index != current.index,
              let key = listKey(near: selectedId, index: index), layout.album(key) != nil else { return }
        moveDetail(to: key, axis: layout.lane(of: key) == selectedLane ? "row" : "", direction: index > current.index ? 1 : -1)
    }

    /// Tap on the fully presented close-up card: play it (list modes play the list from this song).
    func activateSelected() {
        guard mode == .detail, phase == .presented, !selectedId.isEmpty else { return }
        if sortMode.usesGroups { playList(from: selectedId) } else if let id = layout.albumId(for: selectedId) { play(album: id) }
    }

    /// Top-bar now-playing title: open the close-up on the playing song's card.
    func openPlaying() {
        touched()
        setArrangements(false)
        if let key = playingKey {
            if mode == .detail { jumpToPlaying(); return }
            select(key, immediate: overview)
        } else if let id = player.current?.albumId, !selectAlbum(id) {
            return
        }
        open()
    }

    /// Left-edge drawer with the shelf arrangements (hidden by default).
    private(set) var arrangementsOpen = false
    func setArrangements(_ open: Bool) { arrangementsOpen = open }

    func add(_ songs: [Song], to playlist: Playlist) {
        Task {
            guard let client else { return }
            try? await client.updatePlaylist(id: playlist.id, add: songs.map(\.id))
            await reloadPlaylists()
        }
    }

    func createPlaylist(_ name: String, songs: [Song] = []) {
        Task {
            guard let client, !name.isEmpty else { return }
            try? await client.createPlaylist(name: name, songIds: songs.map(\.id))
            await reloadPlaylists()
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        Task {
            guard let client else { return }
            try? await client.deletePlaylist(id: playlist.id)
            await reloadPlaylists()
        }
    }

    func reloadPlaylists() async {
        guard let client else { return }
        playlists = (try? await client.playlists()) ?? playlists
        if sortMode == .playlists, (try? await loadGroups(.playlists)) != nil { apply(keepSelection: true) }
    }
}
