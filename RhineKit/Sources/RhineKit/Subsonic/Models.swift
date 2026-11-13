import Foundation

/// Subsonic / Navidrome 0.47 response models (subset used by the app).
public struct Album: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let artist: String?
    public let artistId: String?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    public let songCount: Int?
    public let duration: Int?
    public let created: String?
    public var song: [Song]?
}

public struct Song: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let album: String?
    public let albumId: String?
    public let artist: String?
    public let track: Int?
    public let discNumber: Int?
    public let year: Int?
    public let genre: String?
    public let coverArt: String?
    public let duration: Int?
    public let bitRate: Int?
    public let suffix: String?
    public let contentType: String?
    public let starred: String?
}

public struct Genre: Codable, Hashable, Sendable {
    public let value: String
    public let songCount: Int?
    public let albumCount: Int?
}

public struct Playlist: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let songCount: Int?
    public let duration: Int?
    public let owner: String?
    public let coverArt: String?
    public let changed: String?
    public var entry: [Song]?
}

public struct SearchResult: Codable, Sendable {
    public var album: [Album]?
    public var song: [Song]?

    public init(album: [Album]? = nil, song: [Song]? = nil) {
        self.album = album
        self.song = song
    }
}

public struct Lyrics: Codable, Sendable {
    public let artist: String?
    public let title: String?
    public let value: String?
}

/// Envelope for `{"subsonic-response": {...}}`.
struct Envelope<Body: Decodable>: Decodable {
    let response: Body
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}

struct ResponseBody: Decodable {
    struct Failure: Decodable { let code: Int; let message: String? }
    let status: String
    let error: Failure?
    let serverVersion: String?
    let albumList2: AlbumList?
    let album: Album?
    let genres: GenreList?
    let playlists: PlaylistList?
    let playlist: Playlist?
    let searchResult3: SearchResult?
    let lyrics: Lyrics?
    let starred2: SearchResult?

    struct AlbumList: Decodable { let album: [Album]? }
    struct GenreList: Decodable { let genre: [Genre]? }
    struct PlaylistList: Decodable { let playlist: [Playlist]? }
}
