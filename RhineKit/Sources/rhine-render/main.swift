// Offscreen render of the Metal shelf with a real Navidrome library, for visual checks without a device.
//   RHINE_URL=... RHINE_USER=... RHINE_PASS=... swift run rhine-render <glb> <out-dir> [width height]
import CoreGraphics
import Foundation
import ImageIO
import Metal
import RhineKit
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: rhine-render <glb> <out-dir> [width height]"); exit(2) }
let width = args.count > 4 ? Int(args[3])! : 2388
let height = args.count > 4 ? Int(args[4])! : 1668
let out = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let device = MTLCreateSystemDefaultDevice()!
let renderer = try ArchiveRenderer(device: device, glb: Data(contentsOf: URL(fileURLWithPath: args[1])), targetFormat: .rgba8Unorm_srgb)
let scene = renderer.scene

let env = ProcessInfo.processInfo.environment
let client = SubsonicClient(credentials: .init(baseURL: URL(string: env["RHINE_URL"]!)!, username: env["RHINE_USER"]!, password: env["RHINE_PASS"]!))
let albums = try await client.allAlbums()
var titles: [String: String] = [:]
var coverIds: [String: String] = [:]
for album in albums { titles[album.id] = album.name; coverIds[album.id] = album.coverArt }
// Genre mode: one column per genre in first-seen order (upstream data.ts).
var genreOrder: [String] = []
var byGenre: [String: [String]] = [:]
for album in albums {
    let genre = album.genre ?? "未分类"
    if byGenre[genre] == nil { genreOrder.append(genre) }
    byGenre[genre, default: []].append(album.id)
}
let columns = genreOrder.map { byGenre[$0]! }
print("library: \(albums.count) albums in \(columns.count) genre columns")

var requests: [[(id: String, slot: Int)]] = []
var hiresRequests: [(id: String, slot: Int)] = []
scene.onCoverRequest = { tiles in requests.append(tiles) }
scene.onHiresRequest = { covers in hiresRequests = covers }

func fetch(_ id: String, size: Int) async -> Data? {
    guard let cover = coverIds[id] else { return nil }
    return try? await URLSession.shared.data(from: client.coverURL(id: cover, size: size)).0
}

func serviceCovers() async {
    let pending = requests; requests.removeAll()
    var started = Date()
    var count = 0
    let hiPending = hiresRequests; hiresRequests.removeAll()
    for cover in hiPending where scene.isHiresWanted(id: cover.id, slot: cover.slot) {
        let pixels = CoverArt.pixels(await fetch(cover.id, size: 1024), size: ArchiveRenderer.hiresSize, title: titles[cover.id])
        if scene.hiresReady(id: cover.id, slot: cover.slot) { renderer.uploadHires(slot: cover.slot, pixels: pixels) }
    }
    for request in pending {
        await withTaskGroup(of: (String, Int, Data).self) { group in
            for tile in request where scene.isWanted(id: tile.id, slot: tile.slot) {
                group.addTask { (tile.id, tile.slot, CoverArt.pixels(await fetch(tile.id, size: 128), size: ArchiveRenderer.atlasTile, title: titles[tile.id])) }
            }
            for await (id, slot, pixels) in group where scene.coverTileReady(id: id, slot: slot) {
                renderer.uploadTile(slot: slot, pixels: pixels); count += 1
            }
        }
    }
    if count > 0 { print("covers: \(count) tiles in \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
    started = Date()
}

let target: MTLTexture = {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead]
    d.storageMode = .shared
    return device.makeTexture(descriptor: d)!
}()

func advance(_ seconds: Double, fps: Double = 120) {
    var t = 0.0
    while t < seconds { scene.step(1 / fps); t += 1 / fps }
}

func snapshot(_ name: String) {
    let start = Date()
    let command = renderer.draw(to: target)
    command.waitUntilCompleted()
    let gpu = (command.gpuEndTime - command.gpuStartTime) * 1000
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let url = out.appending(path: "\(name).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("\(name): gpu \(String(format: "%.2f", gpu)) ms, wall \(Int(Date().timeIntervalSince(start) * 1000)) ms, instances \(scene.instanceCount)")
}

// Warm-up frame, then the library.
scene.resize(width: width, height: height)
let pick = columns.max { $0.count < $1.count }!
scene.setLibrary(columns, selected: pick[pick.count / 2])
await serviceCovers()
advance(0.2)

if env["RHINE_BENCH"] != nil {
    // Steady-state GPU cost per variant: 120 frames each, median of gpuEnd - gpuStart.
    // Pipelined like a display link (3 frames in flight) so the GPU clocks up; first 30 frames dropped.
    func bench(_ label: String) {
        let commands = (0..<150).map { _ -> MTLCommandBuffer in scene.step(1 / 120); return renderer.draw(to: target) }
        commands.last!.waitUntilCompleted()
        // Overlapping command buffers inflate per-buffer spans; throughput is first start → last end.
        let measured = Array(commands.dropFirst(30))
        let throughput = (measured.last!.gpuEndTime - measured.first!.gpuStartTime) * 1000 / Double(measured.count)
        print(String(format: "%-40@ %.2f ms/frame", label as NSString, throughput))
    }
    for (scale, dof, fxaa) in [(1.0, true, true), (0.75, true, true), (0.75, false, true), (0.75, false, false)] {
        renderer.renderScale = scale; scene.focusDepth = dof; renderer.fxaa = fxaa
        bench("scale \(scale) dof \(dof) fxaa \(fxaa)")
    }
    renderer.renderScale = 0.75; scene.focusDepth = false; renderer.fxaa = false
    for kinds in [[Int](), [2], [2, 0], [2, 1]] {
        renderer.debugKinds = kinds
        bench("0.75 kinds \(kinds)")
    }
    renderer.debugKinds = [2, 0, 1]
    scene.focusDepth = true; renderer.fxaa = true
    renderer.renderScale = 0.75
    scene.setMode(.detail); advance(4); bench("detail 0.75")
    scene.setMode(.archive); advance(3)
    scene.intro(active: true, time: 24.6); bench("intro 0.75 (advancing)")
    scene.intro(active: false)
    exit(0)
}
snapshot("01-archive-day")

// Step one row down (upstream swipe) and capture mid-slide.
if let next = scene.neighbour(axis: "row", direction: 1) {
    scene.select(next, immediate: false, axis: "row", direction: 1)
    await serviceCovers()
    advance(0.5)
    snapshot("02-archive-sliding")
    advance(2)
}

// Detail: placement, then the decryption line mid-way and finished.
scene.setMode(.detail)
await serviceCovers()
advance(ArchivePose.placementSeconds + 0.3)
advance(1.4)
snapshot("03-detail-decrypting")
advance(3)
snapshot("04-detail-presented")

scene.setMode(.archive)
advance(2)
scene.theme(night: true)
advance(1)
snapshot("05-archive-night")

scene.theme(night: false, immediate: true)
scene.setOverview(true)
advance(1.5)
snapshot("06-overview")
scene.setOverview(false)
advance(1.5)

for time in [22.4, 23.4, 24.6, 25.6, 26.6] {
    scene.intro(active: true, time: time)
    advance(1 / 120)
    snapshot(String(format: "07-intro-%.1f", time))
}
scene.intro(active: false)
