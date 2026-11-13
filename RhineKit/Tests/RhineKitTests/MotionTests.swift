// Ported from RhineDroid app/src/test (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
// Darwin + simd instead of Foundation: the Command Line Tools ship Testing without its Foundation overlay.
import Darwin
import simd
import Testing
@testable import RhineKit

private func close(_ a: Double, _ b: Double, _ eps: Double) -> Bool { abs(a - b) <= eps }
private func close(_ a: Float, _ b: Float, _ eps: Float) -> Bool { abs(a - b) <= eps }

@Suite struct ShelfLayoutTests {
    @Test func poolRemainsBoundedForTenThousandAlbums() {
        let albums = (0..<10000).map { "device-album-\($0)" }
        let cells = ShelfLayout.cells([albums], lane: 0, row: 9999, filled: true)
        #expect(cells.count == 217)
        #expect(cells[ShelfLayout.selected].album == "device-album-9999")
        #expect(cells.allSatisfy { $0.album != nil })
        #expect(cells[ShelfLayout.selected + 1].album == "device-album-0")
    }

    @Test func finiteColumnsNeverWrapTheirFirstAndLastRows() {
        let cells = ShelfLayout.cells([["a", "b"]], lane: 0, row: 0, filled: false)
        #expect(cells[ShelfLayout.selected - 1].album == nil)
        #expect(cells[ShelfLayout.selected].album == "a")
        #expect(cells[ShelfLayout.selected + 1].album == "b")
        #expect(cells[ShelfLayout.selected + 2].album == nil)
    }

    @Test func finiteColumnsKeepTheirOwnRowsAndNeverRepeatAcrossLanes() {
        let albums = [(0..<10000).map { "a\($0)" }, (0..<3).map { "b\($0)" }]
        let cells = ShelfLayout.cells(albums, lane: 0, row: 9999, filled: false)
        #expect(cells[ShelfLayout.selected].album == "a9999")
        #expect(cells[ShelfLayout.selected + ShelfLayout.rows].album == "b1")
        #expect(cells.filter { $0.album != nil }.count == 19)
        let ids = cells.compactMap(\.album)
        #expect(ids.count == Set(ids).count)
    }

    @Test func emptyLibraryAndColumnTransitionsKeepStableSlotCoordinates() {
        #expect(ShelfLayout.cells([], lane: 0, row: 0, filled: true).allSatisfy { $0.album == nil })
        let cells = ShelfLayout.cells([["a"], ["b"]], lane: 1, row: 0, filled: true)
        #expect(cells[ShelfLayout.selected].album == "b")
        #expect(cells[ShelfLayout.selected + ShelfLayout.rows].album == "a")
        #expect(cells[ShelfLayout.selected].x == 0)
        #expect(cells[ShelfLayout.selected].z == 0)
    }
}

@Suite struct ShelfMotionTests {
    let columns = [(0..<100).map { "a\($0)" }, (0..<100).map { "b\($0)" }]

    @Test func searchJumpResetsTheWholePool() {
        let library = [(0..<1000).map { "a\($0)" }, (0..<120).map { "b\($0)" }, (0..<800).map { "c\($0)" }]
        let motion = ShelfMotion()
        motion.retarget(ShelfLayout.cells(library, lane: 0, row: 10, filled: true), detail: 0, now: 0, seconds: 0)
        motion.retarget(ShelfLayout.cells(library, lane: 0, row: 11, filled: true), detail: 0, now: 1, seconds: 1.4, dz: 0.62)
        motion.retarget(ShelfLayout.cells(library, lane: 2, row: 720, filled: true), detail: 0, now: 1.3, seconds: 0)
        for slot in 0..<ShelfLayout.count {
            for axis in 0..<3 {
                let n = slot * 4 + axis
                #expect(motion.target[n] == motion.sample(slot, axis, 1.3).position)
                #expect(motion.velocity[n] == 0)
                #expect(motion.acceleration[n] == 0)
            }
        }
    }

    @Test func slideDoesNotAddBounceToTheShoulderProfile() {
        let motion = ShelfMotion()
        motion.retarget(ShelfLayout.cells(columns, lane: 0, row: 40, filled: true), detail: 0, now: 0, seconds: 0)
        motion.retarget(ShelfLayout.cells(columns, lane: 0, row: 41, filled: true), detail: 0, now: 1, seconds: 1.4, dz: 0.62)
        let slot = ShelfLayout.selected
        let initial = motion.sample(slot + 3, 1, 1).position
        let final = motion.sample(slot + 3, 1, 3).position
        var last: Float = 0.62
        for step in 0...100 {
            let now = 1 + Float(step) / 100 * 1.4
            let z = motion.sample(slot, 2, now).position
            #expect(z <= last + 0.0001 && z >= -0.0001)
            last = z
            let y = motion.sample(slot + 3, 1, now).position
            #expect(y >= min(initial, final) - 0.0001 && y <= max(initial, final) + 0.0001)
        }
        #expect(motion.sample(slot, 2, 2.5) == ShelfMotion.Sample(position: 0))
    }

    @Test func rapidRetargetPreservesDerivatives() {
        let motion = ShelfMotion()
        motion.retarget(ShelfLayout.cells(columns, lane: 0, row: 40, filled: true), detail: 0, now: 0, seconds: 0)
        motion.retarget(ShelfLayout.cells(columns, lane: 0, row: 41, filled: true), detail: 0, now: 1, seconds: 1.4, dz: 0.62)
        let before = (0..<3).map { motion.sample(ShelfLayout.selected + 1, $0, 1.5) }
        motion.retarget(ShelfLayout.cells(columns, lane: 0, row: 42, filled: true), detail: 0, now: 1.5, seconds: 1.4, dz: 0.62)
        for axis in 0..<3 {
            let after = motion.sample(ShelfLayout.selected, axis, 1.5)
            #expect(close(before[axis].position, after.position, 0.0001))
            #expect(close(before[axis].velocity, after.velocity, 0.0001))
            #expect(close(before[axis].acceleration, after.acceleration, 0.0001))
        }
    }

    @Test func directionalWrapKeepsTravelDirectionAndTiming() {
        #expect(ShelfMotion.occurrence(0, center: 99, count: 100, direction: 1) == 100)
        #expect(ShelfMotion.occurrence(99, center: 0, count: 100, direction: -1) == -1)
        #expect(ShelfMotion.occurrence(1, center: 0, count: 2, direction: 1) == 1)
        #expect(ShelfMotion.occurrence(1, center: 0, count: 2, direction: -1) == -1)
        #expect(ShelfMotion.duration(lanes: 0, rows: 1) == 1.4)
        #expect(ShelfMotion.duration(lanes: 20, rows: 100) == 2.4)
    }
}

@Suite struct ArchiveAnimationTests {
    @Test func opticsFocusOnTheCoverPlane() {
        let camera = ArchivePose.Camera(position: [0, 0, 10], aim: [0, 0, 0], span: 5)
        #expect(close(ArchivePose.focusDistance(camera, point: [0, 0, 0]), 10, 1e-9))
        #expect(close(ArchivePose.focusDistance(camera, point: [20, 15, 0]), 10, 1e-9))
        #expect(close(ArchivePose.focusDistance(camera, point: [0, 0, 11]), 0.1, 1e-9))
    }

    @Test func openingTracksGpuHeightAndReleasesContinuously() {
        let samples: [(Double, Double, Double, Double)] = [
            (0, 0, 25.05, 1.2234059929863417), (0, 0, 25.4, 2.14063738250456),
            (0, 0, 25.75, 2.128282640313845), (2, -1, 25.4, 1.9012090831332218),
        ]
        for s in samples { #expect(close(ArchivePose.openingHeight(row: s.0, lane: s.1, time: s.2), s.3, 1e-8)) }
        for row in -15...15 {
            for lane in -3...3 {
                let r = Double(row), l = Double(lane)
                #expect(close(ArchivePose.shoulder(row: r, lane: l), ArchivePose.openingHeight(row: r, lane: l, time: 27.12), 1e-8))
            }
        }
        #expect(close(ArchivePose.introEntryZ(21.92), -23, 1e-9))
        #expect(close(ArchivePose.introEntryZ(22.295), -5.75, 1e-9))
        #expect(close(ArchivePose.introEntryZ(22.67), 0, 1e-9))
        for (w, h) in [(840, 360), (749, 360), (360, 749)] {
            for time in [25.05, 25.4, 26.72, 27.12] {
                let before = ArchivePose.camera(width: w, height: h, detail: 0, overview: 0, intro: time - 1e-6)
                let after = ArchivePose.camera(width: w, height: h, detail: 0, overview: 0, intro: time + 1e-6)
                #expect(simd_reduce_max(abs(before.position - after.position)) < 0.001)
            }
        }
    }

    @Test func cameraResizeBlendKeepsPosition() {
        var motion = ArchiveCameraMotion()
        let landscape = ArchivePose.camera(width: 749, height: 360, detail: 0, overview: 0)
        let portrait = ArchivePose.camera(width: 360, height: 749, detail: 0, overview: 0)
        #expect(motion.sample(landscape, now: 0) == landscape)
        motion.resize(now: 1)
        #expect(simd_reduce_max(abs(motion.sample(portrait, now: 1).position - landscape.position)) < 1e-12)
        let midway = motion.sample(portrait, now: 1.16)
        #expect(motion.moving)
        motion.resize(now: 1.16)
        #expect(simd_reduce_max(abs(motion.sample(landscape, now: 1.16).position - midway.position)) < 1e-12)
        #expect(motion.sample(landscape, now: 1.49) == landscape)
        #expect(!motion.moving)
    }

    @Test func placementMatchesQuinticAndKeepsDerivativesOnReverse() {
        var value = ArchiveScalar()
        value.to(1, now: 0, seconds: ArchivePose.placementSeconds)
        for i in 0...100 {
            let t = Double(i) / 100
            #expect(close(ArchivePose.smooth(t), value.sample(t * ArchivePose.placementSeconds).value, 1e-10))
        }
        let before = value.sample(0.5)
        value.to(0, now: 0.5, seconds: ArchivePose.placementSeconds)
        let after = value.sample(0.5)
        #expect(close(before.value, after.value, 1e-10))
        #expect(close(before.velocity, after.velocity, 1e-10))
        #expect(close(before.acceleration, after.acceleration, 1e-10))
        #expect(value.sample(3) == ArchiveScalar.Sample(value: 0))
    }

    @Test func springIsIndependentOfFrameRate() {
        let results = [20, 30, 60, 120].map { fps -> (Double, Double) in
            var spring = ArchiveSpring()
            for _ in 0..<(fps * 2) { spring.update(target: 140, dt: 1 / Double(fps)) }
            return (spring.value, spring.velocity)
        }
        for r in results {
            #expect(close(results[0].0, r.0, 1e-10))
            #expect(close(results[0].1, r.1, 1e-10))
        }
    }

    @Test func camerasAreFiniteAndOpeningLandsOnArchive() {
        // iPad Pro 11" (M2) landscape/portrait added beside the upstream sizes.
        for (w, h) in [(749, 360), (360, 749), (1920, 1080), (2388, 1668), (1668, 2388)] {
            for step in 0...100 {
                let camera = ArchivePose.camera(width: w, height: h, detail: Double(step) / 100, overview: 0)
                #expect(camera.position.x.isFinite && camera.aim.y.isFinite)
                #expect((5.8...40).contains(camera.span))
            }
            let opening = ArchivePose.camera(width: w, height: h, detail: 0, overview: 0, intro: 27.12)
            let archive = ArchivePose.camera(width: w, height: h, detail: 0, overview: 0)
            #expect(simd_reduce_max(abs(opening.position - archive.position)) < 1e-6)
            #expect(simd_reduce_max(abs(opening.aim - archive.aim)) < 1e-6)
        }
        let detail = ArchivePose.camera(width: 1920, height: 1080, detail: 1, overview: 0)
        let direction = (detail.position - detail.aim) / 72
        #expect(close(direction.x, -sin(8 * .pi / 180) * cos(20 * .pi / 180), 1e-10))
        #expect(close(direction.y, sin(20 * .pi / 180), 1e-10))
    }
}

@Suite struct PrimitiveTests {
    @Test func slidingKeepsLoadedCoversAndAddresses() {
        let slots = ArtworkSlots(capacity: 8)
        let first = slots.bind(["a", "b", "c"])
        first.forEach { #expect(slots.ready($0.id, slot: $0.slot)) }
        let next = slots.bind(["b", "c", "d"])
        #expect(first[1] === next[0] && first[2] === next[1])
        #expect(next[0].ready && next[1].ready && !next[2].ready)
    }

    @Test func evictionNeverInvalidatesTheVisibleSet() {
        let slots = ArtworkSlots(capacity: 4)
        let a = slots.bind(["a", "b", "c", "d"])[0]
        slots.bind(["b", "c", "d", "e"]).forEach { slots.ready($0.id, slot: $0.slot) }
        #expect(slots.get("a") == nil)
        #expect(!slots.ready("a", slot: a.slot))
        #expect(slots.get("e")?.slot == a.slot)
        #expect(["b", "c", "d", "e"].allSatisfy { slots.get($0)?.ready == true })
        for n in 0...1000 {
            let visible = slots.bind((0..<4).map { "\(n + $0)" })
            #expect(Set(visible.map(\.slot)).count == 4)
        }
    }

    @Test func fadeTakes450msAndInterruptsFromCurrentLevel() {
        var gain = AudioEnvelope()
        gain.to(0, now: 1.0, seconds: 0.45)
        #expect(gain.sample(1.0) == 1)
        #expect(close(gain.sample(1.225), 0.5, 0.0001))
        gain.to(1, now: 1.225, seconds: 0.45)
        #expect(close(gain.sample(1.225), 0.5, 0.0001))
        #expect(close(gain.sample(1.45), 0.75, 0.0001))
        #expect(gain.sample(1.675) == 1)
        #expect(gain.settled(1.675))
        gain.to(0, now: 1.7, seconds: 0)
        #expect(gain.sample(1.7) == 0)
    }

    @Test func paletteMatchesCssColorsAndRoundTripsLinear() {
        #expect(ArchivePalette.color(0) == 0xffe8e5e1)
        #expect(ArchivePalette.color(1) == 0xff08121f)
        for step in 0...100 {
            let c = ArchivePalette.channels(Double(step) / 100)
            for srgb in [c.x, c.y, c.z] {
                let linear = Double(ArchivePalette.linear(srgb) as Float)
                let restored = linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
                #expect(close(srgb, restored, 1e-6))
            }
        }
    }

    @Test func decryptionCurvesAreMonotoneAndHitEndpoints() {
        #expect(DecryptionCurve.grow.sample(34.0) == 0 && DecryptionCurve.grow.sample(36.04) == 1)
        #expect(DecryptionCurve.retract.sample(37.72) == 1 && DecryptionCurve.retract.sample(39) == 0)
        for curve in DecryptionCurve.allCases {
            let rising = curve != .retract
            var last = curve.sample(30)
            for i in 0...1000 {
                let v = curve.sample(34 + Double(i) * 0.006)
                #expect(rising ? v >= last - 1e-12 : v <= last + 1e-12)
                last = v
            }
        }
    }
}
