// Layout from RhineDroid web/src/music.css + android.css (.album-callout, .music-navigation, .music-bottomline)
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import RhineKit
import SwiftUI

func clockText(_ seconds: Int) -> String {
    let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// `.album-callout`: landscape left 64 % / right 20 / top 29 %; portrait left/right 16, bottom 164.
struct AlbumCallout: View {
    let portrait: Bool
    let size: CGSize
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if let album = model.selected {
            let layout = model.layout
            let lane = model.selectedLane
            let detail = model.details[album.id]
            let formats = Set((detail?.song ?? []).compactMap { $0.suffix?.uppercased() }).sorted().joined(separator: " / ")
            let meta = [album.year.map(String.init) ?? "年份未提供",
                        album.songCount.map { "\($0) 首曲目" } ?? "",
                        album.duration.map(clockText) ?? ""].filter { !$0.isEmpty }.joined(separator: "  /  ")
            let titleSize = portrait ? min(36, max(24, size.width * 0.07)) : min(38, max(23, size.width * 0.034))
            // List modes: one card per song, so the song leads and the album becomes context.
            let song = model.selectedSong
            let position = model.listPosition(for: model.selectedId)
            let code = position.map { "TRACK \(String(format: "%02d", $0.index + 1)) / \(String(format: "%02d", $0.total))" }
                ?? "ALBUM \(String(format: "%03d", (layout.ordinal(model.selectedId) ?? 0) + 1))"
            let heading = song?.title ?? album.name
            let subtitle = song.map { "\($0.artist ?? "未知歌手")  ·  \(album.name)" } ?? (album.artist ?? "未知歌手")
            let info = song.map { [$0.suffix?.uppercased() ?? "", clockText($0.duration ?? 0), album.year.map(String.init) ?? ""]
                .filter { !$0.isEmpty }.joined(separator: "  /  ") } ?? meta

            VStack(alignment: .leading, spacing: 0) {
                // Far view: the way back to the playing card sits at the right of the first line (overlay,
                // so the callout keeps its height).
                let playing = model.player.current.flatMap { s in model.playingKey.flatMap { $0 != model.selectedId ? s : nil } }
                (Text("MUSIC ARCHIVE ") + Text("／").foregroundColor(palette.ink) + Text(" \(layout.columnNames[safe: lane] ?? "")"))
                    .font(.mi(9)).tracking(1.5).lineLimit(1)
                    .padding(.trailing, playing == nil ? 0 : 176)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 15.3)
                    .overlay(alignment: .trailing) {
                        if let playing {
                            Button { model.jumpToPlaying() } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(palette.accent).frame(width: 5, height: 5)
                                    Text("正在播放 · \(playing.title)").lineLimit(1)
                                }
                                .font(.mi(10)).foregroundStyle(palette.ink)
                                .frame(maxWidth: 168, alignment: .trailing)
                                .frame(height: 32).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: playing?.id)
                HStack {
                    Text(code).font(.mi(10)).tracking(1)
                        .contentTransition(.numericText())
                    Spacer(minLength: 16)
                    Text(song == nil ? formats : "").font(.mi(9)).tracking(1).foregroundStyle(palette.muted)
                }
                .padding(.top, 15).padding(.bottom, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: 1) }
                .padding(.bottom, 17)
                Text(heading)
                    .font(.mi(titleSize, .bold)).tracking(-0.6)
                    .lineSpacing(titleSize * 0.4 - 4)
                    .lineLimit(2)
                    .padding(.top, 12 - 17).padding(.bottom, 8)
                    .id(model.selectedId)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                Text(subtitle).font(.mi(12, .demibold)).lineLimit(1).padding(.bottom, 10)
                Text(info).font(.mi(10)).tracking(0.5).foregroundStyle(palette.muted)
                Button { model.open() } label: {
                    HStack {
                        Text(song == nil ? "打开专辑" : "打开\(model.sortMode == .favorites ? "我喜欢" : "歌单")").font(.mi(13))
                        Spacer()
                        Text("↗").font(.mi(24))
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .foregroundStyle(palette.ink)
            .animation(.easeOut(duration: 0.46), value: model.selectedId)
            .frame(maxWidth: portrait ? .infinity : min(520, size.width * 0.36 - 20), alignment: .leading)
            // The whole info block opens the close-up of this card.
            .contentShape(Rectangle())
            .onTapGesture { model.open() }
            .padding(.leading, portrait ? 16 : size.width * 0.64)
            .padding(.trailing, portrait ? 16 : 0)
            .padding(.top, portrait ? 0 : size.height * 0.29)
            .padding(.bottom, portrait ? 164 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: portrait ? .bottomLeading : .topLeading)
        }
    }
}

/// `.music-navigation`: counter, album stepper with the 12-slot tick ruler, column stepper.
struct ShelfNavigation: View {
    let portrait: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let layout = model.layout
        let lane = model.selectedLane
        let column = layout.columns[safe: lane] ?? []
        let row = layout.row(of: model.selectedId) ?? 0
        let code = model.sortMode.code

        let counter = VStack(alignment: .leading, spacing: 6) {
            Text(model.sortMode.usesGroups ? "TRACK / SELECT" : "ALBUM / SELECT").font(.mi(8)).tracking(1.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", row + 1)).font(.mi(34, .light)).tracking(-3).contentTransition(.numericText())
                (Text("/") + Text(String(format: " %02d", column.count)).tracking(1))
                    .font(.mi(12, .light)).foregroundStyle(palette.muted)
            }
        }
        let stepper = HStack(spacing: portrait ? 0 : 6) {
            arrow("↑") { model.navigate(axis: "row", direction: -1) }
            TickRuler(count: column.count, selected: row)
            arrow("↓") { model.navigate(axis: "row", direction: 1) }
        }
        let columns = HStack(spacing: 4) {
            arrow("←") { model.stepLane(-1) }
            if portrait { Spacer(minLength: 0) }
            VStack(spacing: 5) {
                Text("\(code) \(String(format: "%02d", lane + 1)) / \(String(format: "%02d", layout.columns.count))")
                    .font(.mi(8)).tracking(1.3).foregroundStyle(palette.muted)
                Button { model.toggleOverview() } label: {
                    Text(layout.columnNames[safe: lane] ?? "").font(.mi(14)).tracking(1).lineLimit(1)
                        .padding(4).frame(minHeight: 40)
                }
                .buttonStyle(.plain)
            }
            .frame(minWidth: portrait ? 78 : 0)
            if portrait { Spacer(minLength: 0) }
            arrow("→") { model.stepLane(1) }
        }

        Group {
            if portrait {
                VStack(spacing: 4) { stepper.frame(maxWidth: .infinity); columns }
                    .padding(.horizontal, 12).padding(.bottom, 36)
            } else {
                GeometryReader { g in
                    // grid-template-columns: minmax(74px, .55fr) 1fr 1fr, gap 14.
                    let total = g.size.width - 28, unit = total / 2.55
                    HStack(spacing: 14) {
                        counter.frame(width: max(74, unit * 0.55), alignment: .leading)
                        stepper.frame(width: unit)
                        columns.frame(width: unit)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 80)
                .padding(.leading, 20).padding(.trailing, 74).padding(.bottom, 35)
            }
        }
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.3), value: model.selectedId)
    }

    private func arrow(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.mi(25)).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// `#album-ticks`: 12 slots, 3×10 pt marks at 25 % ink, the selected one 30 pt tall at full ink (0.4 s).
/// The window recentres only when the selection leaves it (music-ticks.ts:84-86).
struct TickRuler: View {
    let count: Int
    let selected: Int
    @State private var windowStart = 0
    @Environment(\.palette) private var palette
    private let slots = 12

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<min(slots, count), id: \.self) { slot in
                let active = windowStart + slot == selected
                Rectangle().fill(palette.ink)
                    .frame(width: 3, height: active ? 30 : 10)
                    .opacity(active ? 1 : 0.25)
                    .frame(height: 30)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: selected)
        .onChange(of: selected, initial: true) { _, value in recentre(value) }
        .onChange(of: count) { _, _ in recentre(selected, force: true) }
    }

    private func recentre(_ value: Int, force: Bool = false) {
        if force || value < windowStart || value >= windowStart + slots {
            windowStart = max(0, min(value - 5, count - slots))
        }
    }
}

/// `.music-bottomline`.
struct BottomLine: View {
    let portrait: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let albums = model.layout.albums
        let tracks = albums.reduce(0) { $0 + ($1.songCount ?? 0) }
        HStack {
            (Text("NAVIDROME COLLECTION") + Text("  ·  ") + Text("\(albums.count) ALBUMS / \(tracks) TRACKS"))
            Spacer()
            if !portrait {
                Text("METAL · GPU INSTANCING / \(model.theme == .night ? "深夜" : "暖昼") / V0.1.0")
            }
        }
        .font(.mi(portrait ? 7 : 8)).tracking(1.1).foregroundStyle(palette.muted)
        .padding(.horizontal, portrait ? 12 : 20).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
