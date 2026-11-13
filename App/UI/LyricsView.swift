import RhineKit
import SwiftUI

/// Not in upstream. Timed LRC scrolls and highlights the active line in --accent (track-row "playing"
/// colour); plain text from Navidrome 0.47 `getLyrics` is shown as a static sheet.
@MainActor @Observable
final class LyricsStore {
    static let shared = LyricsStore()
    private(set) var cache: [String: [LyricLine]] = [:]
    private var loading = Set<String>()

    func lines(for song: Song, client: SubsonicClient?) -> [LyricLine]? {
        if let lines = cache[song.id] { return lines }
        guard let client, !loading.contains(song.id) else { return nil }
        loading.insert(song.id)
        Task {
            let text = try? await client.lyrics(artist: song.artist ?? "", title: song.title)
            cache[song.id] = text.map(LyricsParser.parse) ?? []
            loading.remove(song.id)
        }
        return nil
    }
}

struct LyricsView: View {
    let song: Song
    var compact = false
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let lines = LyricsStore.shared.lines(for: song, client: model.client)
        let playing = model.player.current?.id == song.id
        let active = playing ? LyricsParser.activeIndex(lines ?? [], at: model.player.currentTime) : nil
        Group {
            if let lines, !lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: compact ? 6 : 9) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.text)
                                    .font(.mi(compact ? 13 : 14, index == active ? .demibold : .regular))
                                    .foregroundStyle(index == active ? palette.accent : (line.time == nil ? palette.ink : palette.muted))
                                    .opacity(active == nil || index == active ? 1 : 0.72)
                                    .onTapGesture { if playing, let t = line.time { model.player.seek(to: t) } }
                                    .id(index)
                            }
                        }
                        .padding(.vertical, compact ? 40 : 16)
                    }
                    .scrollIndicators(.hidden)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                 .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: active) { _, index in
                        guard let index else { return }
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                Text(lines == nil ? "正在读取歌词…" : "这首歌没有内嵌歌词")
                    .font(.mi(11)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
    }
}

/// Second detail tab: lyrics for the playing (or first) track, then album notes.
struct LyricsAndAbout: View {
    let album: Album
    let songs: [Song]
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let current = model.player.current.flatMap { song in songs.first { $0.id == song.id } }
        VStack(alignment: .leading, spacing: 0) {
            Text("LYRICS / 歌词").font(.mi(8)).tracking(1.5).foregroundStyle(palette.muted).padding(.top, 20).padding(.bottom, 8)
            if let song = current ?? songs.first {
                Text(song.title).font(.mi(12, .demibold)).padding(.bottom, 4)
                LyricsView(song: song).frame(minHeight: 120, maxHeight: 360)
            }
            Text("ABOUT THIS ALBUM").font(.mi(8)).tracking(1.5).foregroundStyle(palette.muted).padding(.top, 24).padding(.bottom, 8)
            Text("\(album.artist ?? "未知歌手") · \(album.year.map(String.init) ?? "年份未提供") · \(album.genre ?? "未分类")")
                .font(.mi(11)).lineSpacing(9).foregroundStyle(palette.muted)
            Text("来源：Navidrome 音乐库").font(.mi(11)).foregroundStyle(palette.muted).padding(.top, 9)
        }
    }
}
