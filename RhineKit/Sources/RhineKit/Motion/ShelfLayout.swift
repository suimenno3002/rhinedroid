// Ported from RhineDroid ShelfLayout.kt (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).

/// Fixed GPU slots; library size never increases per-frame submission work.
public enum ShelfLayout {
    public static let columns = 7
    public static let rows = 31
    public static let count = columns * rows
    public static let selected = count / 2
    public static let introColumns = 9
    public static let introRows = 49
    public static let introCount = introColumns * introRows

    public struct Cell: Equatable, Sendable {
        public let lane: Int
        public let row: Int
        public let album: String?
        public let x: Float
        public let z: Float
        public let physicalLane: Int
        public let physicalRow: Int
    }

    public static func cells(_ columns: [[String]], lane: Int, row: Int, filled: Bool) -> [Cell] {
        (0..<count).map { slot in
            let dx = slot / rows - self.columns / 2
            let dz = slot % rows - rows / 2
            let column = filled && !columns.isEmpty ? floorMod(lane + dx, columns.count) : lane + dx
            let songs = columns.indices.contains(column) ? columns[column] : []
            let center: Float = filled || column == lane ? Float(row) : Float(songs.count - 1) / 2
            let raw = Int(center.rounded(.toNearestOrAwayFromZero)) + dz
            let item = filled && !songs.isEmpty ? floorMod(raw, songs.count) : raw
            return Cell(lane: column, row: item, album: songs.indices.contains(item) ? songs[item] : nil,
                        x: Float(dx) * 5.2, z: (Float(raw) - center) * 0.62,
                        physicalLane: lane + dx, physicalRow: raw)
        }
    }

    @inline(__always) static func floorMod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
}
