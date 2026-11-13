import CryptoKit
import Foundation

public struct ServerCredentials: Sendable, Equatable {
    public var baseURL: URL
    public var username: String
    public var password: String

    public init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }
}

public enum SubsonicError: Error, LocalizedError, Equatable {
    case server(code: Int, message: String)
    case http(Int)
    case malformed

    public var errorDescription: String? {
        switch self {
        case let .server(code, message): "Navidrome \(code): \(message)"
        case let .http(status): "HTTP \(status)"
        case .malformed: "无法解析服务器响应"
        }
    }
}

/// Minimal Subsonic API 1.16.1 client. Uses token+salt auth so the password never travels in clear
/// (the LAN server is plain HTTP).
public final class SubsonicClient: Sendable {
    public let credentials: ServerCredentials
    private let session: URLSession
    static let apiVersion = "1.16.1"
    static let clientName = "RhinePad"

    public init(credentials: ServerCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    static func token(password: String, salt: String) -> String {
        Insecure.MD5.hash(data: Data((password + salt).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Builds a signed REST URL. Also used directly for `stream` and `getCoverArt` so AVPlayer / image
    /// loaders can fetch without going through this class.
    public func url(_ endpoint: String, _ query: [String: String] = [:]) -> URL {
        let salt = String((0..<12).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        var components = URLComponents(url: credentials.baseURL.appending(path: "rest/\(endpoint).view"),
                                       resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "u", value: credentials.username),
            URLQueryItem(name: "t", value: Self.token(password: credentials.password, salt: salt)),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: Self.apiVersion),
            URLQueryItem(name: "c", value: Self.clientName),
            URLQueryItem(name: "f", value: "json"),
        ]
        items += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        return components.url!
    }

    func call(_ endpoint: String, _ query: [String: String] = [:]) async throws -> ResponseBody {
        let (data, response) = try await session.data(from: url(endpoint, query))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.http(http.statusCode)
        }
        let body = try Self.decode(data)
        return body
    }

    static func decode(_ data: Data) throws -> ResponseBody {
        guard let body = try? JSONDecoder().decode(Envelope<ResponseBody>.self, from: data).response else {
            throw SubsonicError.malformed
        }
        if body.status != "ok" {
            throw SubsonicError.server(code: body.error?.code ?? 0, message: body.error?.message ?? "unknown")
        }
        return body
    }

    // MARK: - Endpoints

    public func ping() async throws -> String? { try await call("ping").serverVersion }

    /// Pages through `getAlbumList2` (max 500 per request) until the server runs dry.
    public func allAlbums(type: String = "alphabeticalByName") async throws -> [Album] {
        var result: [Album] = []
        let page = 500
        while true {
            let batch = try await call("getAlbumList2", ["type": type, "size": "\(page)", "offset": "\(result.count)"])
                .albumList2?.album ?? []
            result += batch
            if batch.count < page { return result }
        }
    }

    public func album(id: String) async throws -> Album {
        guard let album = try await call("getAlbum", ["id": id]).album else { throw SubsonicError.malformed }
        return album
    }

    public func genres() async throws -> [Genre] { try await call("getGenres").genres?.genre ?? [] }

    public func search(_ text: String, albums: Int = 20, songs: Int = 40) async throws -> SearchResult {
        try await call("search3", ["query": text, "albumCount": "\(albums)", "songCount": "\(songs)", "artistCount": "0"])
            .searchResult3 ?? SearchResult()
    }

    public func playlists() async throws -> [Playlist] { try await call("getPlaylists").playlists?.playlist ?? [] }

    public func playlist(id: String) async throws -> Playlist {
        guard let playlist = try await call("getPlaylist", ["id": id]).playlist else { throw SubsonicError.malformed }
        return playlist
    }

    public func createPlaylist(name: String, songIds: [String]) async throws {
        // Repeated `songId` keys are not expressible in a dictionary; append them manually.
        var components = URLComponents(url: url("createPlaylist", ["name": name]), resolvingAgainstBaseURL: false)!
        components.queryItems! += songIds.map { URLQueryItem(name: "songId", value: $0) }
        _ = try Self.decode(try await session.data(from: components.url!).0)
    }

    public func updatePlaylist(id: String, add: [String] = [], removeIndexes: [Int] = [], name: String? = nil) async throws {
        var query = ["playlistId": id]
        if let name { query["name"] = name }
        var components = URLComponents(url: url("updatePlaylist", query), resolvingAgainstBaseURL: false)!
        components.queryItems! += add.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        components.queryItems! += removeIndexes.map { URLQueryItem(name: "songIndexToRemove", value: "\($0)") }
        _ = try Self.decode(try await session.data(from: components.url!).0)
    }

    public func deletePlaylist(id: String) async throws { _ = try await call("deletePlaylist", ["id": id]) }

    /// Navidrome 0.47 has no OpenSubsonic `getLyricsBySongId`; `getLyrics` returns embedded tag text,
    /// which is often raw LRC. Parse it with `LyricsParser`.
    public func lyrics(artist: String, title: String) async throws -> String? {
        let value = try await call("getLyrics", ["artist": artist, "title": title]).lyrics?.value
        return value?.isEmpty == false ? value : nil
    }

    public func star(id: String, _ on: Bool = true) async throws { _ = try await call(on ? "star" : "unstar", ["id": id]) }

    public func starred() async throws -> SearchResult { try await call("getStarred2").starred2 ?? SearchResult() }

    public func scrobble(id: String, submission: Bool) async throws {
        _ = try await call("scrobble", ["id": id, "submission": submission ? "true" : "false"])
    }

    /// Raw original stream; Navidrome transcodes only when `format` is given.
    public func streamURL(id: String, transcodeTo format: String? = nil, maxBitRate: Int? = nil) -> URL {
        var query = ["id": id]
        if let format { query["format"] = format } else { query["format"] = "raw" }
        if let maxBitRate { query["maxBitRate"] = "\(maxBitRate)" }
        return url("stream", query)
    }

    public func coverURL(id: String, size: Int) -> URL { url("getCoverArt", ["id": id, "size": "\(size)"]) }
}
