/// One lyric line; `time` is nil for unsynchronised text.
public struct LyricLine: Equatable, Sendable {
    public var time: Double?
    public var text: String

    public init(time: Double?, text: String) {
        self.time = time
        self.text = text
    }
}

/// Parses LRC (`[mm:ss.xx]text`, multiple stamps per line, `[offset:±ms]`) or falls back to plain lines.
public enum LyricsParser {
    public static func parse(_ source: String) -> [LyricLine] {
        var offset = 0.0
        var timed: [LyricLine] = []
        var plain: [LyricLine] = []
        for raw in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var stamps: [Double] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                if let time = timestamp(tag) {
                    stamps.append(time)
                } else if tag.hasPrefix("offset:"), let ms = Double(tag.dropFirst(7).trimmed) {
                    offset = ms / 1000
                }
            }
            let text = String(rest.trimmed)
            if stamps.isEmpty {
                if !text.isEmpty { plain.append(LyricLine(time: nil, text: text)) }
            } else {
                timed += stamps.map { LyricLine(time: $0, text: text) }
            }
        }
        guard !timed.isEmpty else { return plain }
        // LRC offset: positive values make lyrics appear sooner.
        return timed
            .map { LyricLine(time: max(0, $0.time! - offset), text: $0.text) }
            .sorted { $0.time! < $1.time! }
    }

    /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx`, `mm:ss:xx`.
    static func timestamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = Int(parts[0]), minutes >= 0 else { return nil }
        if parts.count == 3 {
            guard let seconds = Int(parts[1]), let fraction = Int(parts[2]) else { return nil }
            return Double(minutes * 60 + seconds) + Double(fraction) / pow10(parts[2].count)
        }
        guard let seconds = Double(parts[1]), seconds >= 0, seconds < 60 else { return nil }
        return Double(minutes * 60) + seconds
    }

    private static func pow10(_ n: Int) -> Double { (0..<n).reduce(1.0) { r, _ in r * 10 } }

    /// Index of the line active at `time` (binary search), or nil before the first line.
    public static func activeIndex(_ lines: [LyricLine], at time: Double) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if let t = lines[mid].time, t <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }
}

private extension Substring {
    var trimmed: Substring {
        var s = self
        while s.first?.isWhitespace == true { s.removeFirst() }
        while s.last?.isWhitespace == true { s.removeLast() }
        return s
    }
}
