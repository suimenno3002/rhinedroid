// Panel styling from RhineDroid web/src/music.css + android.css (.music-panel*, .settings-row, .album-result)
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import RhineKit
import SwiftUI
import UIKit

/// `.music-panel-scrim` + `.music-panel`, shown with the SurfaceTransition curve (300 ms in / 200 ms out).
struct PanelHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        if let panel = model.panel {
            let n = palette.night
            ZStack {
                Color(.sRGB, red: 4 / 255, green: 12 / 255, blue: 22 / 255, opacity: 0.24 * (1 - n) + 0.56 * n)
                    .background(.ultraThinMaterial.opacity(0.55 * (1 - n) + 0.18 * n))
                    .ignoresSafeArea()
                    .onTapGesture { model.panel = nil }
                VStack(alignment: .leading, spacing: 0) {
                    switch panel {
                    case .search: SearchPanel()
                    case .settings: SettingsPanel()
                    case .library: LibraryPanel()
                    case .playlists: PlaylistsPanel()
                    }
                }
                .foregroundStyle(palette.ink)
                .padding(.vertical, 18).padding(.horizontal, 22)
                .frame(maxWidth: 620, maxHeight: .infinity, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .background(palette.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                .shadow(color: .black.opacity(0.13), radius: 45, y: 24)
                .padding(12)
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)).animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)),
                removal: .opacity.combined(with: .offset(y: 10)).animation(.timingCurve(0.4, 0, 1, 1, duration: 0.2))))
        }
    }
}

struct PanelHeading: View {
    let kicker: String
    let title: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(kicker).font(.mi(9)).tracking(2).foregroundStyle(palette.muted)
                Text(title).font(.mi(21))
            }
            Spacer()
            Button { model.panel = nil } label: {
                Text("×").font(.mi(29)).foregroundStyle(palette.muted).frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
        .padding(.bottom, 14)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.mi(12)).padding(.bottom, 11)
            content
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder let control: Control
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.mi(12))
                if let help { Text(help).font(.mi(10)).foregroundStyle(palette.muted) }
            }
            Spacer(minLength: 16)
            control
        }
        .frame(minHeight: 48)
    }
}

/// Square ink toggle in the panel language (no system green).
struct InkToggle: View {
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5).fill(isOn ? palette.ink : palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.line))
                RoundedRectangle(cornerRadius: 3).fill(isOn ? palette.surface : palette.ink.opacity(0.5)).frame(width: 16, height: 16).padding(4)
            }
            .frame(width: 44, height: 24)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38), value: isOn)
            .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ChipPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            ForEach(options, id: \.0) { value, label in
                Button { selection = value } label: {
                    Text(label).font(.mi(10)).padding(.horizontal, 10).frame(minHeight: 32)
                        .foregroundStyle(selection == value ? palette.surface : palette.ink)
                        .background(selection == value ? palette.ink : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: Settings

struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var model = model
        let player = model.player
        let nativeSize = UIScreen.main.nativeBounds.size
        let resText = "\(Int(max(nativeSize.width, nativeSize.height)))×\(Int(min(nativeSize.width, nativeSize.height)))"
        PanelHeading(kicker: "PREFERENCES / 设置", title: "界面与播放")
        ScrollView {
            VStack(spacing: 0) {
                PanelSection(title: "外观") {
                    SettingsRow(label: "主题", help: "暖昼 / 深夜，650 ms 渐变切换（快捷键 ⌘T）") { ThemeSwitch() }
                }
                PanelSection(title: "三维档案") {
                    SettingsRow(label: "景深", help: "焦点外的专辑轻微虚化") { InkToggle(isOn: $model.focusDepth) }
                    SettingsRow(label: "解密扫描", help: "打开专辑时封面先模糊、对角扫描后清晰（上游效果）") { InkToggle(isOn: $model.decryption) }
                    SettingsRow(label: "静置浮动", help: "停止操作 2.5 秒后专辑架缓慢起伏") { InkToggle(isOn: $model.idleMotion) }
                    SettingsRow(label: "开场动画", help: "每次连接音乐库时播放") { InkToggle(isOn: $model.playIntro) }
                    SettingsRow(label: "渲染精度", help: "原生 = \(resText) 满分辨率") {
                        ChipPicker(options: [(0.6, "省电"), (0.8, "均衡"), (1.0, "原生")], selection: $model.renderScale)
                    }
                    SettingsRow(label: "动效速度") {
                        ChipPicker(options: [(0.5, "0.5×"), (1.0, "1×"), (1.5, "1.5×"), (2.0, "2×")], selection: $model.motionSpeed)
                    }
                }
                PanelSection(title: "播放") {
                    SettingsRow(label: "切歌方式") {
                        ChipPicker(options: [(PlaybackEngine.Transition.fadeOut, "淡出"), (.fadeInOut, "淡入淡出"), (.gapless, "无缝")],
                                   selection: Binding(get: { player.transition }, set: { player.setTransition($0) }))
                    }
                    SettingsRow(label: "背景音乐", help: "未播放歌曲时在专辑架播放上游 Observatory 片段") {
                        InkToggle(isOn: Binding(get: { player.bgmEnabled }, set: { player.setBackground(enabled: $0) }))
                    }
                }
                PanelSection(title: "Navidrome") {
                    SettingsRow(label: model.serverURL.isEmpty ? "开发会话" : model.serverURL, help: model.username) {
                        Button("退出登录") { model.panel = nil; model.signOut() }.font(.mi(11)).foregroundStyle(palette.accent).buttonStyle(.plain)
                    }
                    SettingsRow(label: "重新同步音乐库") {
                        Button(model.loading ? "同步中…" : "同步 ↻") { Task { await model.refresh() } }.font(.mi(11)).buttonStyle(.plain)
                    }
                }
                PanelSection(title: "关于") {
                    Text("RhinePad 0.2.0 · 移植自 RhineDroid 0.4.8（MIT，© 2026 LBEILC，© 2026 RonaldDeng）。支持外接键盘快捷键：空格播放/暂停、方向键浏览、Enter 打开、Esc 返回、⌘F 搜索、⌘T 切主题。")
                        .font(.mi(11)).lineSpacing(9).foregroundStyle(palette.muted)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 640)
    }
}

// MARK: Search

struct SearchPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var result = SearchResult()
    @FocusState private var focused: Bool

    var body: some View {
        PanelHeading(kicker: "SEARCH / 搜索", title: "检索专辑与歌曲")
        TextField("", text: $query, prompt: Text("专辑、歌手或歌曲").foregroundColor(palette.muted))
            .font(.mi(12)).focused($focused)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
            .onAppear { focused = true }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !query.isEmpty, let client = model.client else { result = SearchResult(); return }
                result = (try? await client.search(query)) ?? SearchResult()
            }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(result.album ?? []) { album in
                    ResultRow(cover: album.coverArt, title: album.name, subtitle: "\(album.artist ?? "") · \(album.year.map(String.init) ?? "")", trailing: "专辑") {
                        model.panel = nil
                        if !model.selectAlbum(album.id) { model.setSort(.genre); Task { try? await Task.sleep(for: .milliseconds(300)); model.selectAlbum(album.id) } }
                    }
                }
                ForEach(result.song ?? []) { song in
                    ResultRow(cover: song.coverArt, title: song.title, subtitle: "\(song.artist ?? "") · \(song.album ?? "")", trailing: clockText(song.duration ?? 0)) {
                        model.player.play([song])
                    }
                    .contextMenu {
                        Button("下一首播放") { model.player.playNext([song]) }
                        Button("加入播放队列") { model.player.append([song]) }
                        Button(song.starred == nil ? "加入我喜欢" : "取消我喜欢") { model.toggleStar(song) }
                        if let album = song.albumId { Button("定位专辑") { model.panel = nil; model.selectAlbum(album) } }
                    }
                }
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 520)
    }
}

struct ResultRow: View {
    let cover: String?
    let title: String
    let subtitle: String
    let trailing: String
    let action: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack { palette.surface; if let image { Image(uiImage: image).resizable().scaledToFill() } }
                    .frame(width: 49, height: 49).clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mi(12)).lineLimit(1)
                    Text(subtitle).font(.mi(10)).foregroundStyle(palette.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(trailing).font(.mi(10)).foregroundStyle(palette.muted)
                Text("↗").font(.mi(17))
            }
            .padding(.vertical, 8).frame(minHeight: 64)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .task(id: cover) {
            guard let data = await CoverLoader.fetch(cover: cover, size: 128, client: model.client),
                  let cg = CoverArt.thumbnail(data, maxPixel: 128) else { return }
            image = UIImage(cgImage: cg)
        }
    }
}

// MARK: Library

struct LibraryPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let layout = model.layout
        PanelHeading(kicker: "LIBRARY / 音乐库", title: "Navidrome 音乐库")
        Text("\(layout.albums.count) 张专辑 · \(layout.columns.count) 个\(model.sortMode.column) · 点击列名跳转")
            .font(.mi(12)).foregroundStyle(palette.muted).padding(.bottom, 12)
        if let error = model.libraryError { Text(error).font(.mi(11)).foregroundStyle(palette.accent).padding(.bottom, 8) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(layout.columnNames.enumerated()), id: \.offset) { lane, name in
                    Button {
                        model.panel = nil
                        if let first = layout.columns[lane].first { model.select(first, immediate: true) }
                    } label: {
                        HStack {
                            Text(String(format: "%02d", lane + 1)).font(.mi(9)).foregroundStyle(palette.muted).frame(width: 28, alignment: .leading)
                            Text(name).font(.mi(12))
                            Spacer()
                            Text("\(layout.columns[lane].count) 张").font(.mi(10)).foregroundStyle(palette.muted)
                        }
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
                        .foregroundStyle(lane == model.selectedLane ? palette.accent : palette.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 520)
    }
}

// MARK: Playlists (not in upstream)

struct PlaylistsPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var open: Playlist?
    @State private var newName = ""

    var body: some View {
        if let open {
            PlaylistDetail(playlist: open) { self.open = nil }
        } else {
            PanelHeading(kicker: "PLAYLISTS / 歌单", title: "Navidrome 歌单")
            HStack(spacing: 10) {
                TextField("", text: $newName, prompt: Text("新歌单名称").foregroundColor(palette.muted))
                    .font(.mi(12)).padding(.horizontal, 13).padding(.vertical, 10)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.line))
                Button("新建 ↗") { model.createPlaylist(newName); newName = "" }
                    .font(.mi(11)).foregroundStyle(palette.accent).buttonStyle(.plain).disabled(newName.isEmpty)
            }
            .padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.playlists) { list in
                        ResultRow(cover: list.coverArt, title: list.name,
                                  subtitle: "\(list.songCount ?? 0) 首 · \(clockText(list.duration ?? 0))", trailing: "") { open = list }
                            .contextMenu {
                                Button("播放") { model.play(playlist: list) }
                                Button("删除歌单", role: .destructive) { model.deletePlaylist(list) }
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
            .task { await model.reloadPlaylists() }
        }
    }
}

struct PlaylistDetail: View {
    let playlist: Playlist
    let back: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var songs: [Song] = []

    var body: some View {
        HStack(alignment: .top) {
            Button("← 全部歌单", action: back).font(.mi(11)).buttonStyle(.plain).frame(minHeight: 48)
            Spacer()
            Button { model.play(playlist: playlist) } label: {
                HStack(spacing: 3) { IconView(icon: .play, size: 13); Text("播放全部").font(.mi(9)) }.frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        Text(playlist.name).font(.mi(21)).padding(.bottom, 12)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    let isCurrent = model.player.current?.id == song.id
                    TrackRow(song: song, number: index + 1, playing: isCurrent, isActivelyPlaying: isCurrent && model.player.isPlaying) {
                        model.player.play(songs, startAt: index)
                    }
                    .contextMenu {
                        Button("从歌单移除", role: .destructive) {
                            Task {
                                try? await model.client?.updatePlaylist(id: playlist.id, removeIndexes: [index])
                                await load()
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 480)
        .task { await load() }
    }

    private func load() async {
        songs = (try? await model.client?.playlist(id: playlist.id))?.entry ?? []
    }
}
