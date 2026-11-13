import Testing
@testable import RhineKit

private func album(_ id: String, _ name: String, artist: String?, genre: String?) -> Album {
    Album(id: id, name: name, artist: artist, artistId: nil, year: nil, genre: genre, coverArt: nil,
          songCount: nil, duration: nil, created: nil, song: nil)
}

@Suite struct LibraryLayoutTests {
    let albums = [
        album("1", "Zeta", artist: "B  Band", genre: "Rock"),
        album("2", "阿尔法", artist: "b band", genre: nil),
        album("3", "beta", artist: "Alice", genre: "Rock"),
        album("4", "Album 10", artist: "Alice", genre: "Jazz"),
        album("5", "Album 2", artist: "Alice", genre: " "),
    ]

    @Test func genreColumnsKeepFirstSeenOrderAndUncategorised() {
        let layout = LibraryLayout(albums: albums, mode: .genre)
        #expect(layout.columnNames == ["Rock", "未分类", "Jazz"])
        #expect(layout.columns == [["1", "3"], ["2", "5"], ["4"]])
        #expect(layout.lane(of: "5") == 1 && layout.row(of: "5") == 1)
    }

    @Test func artistColumnsMergeSpellingsAndSortTitlesNumerically() {
        let layout = LibraryLayout(albums: albums, mode: .artist)
        // Upstream names the column after the first album in sorted order (阿尔法 < Zeta in pinyin).
        #expect(layout.columnNames == ["Alice", "b band"])
        #expect(layout.columns[0] == ["5", "4", "3"])
        #expect(Set(layout.columns[1]) == ["1", "2"])
    }

    @Test func listModesPlaceOneCardPerSongInListOrder() {
        // albumIds holds each song's album, in playlist order; repeats are kept.
        let groups = [LibraryGroup(name: "soul", albumIds: ["3", "1", "3", "missing", "1"]),
                      LibraryGroup(name: "empty", albumIds: ["missing"]),
                      LibraryGroup(name: "work", albumIds: ["1", "4"])]
        let layout = LibraryLayout(albums: albums, mode: .playlists, groups: groups)
        #expect(layout.columnNames == ["soul", "work"])
        #expect(layout.columns == [["0|0", "0|1", "0|2", "0|4"], ["2|0", "2|1"]])
        #expect(layout.albumId(for: "0|2") == "3")
        #expect(layout.key(forAlbum: "1") == "0|1")
        #expect(layout.lane(of: "2|1") == 1 && layout.ordinal("2|1") == 5)
        #expect(layout.album("1") == nil)
    }

    @Test func albumModeChunksByTwelve() {
        let many = (0..<30).map { album("\($0)", String(format: "T%02d", $0), artist: nil, genre: nil) }
        let layout = LibraryLayout(albums: many, mode: .album)
        #expect(layout.columnNames == ["01–12", "13–24", "25–30"])
        #expect(layout.columns.map(\.count) == [12, 12, 6])
        #expect(layout.ordinal("29") == 29)
    }
}
