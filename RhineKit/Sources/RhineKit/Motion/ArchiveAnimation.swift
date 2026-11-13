// Ported from RhineDroid ArchiveAnimation.kt (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import Foundation
import simd

/// Original music-camera.ts placement curve, sampled on the renderer's shared clock.
public struct ArchiveScalar: Sendable {
    public struct Sample: Equatable, Sendable {
        public var value: Double
        public var velocity: Double = 0
        public var acceleration: Double = 0
    }

    private var origin: Double
    private var velocity = 0.0
    private var acceleration = 0.0
    public private(set) var target: Double
    private var start = -1e9
    private var duration = 0.001

    public init(_ initial: Double = 0) { origin = initial; target = initial }

    public func settled(_ now: Double) -> Bool { now - start >= duration }

    public func sample(_ now: Double) -> Sample {
        if settled(now) { return Sample(value: target) }
        let t = min(max((now - start) / duration, 0), 1)
        let D = duration
        let d = target - origin - velocity * D - acceleration * D * D / 2
        let v = -velocity - acceleration * D
        let a = -acceleration
        let c3 = 10 * d - 4 * v * D + a * D * D / 2
        let c4 = -15 * d + 7 * v * D - a * D * D
        let c5 = 6 * d - 3 * v * D + a * D * D / 2
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t, t5 = t4 * t
        let value = origin + velocity * D * t + acceleration * D * D * t2 / 2 + c3 * t3 + c4 * t4 + c5 * t5
        return Sample(value: value,
                      velocity: velocity + acceleration * D * t + (3 * c3 * t2 + 4 * c4 * t3 + 5 * c5 * t4) / D,
                      acceleration: acceleration + (6 * c3 * t + 12 * c4 * t2 + 20 * c5 * t3) / (D * D))
    }

    public mutating func to(_ value: Double, now: Double, seconds: Double) {
        let current = sample(now)
        origin = seconds <= 0 ? value : current.value
        velocity = seconds <= 0 ? 0 : current.velocity
        acceleration = seconds <= 0 ? 0 : current.acceleration
        target = value
        start = now
        duration = max(0.001, seconds)
    }
}

/// Closed-form critically damped spring from motion.ts; frame rate does not change the path.
public struct ArchiveSpring: Sendable {
    public var value: Double
    public var velocity = 0.0

    public init(_ value: Double = 0) { self.value = value }

    public mutating func update(target: Double, dt: Double, rate: Double = 9, immediate: Bool = false) {
        if immediate { value = target; velocity = 0; return }
        let delta = value - target
        let impulse = velocity + rate * delta
        let decay = exp(-rate * max(0, dt))
        value = target + (delta + impulse * dt) * decay
        velocity = (velocity - rate * impulse * dt) * decay
    }

    public func settled(target: Double, position: Double = 0.008, speed: Double = 0.035) -> Bool {
        abs(value - target) < position && abs(velocity) < speed
    }
}

public enum ArchivePose {
    public struct Camera: Equatable, Sendable {
        public var position: SIMD3<Double>
        public var aim: SIMD3<Double>
        public var span: Double
    }

    public static let placementSeconds = 1.45 / 1.05

    public static func focusDistance(_ camera: Camera, point: SIMD3<Double>) -> Double {
        let axis = camera.aim - camera.position
        let distance = max(simd_length(axis), 0.001)
        return max(simd_dot(point - camera.position, axis) / distance, 0.1)
    }

    @inline(__always) public static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (10 + t * (-15 + 6 * t))
    }

    private static func shoulderAt(row: Double, time: Double) -> Double {
        let age = time - 25.05 - abs(row) * 0.065
        let envelope = max(-0.42, 2.15 - 0.17 * (sqrt(row * row + 1) - 1))
        let ring = age > 0 ? sin(age * 5.1) * exp(-age * 1.3) : 0
        let rebound = 0.06 + 0.12 * smooth((time - 26.2) / 0.36)
        return envelope * (smooth(age / 0.62) + rebound * ring * smooth(age / 0.16))
    }

    public static func shoulder(row: Double, lane: Double) -> Double {
        shoulderAt(row: row, time: 26.56) * (0.25 + 0.75 * exp(-0.5 * pow(lane / 0.55, 2)))
    }

    public static func introEntryZ(_ time: Double) -> Double {
        -23 * pow(1 - min(max((time - 21.92) / 0.75, 0), 1), 2)
    }

    /// Camera anchoring samples the same height as the shader; it never moves the mesh on the CPU.
    public static func openingHeight(row: Double, lane: Double, time: Double) -> Double {
        func bell(_ x: Double, _ width: Double) -> Double { exp(-0.5 * pow(x / width, 2)) }
        func packet(_ x: Double) -> Double { 2.5 * bell(x, 3.8) - 0.58 * bell(x - 6, 3.5) }
        let t = time - 22, phase = row + 12 + lane * 0.65
        let wave = smooth(t / 0.32) * (packet(phase - 3 - t * 19) * (1 - smooth((t - 2.15) / 0.65)) +
            packet(phase - 32 + (t - 2.3) * 24) * smooth((t - 2.17) / 0.32) * (1 - smooth((t - 3.5) / 0.85)))
        let handoff = smooth((time - 24.95) / 0.45), selection = smooth((time - 25.4) / 0.95)
        let weight = 0.25 + 0.75 * bell(lane, 0.55)
        let field = 0.62 * wave * (1 - handoff) + shoulderAt(row: row, time: time + 0.3 * handoff * (1 - selection)) * (1 + (weight - 1) * selection)
        return field + (shoulder(row: row, lane: lane) - field) * smooth((time - 25.3) / 1.42)
    }

    public static func camera(width: Int, height: Int, detail: Double, overview: Double, intro: Double? = nil) -> Camera {
        let aspect = Double(width) / Double(max(1, height))
        let portrait = aspect < 1.05
        let orbit = intro.map { smooth(($0 - 22.6) / 1.6) } ?? 1
        let settle = intro.map { smooth(($0 - 24.25) / 2.25) } ?? 1
        var yaw = (89 - 22 * orbit - 8 * settle) * (1 - detail) + 8 * detail
        var baseElevation = 25.0
        if let intro {
            let rise: Double = 40 * smooth((intro - 21.96) / 0.22)
            let land: Double = 6 * smooth((intro - 25.3) / 1.42)
            baseElevation = 3 + rise - 8 * orbit - 16 * settle + land
        }
        var elevation = baseElevation * (1 - detail) + 20 * detail
        yaw += (28 - yaw) * overview
        elevation += (43 - elevation) * overview
        let y = yaw * .pi / 180, e = elevation * .pi / 180
        let direction = SIMD3(-sin(y) * cos(e), sin(e), cos(y) * cos(e))
        let right = SIMD3(cos(y), 0, sin(y))
        let up = SIMD3(sin(y) * sin(e), cos(e), -cos(y) * sin(e))
        let baseSpan = ((10.8 + (10.3 - 10.8) * orbit) * (1 - settle) + 7.33 * settle) * (1 - detail) + 5.9 * detail
        let h = Double(height)
        let portraitDetail = max(6.3 / aspect, 3.7 * h / max(100, 0.54 * h - 156))
        var span = portrait ? max(baseSpan, 8.4 / aspect + (portraitDetail - 8.4 / aspect) * detail)
                            : max(baseSpan, baseSpan * (16.0 / 9) / aspect)
        let wide = smooth((aspect - 16.0 / 9) / (21.0 / 9 - 16.0 / 9))
        let arrayAim = SIMD3(-1.091, (-2.55 + 0.4 * orbit) * (1 - settle) - 0.045 * settle, 2.48 + (0.481 - 2.48) * settle + 2.17)
        var preview = arrayAim
        let introBlend = intro.map { smooth(($0 - 25.3) / 1.42) } ?? 1
        if let intro {
            let pan = smooth((intro - 25.4) / 0.95)
            preview += right * (-2.05 * (1 - pan) * smooth((intro - 24.2) / 0.8))
            if intro >= 25.05 {
                let tracking = smooth((intro - 25.4) / 1.05)
                let lift = 0.4 * smooth((intro - 25.58) / 0.82) + 2.95 * smooth((intro - 27.55) / 1.3)
                let modelLift = lift + (0.9 - lift) * introBlend
                let anchorY: Double = -4.6 + openingHeight(row: 0, lane: 0, time: intro) + modelLift + 3.525
                var anchor = SIMD3<Double>(-2.225, anchorY, introEntryZ(intro))
                let pixelScale: Double = 1080 / baseSpan
                let dx: Double = (120 + 322 * tracking) / pixelScale
                let dy: Double = (-200 - 52 * tracking) / pixelScale
                anchor += right * dx
                anchor += up * dy
                preview += (anchor - preview) * smooth((intro - 25.05) / 0.35)
            }
        }
        let rest: Double = -4.6 + shoulder(row: 0, lane: 0)
        var destination: SIMD3<Double> = portrait ? SIMD3(0, rest + 0.4 + 1.85, 0) : arrayAim
        let shiftX: Double = portrait ? 0 : 0.035 * wide
        let shiftY: Double = portrait ? 0.36 - 0.5 : 0.08 + 0.02 * wide
        destination += right * (shiftX * span * aspect)
        destination += up * (shiftY * span)
        preview += (destination - preview) * introBlend
        var inspected = SIMD3<Double>(0, rest + 3.47 + 1.85, 0)
        let detailX: Double = (portrait ? 0 : 0.25) * span * aspect
        let detailY: Double = ((portrait ? 0.27 + 34.0 / h : 0.49) - 0.5) * span
        inspected += right * detailX
        inspected += up * detailY
        var aim = preview + (inspected - preview) * detail
        aim += (SIMD3(0, -1.8, 0.67) - aim) * overview
        span += (max(16.8, 17.5 / aspect) - span) * overview
        let distance = ((28 + 7 * orbit) * (1 - settle) + 140 * settle) * (1 - detail) + 72 * detail
        return Camera(position: aim + direction * (distance + (172 - distance) * overview), aim: aim, span: span)
    }
}

/// Placement already has its own curve; only a viewport change needs another transition.
public struct ArchiveCameraMotion: Sendable {
    public private(set) var pose: ArchivePose.Camera?
    private var from: ArchivePose.Camera?
    private var start = 0.0
    public var moving: Bool { from != nil }

    public init() {}

    public mutating func resize(now: Double) { from = pose; start = now }

    public mutating func sample(_ target: ArchivePose.Camera, now: Double, immediate: Bool = false) -> ArchivePose.Camera {
        let blend = immediate ? 1 : ArchivePose.smooth((now - start) / 0.32)
        let value: ArchivePose.Camera
        if let origin = from, blend < 1 {
            value = .init(position: origin.position + (target.position - origin.position) * blend,
                          aim: origin.aim + (target.aim - origin.aim) * blend,
                          span: origin.span + (target.span - origin.span) * blend)
        } else {
            value = target
        }
        if blend >= 1 || immediate { from = nil }
        pose = value
        return value
    }
}
