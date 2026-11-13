// Ported from RhineDroid ArchivePalette.kt, ArtworkSlots.kt, AudioEnvelope.kt and web/src/decryption.ts
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import Foundation

/// The same sRGB paper colors as music.css, converted only at the GPU boundary.
public enum ArchivePalette {
    static let day: SIMD3<Double> = [232, 229, 225]
    static let night: SIMD3<Double> = [8, 18, 31]

    public static func channels(_ progress: Double) -> SIMD3<Double> {
        let p = min(max(progress, 0), 1)
        return (day + (night - day) * p) / 255
    }

    public static func linear(_ value: Double) -> Float {
        Float(value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
    }

    public static func linear(_ progress: Double) -> SIMD3<Float> {
        let c = channels(progress)
        return SIMD3(linear(c.x), linear(c.y), linear(c.z))
    }

    public static func color(_ progress: Double) -> UInt32 {
        let c = (channels(progress) * 255).rounded(.toNearestOrAwayFromZero)
        return 0xff00_0000 | UInt32(c.x) << 16 | UInt32(c.y) << 8 | UInt32(c.z)
    }
}

/// Stable texture addresses: scrolling never invalidates already loaded covers.
public final class ArtworkSlots {
    public final class Entry {
        public let id: String
        public let slot: Int
        public var ready = false
        init(id: String, slot: Int) { self.id = id; self.slot = slot }
    }

    private let capacity: Int
    private var entries: [String: Entry] = [:]
    /// Access order, oldest first (mirrors LinkedHashMap(accessOrder = true)).
    private var order: [String] = []

    public init(capacity: Int = 256) { self.capacity = capacity }

    private func touch(_ id: String) {
        if let i = order.firstIndex(of: id) { order.remove(at: i) }
        order.append(id)
    }

    public func bind(_ ids: [String]) -> [Entry] {
        let wanted = Set(ids)
        precondition(wanted.count <= capacity)
        var seen = Set<String>()
        var result: [Entry] = []
        for id in ids where seen.insert(id).inserted {
            if let entry = entries[id] {
                touch(id)
                result.append(entry)
                continue
            }
            let slot: Int
            if entries.count < capacity {
                let used = Set(entries.values.map(\.slot))
                slot = (0..<capacity).first { !used.contains($0) }!
            } else {
                let victim = order.first { !wanted.contains($0) }!
                order.removeAll { $0 == victim }
                slot = entries.removeValue(forKey: victim)!.slot
            }
            let entry = Entry(id: id, slot: slot)
            entries[id] = entry
            order.append(id)
            result.append(entry)
        }
        return result
    }

    public func get(_ id: String) -> Entry? { entries[id] }

    @discardableResult
    public func ready(_ id: String, slot: Int) -> Bool {
        guard let entry = entries[id], entry.slot == slot else { return false }
        touch(id)
        entry.ready = true
        return true
    }

    public func clear() { entries.removeAll(); order.removeAll() }
}

/// Linear gain envelope used for the 450 ms song-transition fades.
public struct AudioEnvelope: Sendable {
    private var from: Float
    public private(set) var target: Float
    private var start: Double = 0
    private var duration: Double = 0

    public init(_ initial: Float = 1) { from = initial; target = initial }

    public func sample(_ now: Double) -> Float {
        guard duration > 0 else { return target }
        return from + (target - from) * Float(min(max((now - start) / duration, 0), 1))
    }

    /// Upstream compares integer milliseconds; seconds need a tolerance for the same exact boundary.
    public func settled(_ now: Double) -> Bool { now - start >= duration - 1e-9 }

    public mutating func to(_ value: Float, now: Double, seconds: Double) {
        precondition(value.isFinite && (0...1).contains(value) && seconds >= 0)
        from = sample(now); target = value; start = now; duration = seconds
    }
}

/// Monotone cubic Hermite curves measured from the reference footage (decryption.ts).
public enum DecryptionCurve: CaseIterable, Sendable {
    case grow, reveal, retract

    public static let start = 34.12
    public static let end = 39.56
    public static let interactiveRate = 1.5

    public var knots: [(Double, Double)] {
        switch self {
        case .grow: [(34.24, 0), (34.4, 0.19), (34.64, 0.57), (34.96, 0.79), (35.28, 0.92), (35.6, 0.973), (36.04, 1)]
        case .reveal: [(38.84, 0), (38.92, 0.28), (39.0, 0.51), (39.16, 0.74), (39.32, 0.94), (39.56, 1)]
        case .retract: [(37.72, 1), (37.88, 0.72), (38.0, 0.38), (38.12, 0.22), (38.24, 0.14), (38.4, 0.075), (38.64, 0.024), (38.84, 0)]
        }
    }

    /// Hermite tangents per knot; end velocities are zero.
    public var slopes: [Double] {
        let k = knots
        func secant(_ i: Int) -> Double { (k[i + 1].1 - k[i].1) / (k[i + 1].0 - k[i].0) }
        return k.indices.map { i in
            if i == 0 || i == k.count - 1 { return 0 }
            let a = secant(i - 1), b = secant(i)
            if a * b <= 0 { return 0 }
            let left = k[i].0 - k[i - 1].0, right = k[i + 1].0 - k[i].0
            let w1 = 2 * right + left, w2 = right + 2 * left
            return (w1 + w2) / (w1 / a + w2 / b)
        }
    }

    public func sample(_ time: Double) -> Double {
        let k = knots
        if time <= k[0].0 { return k[0].1 }
        if time >= k[k.count - 1].0 { return k[k.count - 1].1 }
        let m = slopes
        var i = 0
        while time > k[i + 1].0 { i += 1 }
        let span = k[i + 1].0 - k[i].0
        let t = (time - k[i].0) / span, t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * k[i].1 + (t3 - 2 * t2 + t) * span * m[i]
            + (-2 * t3 + 3 * t2) * k[i + 1].1 + (t3 - t2) * span * m[i + 1]
    }
}
