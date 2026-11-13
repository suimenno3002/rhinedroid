// Ported from RhineDroid ShelfMotion.kt (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import Foundation

/// Same quintic position / velocity / acceleration handoff as music-archive-motion.ts.
/// Arrays are laid out as float4 per slot so they upload straight into the instance buffer.
public final class ShelfMotion {
    public struct Sample: Equatable, Sendable {
        public var position: Float
        public var velocity: Float = 0
        public var acceleration: Float = 0
    }

    public var origin = [Float](repeating: 0, count: ShelfLayout.count * 4)
    public var velocity = [Float](repeating: 0, count: ShelfLayout.count * 4)
    public var acceleration = [Float](repeating: 0, count: ShelfLayout.count * 4)
    public var target = [Float](repeating: 0, count: ShelfLayout.count * 4)
    public private(set) var start: Float = 0
    public private(set) var duration: Float = 0.001
    private var keys: [Int64] = []

    public init() {}

    public func settled(_ now: Float) -> Bool { now - start >= duration }

    public func sample(_ index: Int, _ axis: Int, _ now: Float) -> Sample {
        let n = index * 4 + axis
        if settled(now) { return Sample(position: target[n]) }
        let t = min(max(now - start, 0), duration)
        let D = duration
        let d = target[n] - origin[n] - velocity[n] * D - acceleration[n] * D * D / 2
        let v = -velocity[n] - acceleration[n] * D
        let a = -acceleration[n]
        let c3 = (10 * d - 4 * v * D + a * D * D / 2) / pow(D, 3)
        let c4 = (-15 * d + 7 * v * D - a * D * D) / pow(D, 4)
        let c5 = (6 * d - 3 * v * D + a * D * D / 2) / pow(D, 5)
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
        return Sample(
            position: origin[n] + velocity[n] * t + acceleration[n] * t2 / 2 + c3 * t3 + c4 * t4 + c5 * t5,
            velocity: velocity[n] + acceleration[n] * t + 3 * c3 * t2 + 4 * c4 * t3 + 5 * c5 * t4,
            acceleration: acceleration[n] + 6 * c3 * t + 12 * c4 * t2 + 20 * c5 * t3)
    }

    public func retarget(_ cells: [ShelfLayout.Cell], detail: Float, now: Float, seconds: Float, dx: Float = 0, dz: Float = 0) {
        var previous: [Int64: Int] = [:]
        for (i, key) in keys.enumerated() { previous[key] = i }
        let old = (0..<keys.count).map { i in (0..<3).map { sample(i, $0, now) } }
        let center = old.indices.contains(ShelfLayout.selected) ? old[ShelfLayout.selected] : nil
        let nextKeys = cells.map { (Int64($0.physicalLane) << 32) ^ (Int64($0.physicalRow) & 0xffff_ffff) }
        let halfRows = Float(ShelfLayout.rows / 2)
        for (i, cell) in cells.enumerated() {
            let distance = cell.z / 0.62
            let shoulder = Float(ArchivePose.shoulder(row: Double(distance), lane: Double(cell.x / 5.2)))
            let lift: Float = i == ShelfLayout.selected ? 0.9 + detail * 2.57 : 0
            let end: [Float] = [cell.x, -4.6 + shoulder + lift, cell.z]
            let source = previous[nextKeys[i]].map { old[$0] }
            for axis in 0..<3 {
                let fallback: Float
                switch axis {
                case 0: fallback = end[0] + min(max(dx, -5.2), 5.2) + (center?[0].position ?? 0)
                case 2: fallback = end[2] + min(max(dz, -0.62 * halfRows), 0.62 * halfRows) + (center?[2].position ?? 0)
                default: fallback = end[1] - lift
                }
                let state = source?[axis] ?? Sample(position: fallback)
                let n = i * 4 + axis
                target[n] = end[axis]
                origin[n] = seconds <= 0 || previous.isEmpty ? end[axis] : state.position
                velocity[n] = seconds <= 0 ? 0 : state.velocity
                acceleration[n] = seconds <= 0 ? 0 : state.acceleration
            }
        }
        keys = nextKeys
        start = now
        duration = max(0.001, seconds)
    }

    public static func duration(lanes: Float, rows: Float) -> Float {
        1.4 + min(max((hypot(lanes, rows / 8) - 1) / 7, 0), 1)
    }

    public static func occurrence(_ index: Int, center: Int, count: Int, direction: Int = 0) -> Int {
        guard count > 0 else { return 0 }
        let nearby = index + Int((Double(center - index) / Double(count) + 0.5).rounded(.down)) * count
        if direction > 0 && nearby <= center { return nearby + count }
        if direction < 0 && nearby >= center { return nearby - count }
        return nearby
    }
}
