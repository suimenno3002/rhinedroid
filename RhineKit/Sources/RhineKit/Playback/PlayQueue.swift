/// Play order with shuffle / repeat. Pure value type; the engine only asks it what comes next.
public struct PlayQueue: Sendable, Equatable {
    public enum Repeat: String, Sendable, CaseIterable { case off, all, one }

    public private(set) var songs: [Song] = []
    /// Indices into `songs` in play order (identity unless shuffled).
    public private(set) var order: [Int] = []
    /// Index into `order`.
    public private(set) var position = 0
    public private(set) var shuffled = false
    public var repeatMode: Repeat = .off

    public init() {}

    public init(songs: [Song], start: Int = 0, shuffled: Bool = false) {
        self.songs = songs
        order = Array(songs.indices)
        position = songs.indices.contains(start) ? start : 0
        if shuffled { setShuffle(true) }
    }

    public var current: Song? { order.indices.contains(position) ? songs[order[position]] : nil }
    public var isEmpty: Bool { songs.isEmpty }
    /// Songs in play order from the current one on (for the queue list).
    public var upcoming: ArraySlice<Int> { order.indices.contains(position) ? order[position...] : [] }

    /// Position the player moves to when the current song ends by itself.
    public func autoNext() -> Int? {
        guard !order.isEmpty else { return nil }
        if repeatMode == .one { return position }
        if position + 1 < order.count { return position + 1 }
        return repeatMode == .all ? 0 : nil
    }

    /// Song that will play after the current one ends (for gapless pre-buffering).
    public var autoNextSong: Song? { autoNext().map { songs[order[$0]] } }

    /// Natural end of the current song.
    @discardableResult
    public mutating func finish() -> Song? {
        guard let next = autoNext() else { position = order.count; return nil }
        position = next
        return current
    }

    /// User pressed next: repeat-one does not trap the user on one song.
    @discardableResult
    public mutating func skip() -> Song? {
        guard !order.isEmpty else { return nil }
        if position + 1 < order.count { position += 1 } else if repeatMode != .off { position = 0 } else { return nil }
        return current
    }

    @discardableResult
    public mutating func back() -> Song? {
        guard !order.isEmpty else { return nil }
        if position > 0 { position -= 1 } else if repeatMode != .off { position = order.count - 1 }
        return current
    }

    /// Jump to a song by its index in `songs`.
    public mutating func jump(toSong index: Int) {
        guard let p = order.firstIndex(of: index) else { return }
        position = p
    }

    /// Shuffling keeps the current song playing and randomises the rest after it; turning it off
    /// returns to album order at the current song.
    public mutating func setShuffle(_ on: Bool) {
        guard on != shuffled || (on && order == Array(songs.indices)) else { return }
        shuffled = on
        let currentIndex = current.flatMap { _ in order[position] }
        if on {
            var rest = songs.indices.filter { $0 != currentIndex }
            rest.shuffle()
            order = (currentIndex.map { [$0] } ?? []) + rest
            position = 0
        } else {
            order = Array(songs.indices)
            position = currentIndex ?? 0
        }
    }

    /// Inserts songs right after the current one.
    public mutating func playNext(_ added: [Song]) {
        let start = songs.count
        songs += added
        order.insert(contentsOf: start..<songs.count, at: min(position + 1, order.count))
    }

    public mutating func append(_ added: [Song]) {
        let start = songs.count
        songs += added
        order += start..<songs.count
    }

    /// Removes the song at `orderIndex` (not the current one).
    public mutating func remove(at orderIndex: Int) {
        guard order.indices.contains(orderIndex), orderIndex != position else { return }
        let removed = order.remove(at: orderIndex)
        if orderIndex < position { position -= 1 }
        songs.remove(at: removed)
        order = order.map { $0 > removed ? $0 - 1 : $0 }
    }
}
