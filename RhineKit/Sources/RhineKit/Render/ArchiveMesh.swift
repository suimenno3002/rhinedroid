// Swift port of RhineDroid scripts/build-vulkan-assets.mjs (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
// Reads the authored case GLB directly at launch instead of a prebuilt archive.mesh.
import Foundation

/// Three non-indexed triangle lists, 8 floats per vertex: position.xyz, normal.xyz (custom0), uv.
/// kind 0 = shell + spine (uv.x = 1 on Ivory_Edges), kind 1 = frosted lid, kind 2 = cover insert quad.
public struct ArchiveMesh: Sendable {
    public static let stride = 32
    public private(set) var kinds: [[Float]] = [[], [], []]

    public enum LoadError: Error { case notGLB, unsupported(String) }

    public init(glb data: Data) throws {
        func u32(_ offset: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) } }
        guard data.count > 28, u32(0) == 0x4654_6C67 else { throw LoadError.notGLB }
        let jsonLength = Int(u32(12))
        let json = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + jsonLength))) as! [String: Any]
        let binary = data.subdata(in: (28 + jsonLength)..<data.count)

        let accessors = json["accessors"] as! [[String: Any]]
        let views = json["bufferViews"] as! [[String: Any]]
        let meshes = json["meshes"] as! [[String: Any]]
        let materials = json["materials"] as! [[String: Any]]
        let nodes = json["nodes"] as! [[String: Any]]

        func accessor(_ id: Int) throws -> [[Float]] {
            let a = accessors[id], v = views[a["bufferView"] as! Int]
            let components = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4][a["type"] as! String]!
            let type = a["componentType"] as! Int
            let size = [5123: 2, 5125: 4, 5126: 4][type] ?? 0
            guard size > 0, a["sparse"] == nil else { throw LoadError.unsupported("accessor \(id)") }
            let base = (v["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let stride = v["byteStride"] as? Int ?? components * size
            return binary.withUnsafeBytes { raw in
                (0..<(a["count"] as! Int)).map { i in
                    (0..<components).map { c in
                        let o = base + i * stride + c * size
                        switch type {
                        case 5126: return raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                        case 5123: return Float(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
                        default: return Float(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                        }
                    }
                }
            }
        }

        // The source GLB stores its authored final geometry in identity nodes.
        for node in nodes where node["matrix"] != nil || node["translation"] != nil || node["rotation"] != nil || node["scale"] != nil {
            throw LoadError.unsupported("node transform \(node)")
        }
        for node in nodes {
            guard let meshIndex = node["mesh"] as? Int else { continue }
            for primitive in meshes[meshIndex]["primitives"] as! [[String: Any]] {
                let attributes = primitive["attributes"] as! [String: Int]
                let positions = try accessor(attributes["POSITION"]!)
                let normals = try accessor(attributes["NORMAL"]!)
                let indices = try accessor(primitive["indices"] as! Int).map { Int($0[0]) }
                let name = materials[primitive["material"] as! Int]["name"] as! String
                let kind = name.hasPrefix("Frosted_Polymer") ? 1 : 0
                let spine: Float = name == "Ivory_Edges" ? 1 : 0
                for i in indices {
                    var p = positions[i]
                    p[0] = Self.narrow(p[0])
                    kinds[kind] += p + normals[i] + [spine, 0]
                }
            }
        }
        // Cover insert: a 3.06 square centred on the case window, uv v = 0 at the top edge.
        let x: Float = 0.17, y: Float = 1.85, z: Float = 0.027, h: Float = 3.06 / 2
        for (a, b, u, v) in [(-1, -1, 0, 1), (1, -1, 1, 1), (-1, 1, 0, 0), (-1, 1, 0, 0), (1, -1, 1, 1), (1, 1, 1, 0)] as [(Float, Float, Float, Float)] {
            kinds[2] += [x + a * h, y + b * h, z, 0, 0, 1, u, v]
        }
        for (kind, values) in kinds.enumerated() where values.isEmpty || values.count % 24 != 0 {
            throw LoadError.unsupported("kind \(kind) has \(values.count) floats")
        }
    }

    public func vertexCount(_ kind: Int) -> Int { kinds[kind].count / 8 }

    /// Not upstream: the authored case is 4.1 wide around a 3.06 square cover (0.52 side margins vs
    /// 0.145 top/bottom). Side margins are compressed to `marginScale`, the spine keeps its width.
    static let marginScale: Float = 0.38
    static let coverHalf: Float = 1.53, marginEnd: Float = 2.05, centre: Float = 0.17

    static func narrow(_ x: Float) -> Float {
        let d = x - centre, a = abs(d)
        guard a > coverHalf else { return x }
        let squeezed = coverHalf + (min(a, marginEnd) - coverHalf) * marginScale + max(0, a - marginEnd)
        return centre + (d < 0 ? -squeezed : squeezed)
    }

    /// Left (spine) edge of the case after narrowing, used by the top-ribbon falloff in the shader.
    public static var spineEdge: Float { narrow(-2.225) }
}
