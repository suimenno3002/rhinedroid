// Live smoke test against a Navidrome server. Credentials come from the environment only:
//   RHINE_URL=http://host:4533 RHINE_USER=... RHINE_PASS=... swift run rhine-probe
import Foundation
import RhineKit

let env = ProcessInfo.processInfo.environment
guard let base = env["RHINE_URL"].flatMap(URL.init(string:)), let user = env["RHINE_USER"], let pass = env["RHINE_PASS"] else {
    print("set RHINE_URL / RHINE_USER / RHINE_PASS"); exit(2)
}
let client = SubsonicClient(credentials: .init(baseURL: base, username: user, password: pass))

func check(_ label: String, _ body: () async throws -> String) async {
    let start = Date()
    do { print("✔ \(label): \(try await body()) (\(Int(Date().timeIntervalSince(start) * 1000)) ms)") }
    catch { print("✘ \(label): \(error)"); exit(1) }
}

await check("ping") { try await client.ping() ?? "?" }
var albums: [Album] = []
await check("allAlbums") { albums = try await client.allAlbums(); return "\(albums.count) albums, covers: \(albums.filter { $0.coverArt != nil }.count)" }
await check("genres") { "\(try await client.genres().count) genres" }
var detail: Album?
await check("album") {
    detail = try await client.album(id: albums.first!.id)
    let s = detail!.song ?? []
    return "\(detail!.name): \(s.count) songs, suffixes \(Set(s.compactMap(\.suffix)).sorted())"
}
await check("playlists") { try await client.playlists().map { "\($0.name)(\($0.songCount ?? 0))" }.joined(separator: ", ") }
await check("search3") { let r = try await client.search("ARIA"); return "\(r.album?.count ?? 0) albums, \(r.song?.count ?? 0) songs" }

// Lyric coverage on a sample of songs: how many carry embedded (and timed) lyrics.
await check("lyrics sample") {
    var hit = 0, timed = 0, tried = 0
    for album in albums.shuffled().prefix(6) {
        for song in (try await client.album(id: album.id).song ?? []).prefix(3) {
            tried += 1
            if let text = try await client.lyrics(artist: song.artist ?? "", title: song.title) {
                hit += 1
                if LyricsParser.parse(text).first?.time != nil { timed += 1 }
            }
        }
    }
    return "\(hit)/\(tried) have lyrics, \(timed) timed"
}

await check("cover 128") {
    let (data, response) = try await URLSession.shared.data(from: client.coverURL(id: albums.first!.coverArt!, size: 128))
    return "\((response as? HTTPURLResponse)?.statusCode ?? 0) \((response as? HTTPURLResponse)?.mimeType ?? "") \(data.count) bytes"
}
if env["RHINE_PLAY"] != nil {
    // Muted end-to-end playback: start, verify progress, then a faded skip.
    let engine = await MainActor.run { () -> PlaybackEngine in
        let e = PlaybackEngine(defaults: UserDefaults(suiteName: "rhine-probe")!)
        e.client = client
        e.setVolume(0)
        e.play(detail!.song!, startAt: 0)
        return e
    }
    await check("play") {
        try await Task.sleep(for: .seconds(5))
        return await MainActor.run { "\(engine.transport) t=\(String(format: "%.1f", engine.currentTime)) \(engine.current?.title ?? "-")" }
    }
    await check("next (fade)") {
        await MainActor.run { engine.next() }
        try await Task.sleep(for: .seconds(4))
        return await MainActor.run { "\(engine.transport) t=\(String(format: "%.1f", engine.currentTime)) \(engine.current?.title ?? "-") pos=\(engine.queue.position)" }
    }
    await MainActor.run { engine.stop() }
}

await check("stream head") {
    var request = URLRequest(url: client.streamURL(id: detail!.song!.first!.id))
    request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = response as! HTTPURLResponse
    return "\(http.statusCode) \(http.mimeType ?? "") \(data.count) bytes, accept-ranges=\(http.value(forHTTPHeaderField: "Accept-Ranges") ?? "-")"
}
