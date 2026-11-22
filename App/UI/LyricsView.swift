import RhineKit
import SwiftUI
import UIKit

/// Timed LRC scrolls smoothly with distance-faded paper typography; plain text renders as a clean sheet.
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
                        LazyVStack(alignment: .leading, spacing: compact ? 10 : 16) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                let isActive = index == active
                                let distance = active.map { abs($0 - index) } ?? 0
                                let fade: Double = {
                                    guard active != nil else { return line.time == nil ? 0.92 : 0.78 }
                                    if isActive { return 1.0 }
                                    switch distance {
                                    case 1: return 0.62
                                    case 2: return 0.42
                                    default: return 0.24
                                    }
                                }()
                                Text(line.text)
                                    .font(.mi(compact ? 15 : 19, isActive ? .demibold : .regular))
                                    .lineSpacing(6)
                                    .foregroundStyle(isActive ? palette.accent : (line.time == nil ? palette.ink : palette.muted))
                                    .opacity(fade)
                                    .scaleEffect(isActive ? 1.03 : 1.0, anchor: .leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if playing, let t = line.time {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            model.player.seek(to: t)
                                        }
                                    }
                                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.36), value: active)
                                    .id(index)
                            }
                        }
                        .padding(.top, compact ? 28 : 48)
                        .padding(.bottom, compact ? 48 : 96)
                        .padding(.trailing, 8)
                    }
                    .scrollIndicators(.hidden)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                                 .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: active, initial: true) { _, index in
                        guard let index else { return }
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.52)) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(lines == nil ? "LOADING LYRICS" : "NO EMBEDDED LYRICS")
                        .font(.mi(8.5)).tracking(1.8).foregroundStyle(palette.muted)
                    Rectangle().fill(palette.line).frame(width: 44, height: 1)
                    Text(lines == nil ? "正在从 Navidrome 读取歌词…" : "《\(song.title)》暂未包含内嵌歌词")
                        .font(.mi(13)).foregroundStyle(palette.muted)
                }
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Third detail tab: album notes sheet.
struct AlbumAboutView: View {
    let album: Album
    let songs: [Song]
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT THIS ALBUM").font(.mi(8)).tracking(1.5).foregroundStyle(palette.muted).padding(.top, 24).padding(.bottom, 10)
            Text("\(album.artist ?? "未知歌手") · \(album.year.map(String.init) ?? "年份未提供") · \(album.genre ?? "未分类")")
                .font(.mi(12)).lineSpacing(9).foregroundStyle(palette.ink)
            Text("来源：Navidrome 音乐库").font(.mi(11)).foregroundStyle(palette.muted).padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 28)
    }
}
