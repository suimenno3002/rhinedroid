import Testing
@testable import RhineKit

@Suite struct LyricsParserTests {
    @Test func parsesMultiStampLinesSortedWithOffset() {
        let lines = LyricsParser.parse("[ti:Song]\n[offset:500]\n[00:12.50][01:02.00]副歌\n[00:05.1]第一句\n\n[00:20:30]旧格式")
        #expect(lines.map(\.text) == ["第一句", "副歌", "旧格式", "副歌"])
        let times = lines.compactMap(\.time)
        for (a, b) in zip(times, [4.6, 12.0, 19.8, 61.5]) { #expect(abs(a - b) < 1e-9) }
    }

    @Test func plainTextFallsBackToUntimedLines() {
        let lines = LyricsParser.parse("hello\r\n\r\nworld\n")
        #expect(lines == [LyricLine(time: nil, text: "hello"), LyricLine(time: nil, text: "world")])
    }

    @Test func activeIndexUsesLastStartedLine() {
        let lines = LyricsParser.parse("[00:01.00]a\n[00:03.00]b\n[00:05.00]c")
        #expect(LyricsParser.activeIndex(lines, at: 0.5) == nil)
        #expect(LyricsParser.activeIndex(lines, at: 1.0) == 0)
        #expect(LyricsParser.activeIndex(lines, at: 4.9) == 1)
        #expect(LyricsParser.activeIndex(lines, at: 99) == 2)
    }

    @Test func tokenMatchesSubsonicSpecExample() {
        // From the Subsonic API docs: password "sesame", salt "c19b2d".
        #expect(SubsonicClient.token(password: "sesame", salt: "c19b2d") == "26719a1196d2a940705a59634eb18eab")
    }
}
