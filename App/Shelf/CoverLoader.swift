import Foundation
import RhineKit

/// Fetches covers through Navidrome's server-side resizing (256² atlas tiles, 1024² hi-res covers for
/// the window around the selection), keeps them in a disk cache keyed by cover id, decodes off the main
/// thread and hands RGBA pixels to the renderer. Stale results are dropped by the scene's slot check.
@MainActor
final class CoverLoader {
    var client: SubsonicClient?
    var coverIds: [String: String] = [:]
    var titles: [String: String] = [:]
    var onTile: ((_ id: String, _ slot: Int, _ pixels: Data) -> Void)?
    var onHires: ((_ id: String, _ slot: Int, _ pixels: Data) -> Void)?
    var isWanted: ((_ id: String, _ slot: Int) -> Bool)?
    var isHiresWanted: ((_ id: String, _ slot: Int) -> Bool)?

    private var queue: [(id: String, slot: Int)] = []
    private var inflight = Set<String>()
    private var running = 0
    private let limit = 8

    // Hi-res covers decode one or two at a time, in the scene's priority order.
    private var hiresQueue: [(id: String, slot: Int)] = []
    private var hiresInflight = Set<String>()
    private var hiresRunning = 0
    private let hiresLimit = 2

    private static let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "covers", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func request(tiles: [(id: String, slot: Int)]) {
        // Newest request first; older entries that are still wanted stay behind it.
        queue = tiles + queue.filter { old in !tiles.contains { $0.id == old.id } }
        pump()
    }

    func requestHires(_ covers: [(id: String, slot: Int)]) {
        hiresQueue = covers + hiresQueue.filter { old in !covers.contains { $0.id == old.id } }
        pumpHires()
    }

    private func pump() {
        while running < limit, let next = queue.first {
            queue.removeFirst()
            guard !inflight.contains(next.id), isWanted?(next.id, next.slot) ?? true else { continue }
            inflight.insert(next.id); running += 1
            let cover = coverIds[next.id] ?? next.id, title = titles[next.id], client = client
            Task {
                let pixels = await Self.pixels(cover: cover, size: ArchiveRenderer.atlasTile, title: title, client: client)
                inflight.remove(next.id); running -= 1
                onTile?(next.id, next.slot, pixels)
                pump()
            }
        }
    }

    private func pumpHires() {
        while hiresRunning < hiresLimit, let next = hiresQueue.first {
            hiresQueue.removeFirst()
            guard !hiresInflight.contains(next.id), isHiresWanted?(next.id, next.slot) ?? true else { continue }
            hiresInflight.insert(next.id); hiresRunning += 1
            let cover = coverIds[next.id] ?? next.id, title = titles[next.id], client = client
            Task {
                let pixels = await Self.pixels(cover: cover, size: ArchiveRenderer.hiresSize, title: title, client: client)
                hiresInflight.remove(next.id); hiresRunning -= 1
                onHires?(next.id, next.slot, pixels)
                pumpHires()
            }
        }
    }

    nonisolated static func pixels(cover: String?, size: Int, title: String?, client: SubsonicClient?) async -> Data {
        let data = await fetch(cover: cover, size: size, client: client)
        return await Task.detached(priority: .userInitiated) { CoverArt.pixels(data, size: size, title: title) }.value
    }

    nonisolated static func fetch(cover: String?, size: Int, client: SubsonicClient?) async -> Data? {
        guard let cover else { return nil }
        let file = directory.appending(path: "\(cover.replacingOccurrences(of: "/", with: "_"))-\(size)")
        if let data = try? Data(contentsOf: file) { return data }
        guard let client, let (data, response) = try? await URLSession.shared.data(from: client.coverURL(id: cover, size: size)),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        try? data.write(to: file, options: .atomic)
        return data
    }
}
