// Column layout ported from RhineDroid web/src/data.ts and music-order.ts
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import Foundation

public enum SortMode: String, CaseIterable, Sendable, Codable {
    case genre, artist, album, playlists, favorites

    /// Labels from music-app.ts `sortLabels`, plus the two list modes added for Navidrome.
    public var name: String {
        switch self {
        case .genre: "按流派"; case .artist: "按歌手"; case .album: "按专辑"
        case .playlists: "按歌单"; case .favorites: "我喜欢"
        }
    }

    /// Column stepper code ("GENRE 01 / 03").
    public var code: String {
        switch self {
        case .genre: "GENRE"; case .artist: "ARTIST"; case .album: "ALBUMS"
        case .playlists: "LIST"; case .favorites: "LIKED"
        }
    }

    public var column: String {
        switch self {
        case .genre: "流派"; case .artist: "歌手"; case .album, .favorites, .playlists: "分组"
        }
    }

    /// Columns come from server lists (playlists, starred songs) instead of the album catalogue.
    public var usesGroups: Bool { self == .playlists || self == .favorites }
}

/// One shelf column built from a server list, in list order.
public struct LibraryGroup: Sendable, Equatable {
    public let name: String
    public let albumIds: [String]

    public init(name: String, albumIds: [String]) {
        self.name = name
        self.albumIds = albumIds
    }
}

/// Albums arranged into shelf columns. Pure value type, rebuilt whenever the album list or sort changes.
///
/// Columns hold shelf keys. Catalogue modes use the album id as key; list modes use "lane|albumId",
/// so one album can sit in several playlists without two cells sharing an identity.
public struct LibraryLayout: Sendable {
    public let mode: SortMode
    /// The whole catalogue (sorted in catalogue modes, server order in list modes).
    public let albums: [Album]
    /// Column display names (genre / artist / "01–12" ranges / playlist names).
    public let columnNames: [String]
    public let columns: [[String]]
    private let entries: [String: Album]
    private let ordinals: [String: Int]
    private let location: [String: (lane: Int, row: Int)]
    private let firstKey: [String: String]

    public init(albums input: [Album], mode: SortMode, groups: [LibraryGroup] = []) {
        self.mode = mode
        var names: [String] = [], columns: [[String]] = []
        var entries: [String: Album] = [:]
        var ordinals: [String: Int] = [:]
        if mode.usesGroups {
            albums = input
            let byId = Dictionary(input.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // One card per song, in list order: key "group|songIndex", entry = the song's album (cover).
            for (index, group) in groups.enumerated() {
                var column: [String] = []
                for (song, id) in group.albumIds.enumerated() {
                    guard let album = byId[id] else { continue }
                    let key = "\(index)|\(song)"
                    entries[key] = album
                    column.append(key)
                }
                if !column.isEmpty { names.append(group.name); columns.append(column) }
            }
            for (i, key) in columns.joined().enumerated() { ordinals[key] = i }
        } else {
            let ordered = Self.order(input, mode)
            albums = ordered
            for (i, album) in ordered.enumerated() { entries[album.id] = album; ordinals[album.id] = i }
            switch mode {
            case .artist:
                var lanes: [String: Int] = [:]
                for album in ordered {
                    let key = Self.normalize(album.artist ?? "")
                    if lanes[key] == nil {
                        lanes[key] = names.count
                        let name = (album.artist ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
                        names.append(name.isEmpty ? "未知歌手" : name); columns.append([])
                    }
                    columns[lanes[key]!].append(album.id)
                }
            case .album:
                for start in stride(from: 0, to: ordered.count, by: 12) {
                    let end = min(start + 12, ordered.count)
                    names.append(String(format: "%02d–%02d", start + 1, end))
                    columns.append(ordered[start..<end].map(\.id))
                }
            default:
                // First-seen genre order, like upstream's genre id list.
                var lanes: [String: Int] = [:]
                for album in ordered {
                    let genre = Self.genreName(album)
                    if lanes[genre] == nil { lanes[genre] = names.count; names.append(genre); columns.append([]) }
                    columns[lanes[genre]!].append(album.id)
                }
            }
        }
        columnNames = names
        self.columns = columns
        self.entries = entries
        self.ordinals = ordinals
        var location: [String: (Int, Int)] = [:], firstKey: [String: String] = [:]
        for (lane, column) in columns.enumerated() {
            for (row, key) in column.enumerated() {
                location[key] = (lane, row)
                if let id = entries[key]?.id, firstKey[id] == nil { firstKey[id] = key }
            }
        }
        self.location = location
        self.firstKey = firstKey
    }

    public func album(_ key: String) -> Album? { entries[key] }
    public func albumId(for key: String) -> String? { entries[key]?.id }
    /// First shelf key showing this album (search results, now-playing locate).
    public func key(forAlbum id: String) -> String? { firstKey[id] }
    /// 0-based position for the "ALBUM 001" counter.
    public func ordinal(_ key: String) -> Int? { ordinals[key] }
    public func lane(of key: String) -> Int? { location[key]?.lane }
    public func row(of key: String) -> Int? { location[key]?.row }

    public static func genreName(_ album: Album) -> String {
        let g = album.genre?.trimmingCharacters(in: .whitespaces) ?? ""
        return g.isEmpty ? "未分类" : g
    }

    static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased(with: Locale(identifier: "zh_CN"))
    }

    /// zh_CN collation in ICU is pinyin, matching `Intl.Collator("zh-CN-u-co-pinyin", {numeric, sensitivity: base})`.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive, .numeric],
                  range: nil, locale: Locale(identifier: "zh_CN"))
    }

    static func order(_ albums: [Album], _ mode: SortMode) -> [Album] {
        guard mode == .artist || mode == .album else { return albums }
        return albums.sorted { a, b in
            if mode == .artist {
                let x = normalize(a.artist ?? ""), y = normalize(b.artist ?? "")
                let c = compare(x, y)
                if c != .orderedSame { return c == .orderedAscending }
                if x != y { return x < y }
            }
            let c = compare(normalize(a.name), normalize(b.name))
            return c == .orderedSame ? a.id < b.id : c == .orderedAscending
        }
    }
}

/// Album list snapshot on disk so launch shows the shelf before the network answers.
public enum LibraryCache {
    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "rhine-library.json")
    }

    public static func load() -> [Album]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Album].self, from: data)
    }

    public static func save(_ albums: [Album]) {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
