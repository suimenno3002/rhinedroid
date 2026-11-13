// CPU side of RhineDroid VulkanArchiveRenderer.kt (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
// Holds the shelf state machine; the GPU only receives poses and a handful of scalars per frame.
import Foundation
import simd

public final class ArchiveScene {
    public enum Mode: Sendable { case hidden, archive, detail }
    public enum Phase: String, Sendable { case archive, placing, presented, returningArray = "returning-array", returningCenter = "returning-center" }

    public struct ColumnLabel: Sendable { public let lane: Int; public let x: Double; public let y: Double; public let count: Int; public let row: Double }

    // Library
    public private(set) var columns: [[String]] = []
    private var locations: [String: (lane: Int, row: Int)] = [:]
    public private(set) var selected = ""
    private var lane = 0, row = 0
    public private(set) var filled = true
    public private(set) var cells = ShelfLayout.cells([], lane: 0, row: 0, filled: true)
    let motion = ShelfMotion()
    let artwork = ArtworkSlots()

    // Motion
    private var placement = ArchiveScalar()
    private var overviewMotion = ArchiveSpring()
    private var overviewTarget = 0.0
    public private(set) var animationTime = 0.0
    public var animationSpeed = 1.0
    public private(set) var introTime: Double?
    private var introSpeed = 1.0
    public private(set) var inspectStart = -1.0
    public private(set) var rotation: Float = 0
    private var targetRotation: Float = 0
    private var pendingReturn = false
    private var pendingSelection: (id: String, axis: String, direction: Int)?
    private var cameraMotion = ArchiveCameraMotion()
    private var cameraMoving = false
    public var idleEnabled = false { didSet { dirty = true } }
    public var focusDepth = true { didSet { dirty = true } }
    /// Upstream's inspection reveal (blurred cover, orange diagonal scan, then clear). Optional on iPad.
    public var decryption = true { didSet { if !decryption { inspectStart = -1 }; dirty = true } }
    private var idleGain = ArchiveSpring()
    private var lastInteraction = 0.0
    private var themeMotion = ArchiveScalar()
    private var themeStarted = false
    public private(set) var themeValue = 0.0
    public var guideDuration = 1.1
    private var guideX = ArchiveSpring(), guideZ = ArchiveSpring()
    /// strength, width (rows FWHM), offset (rows), fill — upstream defaults.
    public var guidance = SIMD4<Float>(1.3, 1.35, 0.3, 1) { didSet { dirty = true } }
    public var reduced = false { didSet { if reduced { animate(immediate: true) } } }
    public private(set) var hidden = false
    public private(set) var width = 1, height = 1
    private var settleFrames = 0
    private var dirty = true
    private var lastPhase = ""

    // Camera products
    public private(set) var view = matrix_identity_float4x4
    public private(set) var projection = matrix_identity_float4x4
    public private(set) var cameraPosition = SIMD3<Float>(0, 0, 1)
    public private(set) var focusDistance: Double = 140
    public private(set) var span: Double = 7.33
    public static let near = 0.1, far = 400.0

    // Artwork
    /// Hi-res (1024²) covers kept resident for a 3 × 6 window around the selection (lanes −1…+1, rows
    /// −1…+4), the previous selection and the playing card. Every card whose cover is resident draws it,
    /// so cards never swap between thumbnail and hi-res while they are large on screen.
    public static let hiresCapacity = 24
    let hires = ArtworkSlots(capacity: ArchiveScene.hiresCapacity)
    private var hiresTimes = [Double](repeating: -1000, count: ArchiveScene.hiresCapacity)
    private var hiresInfo = [Float](repeating: -1, count: ShelfLayout.count * 4)
    private var lastHiresReady = -1000.0
    private var previousSelected: String?
    static let hiresWindowRows = [0, 1, -1, 2, 3, 4]
    /// Maps a shelf key to its artwork key, so cards showing the same cover share one atlas slot
    /// (one-song-per-card list modes repeat album covers).
    public var coverKey: (String) -> String = { $0 }
    /// Shelf keys of the cards showing the playing song; their cases get the accent edge light.
    public var playingKeys: Set<String> = [] { didSet { if playingKeys != oldValue { updatePlayingMask(); bindHires(); dirty = true } } }
    private var playingMask = [UInt32](repeating: 0, count: 8)

    private func updatePlayingMask() {
        playingMask = [UInt32](repeating: 0, count: 8)
        guard !playingKeys.isEmpty else { return }
        // Short columns wrap to fill the pool, so a card can appear several times; light only the
        // copy nearest the selection.
        var nearest: [String: (slot: Int, distance: Float)] = [:]
        for (i, cell) in cells.enumerated() {
            guard let key = cell.album, playingKeys.contains(key) else { continue }
            let lanes = cell.x / 5.2, rows = cell.z / 0.62
            let distance = lanes * lanes * 9 + rows * rows
            if distance < (nearest[key]?.distance ?? .infinity) { nearest[key] = (i, distance) }
        }
        for (slot, _) in nearest.values { playingMask[slot / 32] |= 1 << UInt32(slot % 32) }
    }
    /// Called after every rebuild with artwork keys that still need an atlas tile.
    public var onCoverRequest: ((_ tiles: [(id: String, slot: Int)]) -> Void)?
    /// Artwork keys that still need their hi-res cover, in priority order, with the array slice to fill.
    public var onHiresRequest: ((_ covers: [(id: String, slot: Int)]) -> Void)?
    public var onPhase: ((Phase, String) -> Void)?

    public init() { theme(night: false) }

    // MARK: Commands (mirror the scene-* bridge messages)

    public func setLibrary(_ columns: [[String]], selected id: String) {
        self.columns = columns
        locations = [:]
        for (lane, column) in columns.enumerated() {
            for (row, album) in column.enumerated() where locations[album] == nil { locations[album] = (lane, row) }
        }
        select(id, immediate: true)
    }

    public func select(_ id: String, immediate: Bool, axis: String = "", direction: Int = 0) {
        if !immediate && placement.target > 0.5 && abs(rotation) > 0.001 {
            pendingSelection = (id, axis, direction); targetRotation = 0; dirty = true; return
        }
        pendingSelection = nil
        inspectStart = -1
        lastInteraction = animationTime
        let location = locations[id]
        guard location != nil || (id.isEmpty && columns.isEmpty) || columns.isEmpty else { return }
        let actualLane = location?.lane ?? 0, actualRow = location?.row ?? 0
        let step = max(-1, min(1, direction))
        let sameLane = !columns.isEmpty && ShelfLayout.floorMod(lane, columns.count) == actualLane
        let nextLane = filled ? ShelfMotion.occurrence(actualLane, center: lane, count: columns.count, direction: axis == "lane" ? step : 0) : actualLane
        let rowCount = columns.indices.contains(actualLane) ? columns[actualLane].count : 0
        let nextRow = filled ? ShelfMotion.occurrence(actualRow, center: row, count: rowCount, direction: axis == "row" && sameLane ? step : 0) : actualRow
        let dx = Float(nextLane - lane) * 5.2
        let dz = sameLane ? Float(nextRow - row) * 0.62 : 0
        // The card being left keeps its hi-res cover while it travels away.
        if !immediate, id != selected, !selected.isEmpty { previousSelected = selected }
        let seconds = reduced || immediate ? 0 : ShelfMotion.duration(lanes: dx / 5.2, rows: dz / 0.62)
        if !immediate, !reduced, id != selected, placement.target > 0.5 {
            handoffStart = animationTime; handoffDuration = max(0.6, Double(seconds))
        }
        selected = id; lane = nextLane; row = nextRow
        rotation = 0; targetRotation = 0
        rebuildCells(seconds: seconds, dx: dx, dz: dz)
        dirty = true
    }

    /// Neighbour along an axis, wrapping like the upstream stepper.
    public func neighbour(axis: String, direction: Int) -> String? {
        guard let location = locations[selected], !columns.isEmpty else { return nil }
        if axis == "lane" {
            let column = columns[ShelfLayout.floorMod(location.lane + direction, columns.count)]
            return column.isEmpty ? nil : column[min(location.row, column.count - 1)]
        }
        let column = columns[location.lane]
        return column[ShelfLayout.floorMod(location.row + direction, column.count)]
    }

    public func setMode(_ mode: Mode, immediate: Bool = false) {
        if immediate { introTime = nil }
        hidden = mode == .hidden
        animate(detail: mode == .detail ? 1 : 0, overview: 0, immediate: immediate)
    }

    public func setOverview(_ active: Bool) { animate(overview: active ? 1 : 0) }

    public func setFilled(_ value: Bool) { filled = value; animate() }

    public func theme(night: Bool, immediate: Bool = false) {
        themeMotion.to(night ? 1 : 0, now: animationTime, seconds: reduced || immediate || !themeStarted ? 0 : 0.65)
        themeStarted = true
        dirty = true
    }

    public func intro(active: Bool, time: Double = 21.92, speed: Double = 1) {
        if active {
            introSpeed = min(max(speed, 0.25), 3)
            introTime = min(max(time, 21.92), 27.12)
            hidden = false
        } else {
            introTime = nil
        }
        dirty = true
    }

    public func drag(rotation value: Double) {
        targetRotation = Float(min(max(value, -1.1), 1.1))
        lastInteraction = animationTime
        dirty = true
    }

    public func resize(width: Int, height: Int) {
        guard width > 0, height > 0, width != self.width || height != self.height else { return }
        cameraMotion.resize(now: animationTime)
        self.width = width; self.height = height
        settleFrames = 3; dirty = true
        updateCamera()
    }

    /// Normalised (top-left origin) hit test against projected cover centres.
    /// Hit test against each projected cover quad and return the front-most one, so a tap always lands on
    /// the card under the finger. Upstream's nearest-centre test (kept as a fallback for taps between
    /// cards) often chose a card behind the touched one on the steep iPad view.
    public func pick(x: Double, y: Double) -> (album: String, lane: Int, row: Int)? {
        let now = Float(animationTime)
        let viewProjection = projection * view
        let point = SIMD2<Float>(Float(x), Float(y))
        let corners: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        let radius = 1.8 / max(span, 0.1)
        var hit: (String, Int, Int, Float)?
        var near: (String, Int, Int, Double)?
        for (index, cell) in cells.enumerated() {
            guard let album = cell.album else { continue }
            let origin = SIMD3(motion.sample(index, 0, now).position, motion.sample(index, 1, now).position, motion.sample(index, 2, now).position)
            // Cover insert (ArchiveMesh kind 2): 3.06 square centred at (0.17, 1.85, 0.027).
            var screen: [SIMD2<Float>] = []
            var depth: Float = 0
            for c in corners {
                let clip = viewProjection * SIMD4<Float>(origin + SIMD3(0.17 + c.x * 1.53, 1.85 + c.y * 1.53, 0.027), 1)
                guard clip.w > 0 else { break }
                screen.append(SIMD2((clip.x / clip.w + 1) / 2, (1 - clip.y / clip.w) / 2))
                depth += clip.w
            }
            if screen.count == 4 {
                var positive = false, negative = false
                for i in 0..<4 {
                    let a = screen[i], b = screen[(i + 1) % 4]
                    let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
                    if cross > 0 { positive = true } else if cross < 0 { negative = true }
                }
                if !(positive && negative), depth < (hit?.3 ?? .infinity) { hit = (album, cell.lane, cell.row, depth) }
            }
            let p = project(origin + SIMD3(0, 1.85, 0))
            let distance = hypot((p.x - x) * Double(width) / Double(height), p.y - y)
            if distance < radius, distance < (near?.3 ?? .infinity) { near = (album, cell.lane, cell.row, distance) }
        }
        if let hit { return (hit.0, hit.1, hit.2) }
        return near.map { ($0.0, $0.1, $0.2) }
    }

    public func columnLabels() -> [ColumnLabel] {
        guard !columns.isEmpty else { return [] }
        let now = Float(animationTime)
        return (-3...3).compactMap { dx in
            let actual = filled ? ShelfLayout.floorMod(lane + dx, columns.count) : lane + dx
            guard columns.indices.contains(actual) else { return nil }
            let slot = (dx + 3) * ShelfLayout.rows + ShelfLayout.rows / 2
            let z = motion.sample(slot, 2, now).position
            let p = project(SIMD3(motion.sample(slot, 0, now).position, motion.sample(slot, 1, now).position + 1.85, z))
            return ColumnLabel(lane: actual, x: p.x, y: p.y, count: columns[actual].count, row: 12 + Double(cells[slot].physicalRow) - Double(z / 0.62))
        }
    }

    // MARK: Artwork

    /// A 128² tile finished decoding. Returns false if the slot was reassigned meanwhile (drop the pixels).
    public func coverTileReady(id: String, slot: Int) -> Bool {
        guard artwork.ready(id, slot: slot) else { return false }
        uploadCells(); dirty = true
        return true
    }

    /// A hi-res cover finished decoding. Returns false if the slice was reassigned meanwhile (drop the pixels).
    public func hiresReady(id: String, slot: Int) -> Bool {
        guard hires.ready(id, slot: slot) else { return false }
        hiresTimes[slot] = animationTime; lastHiresReady = animationTime
        uploadCells(); dirty = true
        return true
    }

    public func isHiresWanted(id: String, slot: Int) -> Bool { hires.get(id)?.slot == slot }

    // Close-up handoff: depth of field eases off while the two cards swap, so the outgoing one blurs
    // late and the incoming one is sharp early; a newly resident hi-res cover cross-fades in.
    private var handoffStart = -1.0, handoffDuration = 1.0
    static let coverFade = 0.35

    /// Multiplier on the depth-of-field blur: 1 → 0.2 quickly, held while the cards move, back to 1 at the end.
    public var dofScale: Double {
        guard handoffStart >= 0 else { return 1 }
        let x = (animationTime - handoffStart) / handoffDuration
        guard x < 1 else { return 1 }
        let down = ArchivePose.smooth(x / 0.18), up = ArchivePose.smooth((x - 0.55) / 0.45)
        return 1 - 0.8 * down * (1 - up)
    }

    public func isWanted(id: String, slot: Int) -> Bool { artwork.get(id)?.slot == slot }

    // MARK: Frame

    /// Advances the clocks. Returns whether another frame is needed (otherwise the display link may pause).
    @discardableResult
    public func step(_ elapsed: Double) -> Bool {
        let realDt = min(max(elapsed, 0), 0.05)
        let dt = realDt * (introTime != nil ? 1 : animationSpeed)
        animationTime += dt
        if let t = introTime { introTime = min(27.12, t + realDt * introSpeed) }
        overviewMotion.update(target: overviewTarget, dt: dt, rate: 6.5, immediate: reduced)
        let returning = pendingReturn || pendingSelection != nil || placement.target < 0.5
        if reduced {
            rotation = returning ? 0 : targetRotation
        } else if returning {
            rotation = Float(Double(rotation) * exp(-dt * 7))
            if abs(rotation) < 0.001 { rotation = 0 }
        } else {
            rotation += Float(Double(targetRotation - rotation) * (1 - exp(-dt * 2.8)))
        }
        if returning && rotation == 0 {
            if let pending = pendingSelection {
                pendingSelection = nil
                select(pending.id, immediate: false, axis: pending.axis, direction: pending.direction)
            } else if pendingReturn {
                animate(detail: 0)
            }
        }
        let drifting = idleEnabled && !reduced && !hidden && introTime == nil && placement.target == 0 && overviewTarget == 0
        idleGain.update(target: drifting && animationTime - lastInteraction > 2.5 ? 1 : 0, dt: dt, rate: 4, immediate: reduced)
        themeValue = min(max(themeMotion.sample(animationTime).value, 0), 1)
        let now = Float(animationTime)
        let guideRate = 4.7438645 / guideDuration
        guideX.update(target: Double(motion.sample(ShelfLayout.selected, 0, now).position), dt: dt, rate: guideRate, immediate: reduced)
        guideZ.update(target: Double(motion.sample(ShelfLayout.selected, 2, now).position), dt: dt, rate: guideRate, immediate: reduced)
        updateCamera()
        updatePhase()
        let inspectionMoving = inspectStart >= 0 && animationTime - inspectStart < 3.63
        let active = dirty || !placement.settled(animationTime) || !motion.settled(now) || cameraMoving
            || !overviewMotion.settled(target: overviewTarget) || !themeMotion.settled(animationTime)
            || abs(rotation - targetRotation) > 0.001 || pendingReturn || pendingSelection != nil || inspectionMoving
            || introTime != nil || settleFrames > 0
            || (handoffStart >= 0 && animationTime - handoffStart < handoffDuration)
            || animationTime - lastHiresReady < Self.coverFade
        // Idle drift (8 s / 13 s sines, ≤0.1 units) is the only motion left: it needs no high frame rate.
        ambientOnly = !active && (drifting || idleGain.value > 0.0001)
        return active || ambientOnly
    }

    /// True when the last `step` found nothing moving except the idle drift.
    public private(set) var ambientOnly = false

    /// The renderer submitted a frame.
    public func presented() { dirty = false; settleFrames = max(0, settleFrames - 1) }

    /// Forces one more frame (quality change, cover upload).
    public func invalidate() { dirty = true }

    public var visible: Bool { !hidden && (introTime != nil || columns.contains { !$0.isEmpty }) }
    public var depthOfField: Bool { introTime == nil && focusDepth }
    public var instanceCount: Int { introTime != nil ? ShelfLayout.introCount : ShelfLayout.count }
    public var placementValue: Double { min(max(placement.sample(animationTime).value, 0), 1) }

    public func uniforms(kind: Int) -> ArchiveUniforms {
        let now = Float(animationTime)
        return ArchiveUniforms(
            viewProjection: projection * view,
            camera: SIMD4(cameraPosition, 0),
            travel: SIMD4(motion.start, motion.duration, now, introTime.map(Float.init) ?? -1),
            grids: SIMD4(Float(ShelfLayout.introColumns), Float(ShelfLayout.introRows), Float(ShelfLayout.columns), Float(ShelfLayout.rows)),
            guidance: guidance,
            a: SIMD4(Float(inspectStart), Float(idleGain.value), Float(placementValue), rotation),
            b: SIMD4(Float(kind), Float(themeValue), 0, focusDepth ? 1 : 0),
            c: SIMD4(motion.sample(ShelfLayout.selected, 0, now).position, motion.sample(ShelfLayout.selected, 2, now).position,
                     Float(guideX.value), Float(guideZ.value)),
            d: SIMD4(0, 0, 0, 0),
            playA: SIMD4(playingMask[0], playingMask[1], playingMask[2], playingMask[3]),
            playB: SIMD4(playingMask[4], playingMask[5], playingMask[6], playingMask[7]))
    }

    /// Copies cells / origins / velocities / accelerations / hi-res info (float4 × 217 each) into a GPU buffer.
    public static let poseArrays = 5
    public func writePose(to pointer: UnsafeMutableRawPointer) {
        let bytes = ShelfLayout.count * 16
        for (i, array) in [motion.target, motion.origin, motion.velocity, motion.acceleration, hiresInfo].enumerated() {
            array.withUnsafeBytes { pointer.advanced(by: i * bytes).copyMemory(from: $0.baseAddress!, byteCount: bytes) }
        }
    }

    // MARK: Internals

    private func animate(detail: Double? = nil, overview: Double? = nil, immediate: Bool = false) {
        let targetDetail = detail ?? placement.target, targetOverview = overview ?? overviewTarget
        if targetDetail == 0 && !immediate && abs(rotation) > 0.001 {
            pendingReturn = true; targetRotation = 0; dirty = true; return
        }
        pendingReturn = false
        if placement.target != targetDetail || immediate {
            placement.to(targetDetail, now: animationTime, seconds: reduced || immediate ? 0 : ArchivePose.placementSeconds)
        }
        overviewTarget = targetOverview
        if reduced || immediate { overviewMotion.update(target: overviewTarget, dt: 0, immediate: true) }
        if targetDetail == 0 { inspectStart = -1 }
        rebuildCells(seconds: reduced || immediate ? 0 : Float(ArchivePose.placementSeconds))
        lastInteraction = animationTime
        dirty = true
    }

    private func rebuildCells(seconds: Float = 0, dx: Float = 0, dz: Float = 0) {
        cells = ShelfLayout.cells(columns, lane: lane, row: row, filled: filled)
        motion.retarget(cells, detail: Float(placement.target), now: Float(animationTime), seconds: seconds, dx: dx, dz: dz)
        updatePlayingMask()
        let assigned = artwork.bind(cells.compactMap { $0.album.map(coverKey) })
        let missing = assigned.filter { !$0.ready }.map { (id: $0.id, slot: $0.slot) }
        let cover = selected.isEmpty ? "" : coverKey(selected)
        let ordered = missing.sorted { ($0.id == cover ? 0 : 1) < ($1.id == cover ? 0 : 1) }
        if !ordered.isEmpty { onCoverRequest?(ordered) }
        bindHires()
        uploadPose()
    }

    /// Keeps the hi-res window resident: current card, previous selection, the rest of the 3 × 6 window
    /// (centre column first), then the playing card. Requests whatever is missing, in that order.
    private func bindHires() {
        var keys: [String] = [], seen = Set<String>()
        func add(_ key: String?) {
            guard let key, !key.isEmpty, keys.count < Self.hiresCapacity, seen.insert(key).inserted else { return }
            keys.append(key)
        }
        func cover(lane: Int, row: Int) -> String? {
            let slot = (lane + ShelfLayout.columns / 2) * ShelfLayout.rows + row + ShelfLayout.rows / 2
            return cells.indices.contains(slot) ? cells[slot].album.map(coverKey) : nil
        }
        add(cover(lane: 0, row: 0))
        add(previousSelected.map(coverKey))
        for row in Self.hiresWindowRows { add(cover(lane: 0, row: row)) }
        for row in Self.hiresWindowRows { add(cover(lane: -1, row: row)); add(cover(lane: 1, row: row)) }
        for key in playingKeys.sorted() { add(coverKey(key)) }
        let missing = hires.bind(keys).filter { !$0.ready }.map { (id: $0.id, slot: $0.slot) }
        if !missing.isEmpty { onHiresRequest?(missing) }
        uploadCells()
    }

    private func uploadPose() {
        for (i, cell) in cells.enumerated() {
            motion.origin[i * 4 + 3] = Float(cell.physicalRow)
            motion.velocity[i * 4 + 3] = Float(cell.physicalLane)
            let d = Double(cell.z / 0.62)
            let weight = 0.25 + 0.75 * exp(-0.5 * pow(Double(cell.x) / 5.2 / 0.55, 2))
            motion.acceleration[i * 4 + 3] = Float((ArchivePose.shoulder(row: d + 0.5, lane: 0) - ArchivePose.shoulder(row: d - 0.5, lane: 0)) * weight * 0.024)
        }
        uploadCells()
    }

    private func uploadCells() {
        for (i, cell) in cells.enumerated() {
            let key = cell.album.map(coverKey)
            let art = key.flatMap { artwork.get($0) }
            motion.target[i * 4 + 3] = art.map { Float($0.slot + 1) * ($0.ready ? 1 : -1) } ?? 0
            // hiresInfo: x = array slice (−1 = none), y = time it became resident (cross-fade).
            if let entry = key.flatMap({ hires.get($0) }), entry.ready {
                hiresInfo[i * 4] = Float(entry.slot); hiresInfo[i * 4 + 1] = Float(hiresTimes[entry.slot])
            } else {
                hiresInfo[i * 4] = -1
            }
        }
    }

    private func updatePhase() {
        let phase: Phase
        if pendingReturn { phase = .returningCenter }
        else if pendingSelection != nil || cameraMoving || !placement.settled(animationTime) || !motion.settled(Float(animationTime)) {
            phase = placement.target > 0.5 ? .placing : .returningArray
        } else {
            phase = placement.target > 0.5 ? .presented : .archive
        }
        if phase == .presented && inspectStart < 0 && decryption { inspectStart = animationTime }
        let key = "\(phase.rawValue):\(selected)"
        if key != lastPhase { lastPhase = key; onPhase?(phase, selected) }
    }

    private func updateCamera() {
        let target = ArchivePose.camera(width: width, height: height, detail: placementValue,
                                        overview: min(max(overviewMotion.value, 0), 1), intro: introTime)
        let pose = cameraMotion.sample(target, now: animationTime, immediate: reduced)
        cameraMoving = cameraMotion.moving
        span = max(pose.span, 0.1)
        let distance = max(simd_length(pose.position - pose.aim), 1)
        let fovY = 2 * atan(span / (2 * distance))
        view = Self.lookAt(eye: pose.position, center: pose.aim)
        projection = Self.perspective(fovY: fovY, aspect: Double(width) / Double(height), near: Self.near, far: Self.far)
        cameraPosition = SIMD3<Float>(pose.position)
        let now = Float(animationTime)
        let focus = introTime != nil ? pose.aim : SIMD3(
            Double(motion.sample(ShelfLayout.selected, 0, now).position) + 0.17 * cos(Double(rotation)),
            Double(motion.sample(ShelfLayout.selected, 1, now).position) + 1.85,
            Double(motion.sample(ShelfLayout.selected, 2, now).position) - 0.17 * sin(Double(rotation)))
        focusDistance = ArchivePose.focusDistance(pose, point: focus)
    }

    func project(_ point: SIMD3<Float>) -> (x: Double, y: Double) {
        let viewProjection: simd_float4x4 = projection * view
        let clip: SIMD4<Float> = viewProjection * SIMD4<Float>(point, 1)
        return (Double((clip.x / clip.w + 1) / 2), Double((1 - clip.y / clip.w) / 2))
    }

    private static func float4x4(_ c: [SIMD4<Double>]) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(c[0]), SIMD4<Float>(c[1]), SIMD4<Float>(c[2]), SIMD4<Float>(c[3])))
    }

    static func lookAt(eye: SIMD3<Double>, center: SIMD3<Double>, up: SIMD3<Double> = [0, 1, 0]) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return float4x4([
            SIMD4(s.x, u.x, -f.x, 0), SIMD4(s.y, u.y, -f.y, 0), SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)])
    }

    /// Right-handed perspective with Metal's [0, 1] clip depth.
    static func perspective(fovY: Double, aspect: Double, near: Double, far: Double) -> simd_float4x4 {
        let y = 1 / tan(fovY / 2), x = y / aspect, z = far / (near - far)
        return float4x4([SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)])
    }
}

/// Matches `Params` in ArchiveShaders.swift (all members are 16-byte aligned).
public struct ArchiveUniforms {
    public var viewProjection: simd_float4x4
    public var camera: SIMD4<Float>
    /// travel.x start, travel.y duration, clock, opening time (-1 when browsing)
    public var travel: SIMD4<Float>
    /// openingGrid.xy, poolGrid.xy
    public var grids: SIMD4<Float>
    public var guidance: SIMD4<Float>
    /// inspection, idle, placement, rotation
    public var a: SIMD4<Float>
    /// kind, night, optics, focus
    public var b: SIMD4<Float>
    /// focusCenter.xy, guideCenter.xy
    public var c: SIMD4<Float>
    /// selectedReady
    public var d: SIMD4<Float>
    /// Bitmask of pool slots showing the playing song.
    public var playA: SIMD4<UInt32>
    public var playB: SIMD4<UInt32>
}
