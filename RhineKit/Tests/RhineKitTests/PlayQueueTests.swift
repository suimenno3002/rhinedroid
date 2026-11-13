import Testing
@testable import RhineKit

private func songs(_ n: Int) -> [Song] {
    (0..<n).map {
        Song(id: "s\($0)", title: "T\($0)", album: nil, albumId: nil, artist: nil, track: $0 + 1, discNumber: nil, year: nil,
             genre: nil, coverArt: nil, duration: 100, bitRate: nil, suffix: "flac", contentType: "audio/flac", starred: nil)
    }
}

@Suite struct PlayQueueTests {
    @Test func naturalEndRespectsRepeatModes() {
        var q = PlayQueue(songs: songs(3), start: 2)
        #expect(q.autoNext() == nil)
        #expect(q.finish() == nil)
        #expect(q.current == nil)

        q = PlayQueue(songs: songs(3), start: 2)
        q.repeatMode = .all
        #expect(q.finish()?.id == "s0")

        q.repeatMode = .one
        #expect(q.finish()?.id == "s0")
        #expect(q.autoNextSong?.id == "s0")
    }

    @Test func userSkipEscapesRepeatOneAndStopsAtEndWhenOff() {
        var q = PlayQueue(songs: songs(3), start: 1)
        q.repeatMode = .one
        #expect(q.skip()?.id == "s2")
        #expect(q.skip()?.id == "s0")
        q.repeatMode = .off
        #expect(q.back()?.id == "s0")
        q.jump(toSong: 2)
        #expect(q.skip() == nil)
        #expect(q.current?.id == "s2")
    }

    @Test func shuffleKeepsCurrentFirstAndUnshuffleRestoresAlbumOrder() {
        var q = PlayQueue(songs: songs(20), start: 7)
        q.setShuffle(true)
        #expect(q.current?.id == "s7")
        #expect(q.position == 0)
        #expect(Set(q.order) == Set(0..<20))
        q.skip(); q.skip()
        let playing = q.current!.id
        q.setShuffle(false)
        #expect(q.current?.id == playing)
        #expect(q.order == Array(0..<20))
    }

    @Test func playNextAppendAndRemoveKeepCurrent() {
        var q = PlayQueue(songs: songs(3), start: 1)
        q.playNext(songs(1).map { _ in Song(id: "x", title: "X", album: nil, albumId: nil, artist: nil, track: nil, discNumber: nil, year: nil, genre: nil, coverArt: nil, duration: 1, bitRate: nil, suffix: nil, contentType: nil, starred: nil) })
        #expect(q.autoNextSong?.id == "x")
        q.remove(at: 0)
        #expect(q.current?.id == "s1")
        #expect(q.upcoming.map { q.songs[$0].id } == ["s1", "x", "s2"])
        q.remove(at: q.position)
        #expect(q.current?.id == "s1")
    }
}
