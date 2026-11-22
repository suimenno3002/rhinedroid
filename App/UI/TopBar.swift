// Layout and styling from RhineDroid web/src/music.css, android.css, music-theme-switch.css,
// music-transport-title.css (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import RhineKit
import SwiftUI

/// `.music-header` + `#library-status` + `.music-view-toggle` (ui-spec.md §2).
struct TopBar: View {
    let portrait: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let hidden = model.overview
        ZStack(alignment: .topLeading) {
            if portrait {
                VStack(alignment: .leading, spacing: 12) {
                    brand
                    HStack(spacing: 4) {
                        buttons
                        Spacer(minLength: 0)
                        NowPlayingEntry(portrait: true)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    brand
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        buttons
                        NowPlayingEntry(portrait: false).fade(hidden)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
            status.offset(x: portrait ? 16 : 22, y: portrait ? 112 : 76)
            overviewToggle.offset(x: portrait ? 16 : 20, y: portrait ? 132 : 102)
            if model.arrangementsOpen {
                sortSwitcher.offset(x: portrait ? 16 : 20, y: portrait ? 184 : 154)
                    .transition(.opacity.combined(with: .offset(x: -16)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RhinePad").font(.mi(portrait ? 21 : 23, .bold)).tracking(1).foregroundStyle(palette.ink)
            if !portrait {
                (Text("MUSIC ARCHIVE") + Text(" ／ ").foregroundColor(palette.muted) + Text("NAVIDROME PLAYER"))
                    .font(.mi(8)).tracking(0.7).foregroundStyle(palette.ink).frame(height: 12)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var buttons: some View {
        let hidden = model.overview
        IconButton(icon: .folder) { model.panel = .library }.fade(hidden)
        IconButton(icon: .search) { model.panel = .search }.fade(hidden)
        // ↻ requests a rotation upstream; iPad rotates with the device, so it toggles playlists here.
        Button { model.panel = .playlists } label: {
            Text("↻").font(.mi(12)).foregroundStyle(palette.ink).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight).fade(hidden)
        IconButton(icon: .settings) { model.panel = .settings }.fade(hidden)
    }

    private var status: some View {
        let tracks = model.layout.albums.reduce(0) { $0 + ($1.songCount ?? 0) }
        let text = model.loading && model.layout.albums.isEmpty ? "正在读取 Navidrome…" : "Navidrome · \(tracks) 首"
        return HStack(spacing: 7) {
            Rectangle().fill(model.loading ? palette.accent : Color(red: 0x8c / 255, green: 0x9b / 255, blue: 0x7b / 255))
                .frame(width: 4, height: 4)
                .pulse(model.loading)
            Text(text).font(.mi(portrait ? 8 : 9)).tracking(0.3).foregroundStyle(model.theme == .night ? palette.ink : palette.muted)
        }
        .opacity(model.mode == .detail || model.overview ? 0 : 1)
        .allowsHitTesting(false)
    }

    /// Shelf arrangements listed directly down the left edge: catalogue orders, 我喜欢, then every
    /// playlist by name. The active one is ink with an accent mark; the rest are muted.
    private var sortSwitcher: some View {
        let catalogue: [SortMode] = [.genre, .artist, .album, .favorites]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(catalogue, id: \.self) { mode in
                arrangementRow(mode.name, active: model.sortMode == mode) { model.setSort(mode) }
            }
            if !model.playlists.isEmpty {
                Text("PLAYLISTS / 歌单").font(.mi(8)).tracking(1.5).foregroundStyle(palette.muted)
                    .padding(.top, 12).padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.playlists) { list in
                            arrangementRow(list.name, active: model.sortMode == .playlists && model.playlistId == list.id) {
                                model.setSort(.playlists, playlist: list.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: portrait ? 160 : 230)
                .fixedSize(horizontal: false, vertical: true)
            }
            if model.loading && model.sortMode.usesGroups {
                Text("同步中…").font(.mi(9)).foregroundStyle(palette.muted).padding(.top, 6)
            }
        }
        .frame(width: 180, alignment: .leading)
        .opacity(model.mode == .detail || model.overview ? 0 : 1)
        .offset(y: model.overview ? -6 : 0)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.36), value: model.overview)
        .allowsHitTesting(model.mode == .archive && !model.overview && !model.layout.albums.isEmpty)
    }

    private func arrangementRow(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle().fill(active ? palette.accent : .clear).frame(width: 4, height: 4)
                Text(label).font(.mi(12)).tracking(0.5).lineLimit(1)
            }
            .foregroundStyle(active ? palette.ink : palette.muted)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.26), value: active)
        }
        .buttonStyle(.plain)
    }

    private var overviewToggle: some View {
        Button { model.toggleOverview() } label: {
            HStack(spacing: 11) {
                IconView(icon: .grid, size: 16)
                Text("缩略图模式").font(.mi(12)).tracking(0.72)
            }
            .foregroundStyle(palette.ink)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(model.layout.albums.isEmpty)
        .opacity(model.mode == .detail ? 0 : model.overview ? 0 : model.layout.albums.isEmpty ? 0.38 : 1)
        .offset(y: model.overview ? -6 : 0)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.36), value: model.overview)
        .allowsHitTesting(model.mode == .archive && !model.overview)
    }
}

struct IconButton: View {
    let icon: Icon
    var size: CGFloat = 17
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: size).foregroundStyle(palette.ink).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

/// `.theme-switch`: two 暖昼 / 深夜 buttons over an ink pill sliding 380 ms cubic-bezier(0.22, 1, 0.36, 1).
struct ThemeSwitch: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let night = model.theme == .night
        HStack(spacing: 4) {
            option("暖昼", dot: Color(red: 0xe9 / 255, green: 0xc4 / 255, blue: 0x92 / 255), active: !night)
            option("深夜", dot: Color(red: 0x41 / 255, green: 0x55 / 255, blue: 0x77 / 255), active: night)
        }
        .padding(3)
        .background(alignment: .leading) {
            GeometryReader { g in
                let w = (g.size.width - 10) / 2
                RoundedRectangle(cornerRadius: 5).fill(palette.ink)
                    .frame(width: w, height: g.size.height - 6)
                    .offset(x: 3 + (night ? w + 4 : 0), y: 3)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: night)
            }
        }
        .frame(height: 48)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.line))
        .fixedSize()
    }

    private func option(_ label: String, dot: Color, active: Bool) -> some View {
        Button { if !active { model.toggleTheme() } } label: {
            HStack(spacing: 5) {
                Rectangle().fill(dot).frame(width: 7, height: 7)
                    .overlay(Rectangle().stroke(Color.gray.opacity(0.35), lineWidth: 1).padding(-0.5))
                Text(label).font(.mi(11))
            }
            .foregroundStyle(active ? palette.surface : palette.ink)
            .opacity(active ? 1 : 0.6)
            .padding(8)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.26), value: active)
        }
        .buttonStyle(.plain)
    }
}

/// Text-only now-playing entry: frameless prev / play-pause / next glyphs.
struct NowPlayingEntry: View {
    let portrait: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let player = model.player
        let hasSong = player.current != nil
        HStack(spacing: 0) {
            control(.previous) { model.skipTrack(-1) }
            Button { player.toggle() } label: {
                ZStack {
                    IconView(icon: .play)
                        .opacity(player.isPlaying ? 0 : 1)
                        .scaleEffect(player.isPlaying ? 0.7 : 1)
                    IconView(icon: .pause)
                        .opacity(player.isPlaying ? 1 : 0)
                        .scaleEffect(player.isPlaying ? 1 : 0.7)
                }
                .foregroundStyle(player.isPlaying ? palette.accent : palette.ink)
                .animation(.easeInOut(duration: 0.18), value: player.isPlaying)
                .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            control(.next) { model.skipTrack(1) }
        }
        .disabled(!hasSong)
        .opacity(hasSong ? 1 : 0.38)
    }

    private func control(_ icon: Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon: icon).foregroundStyle(palette.ink).frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }
}

extension View {
    /// The overview hides top-bar controls: opacity 0 and 6 pt up (280 ms ease / 360 ms curve).
    func fade(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .offset(y: hidden ? -6 : 0)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.36), value: hidden)
            .allowsHitTesting(!hidden)
    }

    func pulse(_ active: Bool) -> some View { modifier(Pulse(active: active)) }

    /// android.css paper glass (minimal transport, now-playing card).
    func glass(radius: CGFloat, border: Bool = true) -> some View { modifier(Glass(radius: radius, border: border)) }
}

private struct Pulse: ViewModifier {
    let active: Bool
    @State private var dim = false
    func body(content: Content) -> some View {
        content.opacity(active && dim ? 0.25 : 1)
            .onChange(of: active, initial: true) { _, on in
                if on { withAnimation(.easeInOut(duration: 0.65).repeatForever()) { dim = true } } else { dim = false }
            }
    }
}

struct Glass: ViewModifier {
    let radius: CGFloat
    let border: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let n = palette.night
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                ZStack {
                    shape.fill(palette.pageBackground.opacity(0.94))
                    shape.fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.27 * (1 - n) + 0.08 * n), location: 0),
                        .init(color: .white.opacity(0.03 * (1 - n) + 0.01 * n), location: 0.38 * (1 - n) + 0.44 * n),
                        .init(color: .white.opacity(0.09 * (1 - n) + 0.02 * n), location: 0.75),
                        .init(color: .white.opacity(0.22 * (1 - n) + 0.03 * n), location: 1),
                    ], startPoint: UnitPoint(x: 0.21, y: 0), endPoint: UnitPoint(x: 0.79, y: 1)))
                    // inset 0 1px 0 (top highlight) and inset 0 -1px 0 (bottom)
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.77 * (1 - n) + 0.38 * n), .clear, .white.opacity(0.21 * (1 - n) + 0.08 * n)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .padding(border ? 1 : 0)
                }
                .shadow(color: .black.opacity(0.086 * (1 - n) + 0.33 * n), radius: 14 + n, y: 10 + 2 * n)
            }
            .overlay {
                if border { shape.stroke(Color.white.opacity(0.66 * (1 - n) + 0.31 * n).blend(palette.line), lineWidth: 1) }
            }
    }
}

private extension Color {
    /// color-mix(in srgb, line 50%, white-ish 50%) approximation.
    func blend(_ other: Color) -> Color { self.mix(with: other, by: 0.5) }
}
