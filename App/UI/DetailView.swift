// Layout from RhineDroid web/src/music.css + android.css (#album-detail-content, .album-facts, .music-tabs, .track-row)
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import RhineKit
import SwiftUI
import UIKit

/// Album detail panel: landscape left 53 % → right 20, top 85, bottom 30; portrait below 51 %.
struct DetailView: View {
    let portrait: Bool
    let size: CGSize
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var tab = 0
    @Namespace private var tabUnderline

    var body: some View {
        if let album = model.selected {
            let detail = model.details[album.id]
            let songs = detail?.song ?? []
            // List modes: the card is a song; the track list is the playlist / liked column in its order.
            let song = model.selectedSong
            let listSongs = model.listSongs(for: model.selectedId)
            let row = model.listPosition(for: model.selectedId)?.index ?? 0
            let titleParts = splitBilingualTitle(song?.title ?? album.name)
            let activeLyricSong: Song? = {
                if let song { return song }
                if let current = model.player.current, songs.contains(where: { $0.id == current.id }) { return current }
                return songs.first
            }()

            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    // Pinned: info, transport and tabs stay put; only the list / lyrics below scrolls.
                    VStack(alignment: .leading, spacing: 0) {
                        let counter = song == nil
                            ? "ALBUM \(String(format: "%03d", (model.layout.ordinal(model.selectedId) ?? 0) + 1))"
                            : "TRACK \(String(format: "%02d", row + 1)) / \(String(format: "%02d", listSongs.count))"
                        VStack(alignment: .leading, spacing: 4) {
                            Text(titleParts.main).font(.mi(25, .demibold)).tracking(-0.6)
                                .lineLimit(2).truncationMode(.tail)
                            if let trans = titleParts.translation {
                                Text(trans).font(.mi(12.5, .demibold)).tracking(0.2)
                                    .foregroundStyle(palette.muted).lineLimit(1).truncationMode(.tail)
                            }
                        }
                        .padding(.trailing, 96)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topTrailing) {
                            Text(counter).font(.mi(8)).tracking(1.6).foregroundStyle(palette.muted)
                                .monospacedDigit().padding(.top, 10)
                        }
                        .padding(.top, 8).padding(.bottom, 10)
                        // Browsing another card: the way back sits at the right of this line, as an overlay,
                        // so it never changes the height of the title block.
                        let playing = model.player.current.flatMap { s in model.playingKey.flatMap { $0 != model.selectedId ? s : nil } }
                        Text(song.map { "\($0.artist ?? "未知歌手")  ·  \(album.name)" } ?? (album.artist ?? "未知歌手"))
                            .font(.mi(14)).lineLimit(1)
                            .padding(.trailing, playing == nil ? 0 : 168)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .trailing) {
                                if let playing {
                                    Button { model.jumpToPlaying() } label: {
                                        HStack(spacing: 6) {
                                            Circle().fill(palette.accent).frame(width: 5, height: 5)
                                            Text("正在播放 · \(playing.title)").lineLimit(1)
                                        }
                                        .font(.mi(10)).foregroundStyle(palette.ink)
                                        .frame(maxWidth: 160, alignment: .trailing)
                                        .frame(height: 32).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .hoverEffect(.highlight)
                                    .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: playing?.id)
                            .padding(.bottom, 14)
                        // The rule under the title is the progress line.
                        DetailProgress()
                        facts(album, songs, song: song)
                        tabs()
                    }
                    .foregroundStyle(palette.ink)
                    .padding(.trailing, 6)

                    // Bottom area: lyrics owns its own ScrollView directly (no nested scrolling).
                    Group {
                        if tab == 0 {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
                                    if song != nil { listTracks(listSongs, current: row) } else { tracks(album, songs) }
                                }
                                .foregroundStyle(palette.ink)
                                .padding(.trailing, 6)
                            }
                            .scrollIndicators(.hidden)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                                         .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                        } else if tab == 1 {
                            if let targetSong = activeLyricSong {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 8) {
                                        Text("LYRICS").font(.mi(7.5)).tracking(1.5).foregroundStyle(palette.muted)
                                        Text(targetSong.title).font(.mi(11, .demibold)).foregroundStyle(palette.ink).lineLimit(1)
                                    }
                                    .padding(.top, 14)
                                    LyricsView(song: targetSong, compact: portrait)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                                .padding(.trailing, 6)
                            } else {
                                Text("暂无可显示歌词的曲目").font(.mi(12)).foregroundStyle(palette.muted).padding(.top, 28)
                            }
                        } else {
                            ScrollView {
                                AlbumAboutView(album: album, songs: song.map { [$0] } ?? songs)
                                    .padding(.trailing, 6)
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                    .transition(.opacity.animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)))
                }
                // Keep the playing row in view when the song changes (skip, shuffle, auto-advance).
                .onChange(of: model.player.current?.id, initial: true) { _, _ in
                    guard tab == 0, let index = playingRow(songs: songs, listSongs: listSongs, listMode: song != nil) else { return }
                    withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 2.0)) { proxy.scrollTo("row-\(index)", anchor: .center) }
                }
            }
            .padding(.leading, portrait ? 16 : size.width * 0.53)
            .padding(.trailing, portrait ? 16 : 20)
            .padding(.top, portrait ? size.height * 0.51 + 12 : 85)
            .padding(.bottom, 30)
            .background(alignment: .top) {
                if portrait {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: palette.pageBackground, location: 34 / (size.height * 0.54))],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.top, size.height * 0.46)
                        .ignoresSafeArea()
                }
            }
            // List modes keep the list's scroll position while the close-up moves between songs.
            .id(model.sortMode.usesGroups ? model.sortMode.rawValue : album.id)
        }
    }

    /// Row index of the playing song in the visible list (list position wins when a song repeats).
    private func playingRow(songs: [Song], listSongs: [Song], listMode: Bool) -> Int? {
        guard let current = model.player.current else { return nil }
        if listMode {
            if let key = model.playingKey, let index = model.listPosition(for: key)?.index,
               listSongs.indices.contains(index), listSongs[index].id == current.id { return index }
            return listSongs.firstIndex { $0.id == current.id }
        }
        return songs.firstIndex { $0.id == current.id }
    }

    /// Release year, artist, genre side by side in three equal columns, each a small label over its value.
    private func facts(_ album: Album, _ songs: [Song], song: Song?) -> some View {
        let fields: [(String, String)] = [
            ("RELEASE / 发行年份", (song?.year ?? album.year).map(String.init) ?? "未提供"),
            ("ARTIST / 歌手", song?.artist ?? album.artist ?? "未知歌手"),
            ("GENRE / 流派", song?.genre ?? album.genre ?? "未分类"),
        ]
        return HStack(spacing: 18) {
            ForEach(fields, id: \.0) { name, value in
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(.mi(7)).tracking(0.6).foregroundStyle(palette.muted).lineLimit(1)
                    Text(value).font(.mi(11)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 14).padding(.bottom, 10)
    }

    private func tabs() -> some View {
        HStack(spacing: portrait ? 14 : 20) {
            tabButton(0, "01", "歌单")
            tabButton(1, "02", "歌词")
            tabButton(2, "03", "介绍")
            Spacer()
            let player = model.player
            HStack(spacing: portrait ? 12 : 18) {
                modeToggle("随机", on: player.queue.shuffled) { player.setShuffle(!player.queue.shuffled) }
                modeToggle(["off": "循环", "all": "列表循环", "one": "单曲循环"][player.queue.repeatMode.rawValue] ?? "循环",
                           on: player.queue.repeatMode != .off) {
                    let all = PlayQueue.Repeat.allCases
                    player.setRepeat(all[(all.firstIndex(of: player.queue.repeatMode)! + 1) % all.count])
                }
                modeToggle("词", on: tab == 1) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) { tab = tab == 1 ? 0 : 1 }
                }
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
    }

    private func modeToggle(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.mi(11)).foregroundStyle(on ? palette.ink : palette.muted)
                .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private func tabButton(_ index: Int, _ number: String, _ label: String) -> some View {
        Button { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { tab = index } } label: {
            HStack(spacing: 6) { Text(number).font(.mi(8)); Text(label).font(.mi(portrait ? 10 : 11)) }
                .foregroundStyle(tab == index ? palette.ink : palette.muted)
                .padding(.top, 15).padding(.bottom, 11)
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) {
                    if tab == index {
                        Rectangle().fill(palette.ink).frame(height: 2).offset(y: 1)
                            .matchedGeometryEffect(id: "detail-tab-underline", in: tabUnderline)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    @ViewBuilder private func tracks(_ album: Album, _ songs: [Song]) -> some View {
        if songs.isEmpty {
            Text(model.details[album.id] == nil ? "正在读取曲目…" : "这个专辑还没有可播放曲目").font(.mi(11)).foregroundStyle(palette.muted).padding(.vertical, 25)
        } else {
            let discs = Set(songs.map { $0.discNumber ?? 1 }).count
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    if discs > 1, index == 0 || songs[index - 1].discNumber != song.discNumber {
                        Text("DISC \(String(format: "%02d", song.discNumber ?? 1))").font(.mi(8)).tracking(1.5).foregroundStyle(palette.muted)
                            .padding(.top, 20).padding(.bottom, 8)
                    }
                    let isCurrent = model.player.current?.id == song.id
                    TrackRow(song: song, number: song.track ?? index + 1, playing: isCurrent, isActivelyPlaying: isCurrent && model.player.isPlaying) {
                        if !isCurrent { model.play(album: album.id, from: index) }
                    }
                    .id("row-\(index)")
                    .contextMenu {
                        Button("下一首播放") { model.player.playNext([song]) }
                        Button("加入播放队列") { model.player.append([song]) }
                        Button(song.starred == nil ? "加入我喜欢" : "取消我喜欢") { model.toggleStar(song) }
                        Menu("加入歌单") {
                            ForEach(model.playlists) { list in Button(list.name) { model.add([song], to: list) } }
                        }
                    }
                }
            }
        }
    }
}

extension DetailView {
    /// Playlist / liked order with the inspected card's song marked; tapping plays the list from there.
    @ViewBuilder func listTracks(_ songs: [Song], current: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                let isCurrent = model.player.current?.id == song.id || (model.player.current == nil && index == current)
                TrackRow(song: song, number: index + 1, playing: isCurrent,
                         isActivelyPlaying: model.player.current?.id == song.id && model.player.isPlaying) {
                    // The playing row only brings its card up; it does not restart the song.
                    model.focusListSong(index)
                    if model.player.current?.id != song.id { model.player.play(songs, startAt: index) }
                }
                .id("row-\(index)")
                .contextMenu {
                    Button("下一首播放") { model.player.playNext([song]) }
                    Button("加入播放队列") { model.player.append([song]) }
                    Button(song.starred == nil ? "加入我喜欢" : "取消我喜欢") { model.toggleStar(song) }
                }
            }
        }
    }
}

struct TrackRow: View {
    let song: Song
    let number: Int
    let playing: Bool
    var isActivelyPlaying: Bool = true
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if playing {
                    PlayingBars(animated: isActivelyPlaying, color: palette.accent)
                        .frame(width: 23, height: 14, alignment: .leading)
                } else {
                    Text(String(format: "%02d", number)).font(.mi(9)).monospacedDigit().foregroundStyle(palette.muted).frame(width: 23, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.title).font(.mi(12, playing ? .demibold : .regular)).lineLimit(1)
                    Text(song.artist ?? "").font(.mi(10)).foregroundStyle(palette.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(song.suffix?.uppercased() ?? "").font(.mi(7)).foregroundStyle(palette.muted).frame(width: 40, alignment: .trailing)
                Text(clockText(song.duration ?? 0)).font(.mi(9)).monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .foregroundStyle(playing ? palette.accent : palette.ink)
            .padding(.leading, playing ? 8 : 0)
            .padding(.vertical, 11)
            .frame(minHeight: 48)
            .background(playing ? palette.accent.opacity(0.055) : .clear)
            .overlay(alignment: .leading) {
                if playing { Rectangle().fill(palette.accent).frame(width: 2) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(highlight: palette.veil))
        .hoverEffect(.highlight)
    }
}

/// Restrained 3-bar level indicator for the currently playing track row.
private struct PlayingBars: View {
    let animated: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                bar(height: animated ? 4 + 8 * abs(sin(t * 4.2)) : 3.5)
                bar(height: animated ? 4 + 9 * abs(sin(t * 5.6 + 1.1)) : 6.0)
                bar(height: animated ? 4 + 7 * abs(sin(t * 3.7 + 2.3)) : 4.5)
            }
            .frame(height: 13, alignment: .bottom)
        }
    }

    private func bar(height: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: 2.2, height: height)
    }
}

private struct RowPressStyle: ButtonStyle {
    let highlight: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? highlight.opacity(0.65) : .clear)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
