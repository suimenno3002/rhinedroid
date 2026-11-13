// Host side of RhineDroid VulkanArchiveRenderer + native-archive-scene.ts gestures
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import MetalKit
import RhineKit
import SwiftUI

/// Owns the Metal shelf. The display link runs only while the scene reports motion and pauses
/// itself when everything is settled, so an idle shelf costs no GPU time.
@MainActor
final class ShelfController: NSObject, MTKViewDelegate {
    let view: ShelfMTKView
    let renderer: ArchiveRenderer
    let covers = CoverLoader()
    var scene: ArchiveScene { renderer.scene }
    var mode: ArchiveScene.Mode = .archive
    var onPick: ((String) -> Void)?
    var onActivate: (() -> Void)?
    var onNavigate: ((_ axis: String, _ direction: Int) -> Void)?
    var onPhase: ((ArchiveScene.Phase) -> Void)?
    private var last: CFTimeInterval = 0

    init?(glb: URL) {
        guard let device = MTLCreateSystemDefaultDevice(), let data = try? Data(contentsOf: glb) else { return nil }
        let view = ShelfMTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .invalid
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.autoResizeDrawable = true
        view.isMultipleTouchEnabled = false
        view.backgroundColor = UIColor(red: 232 / 255, green: 229 / 255, blue: 225 / 255, alpha: 1)
        do { renderer = try ArchiveRenderer(device: device, glb: data, targetFormat: view.colorPixelFormat) } catch { return nil }
        self.view = view
        super.init()
        view.delegate = self
        view.controller = self
        // CAMetalLayer-backed views default to scale 1; render at the panel's native 2x.
        view.contentScaleFactor = UIScreen.main.nativeScale
        covers.isWanted = { [weak self] id, slot in self?.scene.isWanted(id: id, slot: slot) ?? false }
        covers.onTile = { [weak self] id, slot, pixels in
            guard let self, self.scene.coverTileReady(id: id, slot: slot) else { return }
            self.renderer.uploadTile(slot: slot, pixels: pixels); self.wake()
        }
        covers.isHiresWanted = { [weak self] id, slot in self?.scene.isHiresWanted(id: id, slot: slot) ?? false }
        covers.onHires = { [weak self] id, slot, pixels in
            guard let self, self.scene.hiresReady(id: id, slot: slot) else { return }
            self.renderer.uploadHires(slot: slot, pixels: pixels); self.wake()
        }
        scene.onCoverRequest = { [weak self] tiles in self?.covers.request(tiles: tiles) }
        scene.onHiresRequest = { [weak self] covers in self?.covers.requestHires(covers) }
        scene.onPhase = { [weak self] phase, _ in self?.onPhase?(phase) }
        #if DEBUG
        startStats()
        #endif
    }

    #if DEBUG
    // RHINE_STATS=1: every 2 s print fps, GPU ms/frame and thermal state to stderr.
    private var statFrames = 0, statGPUFrames = 0
    private var statGPU = 0.0
    private var statTimer: Timer?

    private func startStats() {
        guard ProcessInfo.processInfo.environment["RHINE_STATS"] != nil else { return }
        var last = CACurrentMediaTime()
        statTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime(), span = now - last
                last = now
                let fps = Double(self.statFrames) / span
                let gpu = self.statGPUFrames > 0 ? self.statGPU / Double(self.statGPUFrames) : 0
                let thermal = ["nominal", "fair", "serious", "critical"][min(3, ProcessInfo.processInfo.thermalState.rawValue)]
                fputs(String(format: "[perf] fps %3.0f  gpu %5.2f ms  busy %3.0f%%  drawable %dx%d  scale %.2f  thermal %@\n",
                             fps, gpu, fps * gpu / 10, Int(self.view.drawableSize.width), Int(self.view.drawableSize.height),
                             self.renderer.renderScale, thermal), stderr)
                self.statFrames = 0; self.statGPUFrames = 0; self.statGPU = 0
            }
        }
    }

    fileprivate func recordGPU(_ ms: Double) { statGPU += ms; statGPUFrames += 1 }
    #endif

    /// Any command that changes the scene calls this; the delegate pauses again once settled.
    func wake() {
        // Any real change gets the full rate back immediately, even from the 30 fps ambient mode.
        let rate = Self.activeRate
        if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
        guard view.isPaused else { return }
        last = 0
        view.isPaused = false
    }

    /// 120 Hz while something moves; 60 Hz once iOS reports thermal pressure.
    private static var activeRate: Int { ProcessInfo.processInfo.thermalState.rawValue >= 2 ? 60 : 120 }
    /// Idle drift is two slow sines (8 s and 13 s periods); 30 fps is visually identical and ~4x cheaper.
    private static let ambientRate = 30

    func perform(_ change: (ArchiveScene) -> Void) { change(scene); wake() }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            scene.resize(width: Int(size.width), height: Int(size.height))
            wake()
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            let now = CACurrentMediaTime()
            let dt = last == 0 ? 1 / 120 : now - last
            last = now
            let more = scene.step(dt)
            guard let drawable = (view as MTKView).currentDrawable else { return }
            renderer.draw(to: drawable.texture) { command in
                command.present(drawable)
                #if DEBUG
                command.addCompletedHandler { [weak self] buffer in
                    let ms = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
                    DispatchQueue.main.async { self?.recordGPU(ms) }
                }
                #endif
            }
            #if DEBUG
            statFrames += 1
            #endif
            let rate = scene.ambientOnly ? Self.ambientRate : Self.activeRate
            if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
            if !more { view.isPaused = true }
        }
    }

    // MARK: Gestures (native-archive-scene.ts)

    // Live drag: the shelf steps while the finger moves (one card per `rowStep` / column per `laneStep`),
    // instead of upstream's single step on release. The axis locks after 12 pt.
    private var dragAxis: String?
    private var dragAnchor = CGPoint.zero
    private var dragSteps = 0
    private let rowStep: CGFloat = 54, laneStep: CGFloat = 96

    func began(at point: CGPoint) { dragAxis = nil; dragAnchor = point; dragSteps = 0 }

    func moved(to point: CGPoint) {
        let dx = point.x - dragAnchor.x, dy = point.y - dragAnchor.y
        if dragAxis == nil {
            guard hypot(dx, dy) >= 12 else { return }
            let horizontal = abs(dx) > abs(dy)
            dragAxis = mode == .detail ? "detail" : (horizontal ? "lane" : "row")
            // Detail mode accepts either direction; keep whichever axis started the drag.
            if mode == .detail { dragHorizontal = horizontal }
        }
        guard let axis = dragAxis else { return }
        let horizontal = axis == "lane" || (axis == "detail" && dragHorizontal)
        let delta = horizontal ? dx : dy
        let step = horizontal ? laneStep : rowStep
        guard abs(delta) >= step else { return }
        // Finger moving left / up pulls the next card in, like scrolling content.
        onNavigate?(axis, delta < 0 ? 1 : -1)
        dragSteps += 1
        if horizontal { dragAnchor.x += delta < 0 ? -step : step } else { dragAnchor.y += delta < 0 ? -step : step }
    }
    private var dragHorizontal = true

    func released(dx: CGFloat, dy: CGFloat, elapsed: TimeInterval, at point: CGPoint) {
        defer { dragAxis = nil }
        if dragSteps > 0 { return }
        // Short flick that never reached a full step still counts as one (upstream thresholds).
        let major = max(abs(dx), abs(dy)), minor = min(abs(dx), abs(dy))
        if major >= 36, major >= minor * 1.3, elapsed <= 1.4 {
            let horizontal = abs(dx) > abs(dy)
            let axis = mode == .detail ? "detail" : (horizontal ? "lane" : "row")
            onNavigate?(axis, (horizontal ? dx : dy) < 0 ? 1 : -1)
        } else if hypot(dx, dy) < 12, view.bounds.width > 0 {
            let x = point.x / view.bounds.width, y = point.y / view.bounds.height
            guard let hit = scene.pick(x: x, y: y) else { return }
            // Close-up: tapping the lifted card plays it; elsewhere a tap picks a card.
            if mode == .detail { if hit.album == scene.selected { onActivate?() } } else { onPick?(hit.album) }
        }
    }
}

final class ShelfMTKView: MTKView {
    weak var controller: ShelfController?
    private var gesture: (touch: UITouch, start: CGPoint, time: TimeInterval)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gesture == nil, let touch = touches.first else { return }
        gesture = (touch, touch.location(in: self), touch.timestamp)
        controller?.began(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let g = gesture, touches.contains(g.touch) else { return }
        controller?.moved(to: g.touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let g = gesture, touches.contains(g.touch) else { return }
        gesture = nil
        let p = g.touch.location(in: self)
        controller?.released(dx: p.x - g.start.x, dy: p.y - g.start.y, elapsed: g.touch.timestamp - g.time, at: p)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { gesture = nil }
}

struct ShelfView: UIViewRepresentable {
    let controller: ShelfController
    func makeUIView(context: Context) -> ShelfMTKView { controller.view }
    func updateUIView(_ view: ShelfMTKView, context: Context) {}
}
