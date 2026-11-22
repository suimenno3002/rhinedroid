import RhineKit
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var night: Double = 0
    @State private var ambientTint: Color?

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.width < geometry.size.height * 1.05
            ZStack {
                Palette(night: night).pageBackground.ignoresSafeArea()
                if let shelf = model.shelf {
                    ShelfView(controller: shelf).ignoresSafeArea()
                } else {
                    Text("无法创建 Metal 渲染器").font(.mi(15)).foregroundStyle(Palette(night: night).muted)
                }
                Vignette(night: night, detail: model.mode == .detail, portrait: portrait, ambientTint: ambientTint)
                    .ignoresSafeArea()
                    .animation(Palette.themeAnimation, value: model.mode)
                if model.signedIn {
                    MusicOverlay(portrait: portrait, size: geometry.size)
                        .opacity(model.booting ? 0 : 1)
                        .allowsHitTesting(!model.booting)
                    if model.booting {
                        BootView(portrait: portrait, size: geometry.size).transition(.opacity)
                    }
                    keyboardShortcuts
                } else {
                    LoginView()
                }
            }
            .environment(\.palette, Palette(night: night))
        }
        // Upstream lays out against the whole immersive viewport; keep only keyboard avoidance.
        .ignoresSafeArea(.container)
        .onAppear {
            night = model.theme == .night ? 1 : 0
            #if DEBUG
            // Simulator screenshots: SIMCTL_CHILD_RHINE_ORIENTATION=landscape|portrait.
            if let value = ProcessInfo.processInfo.environment["RHINE_ORIENTATION"],
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: value == "portrait" ? .portrait : .landscapeRight))
            }
            #endif
        }
        .onChange(of: model.theme) { _, theme in
            withAnimation(Palette.themeAnimation) { night = theme == .night ? 1 : 0 }
        }
        .onChange(of: model.mode) { _, _ in model.player.setForeground(model.mode == .archive) }
        .task(id: model.selected?.coverArt ?? model.selected?.id ?? "") {
            guard let album = model.selected else { ambientTint = nil; return }
            let coverKey = album.coverArt ?? album.id
            if let cached = CoverTintExtractor.cached(coverKey) {
                ambientTint = cached
                return
            }
            guard let data = await CoverLoader.fetch(cover: album.coverArt, size: 128, client: model.client) else { return }
            let tint = await Task.detached(priority: .utility) { CoverTintExtractor.extract(from: data) }.value
            if let tint {
                CoverTintExtractor.store(tint, for: coverKey)
                ambientTint = tint
            }
        }
    }

    /// iPad hardware keyboard shortcuts (Space, arrows, Return, Esc, ⌘F, ⌘T).
    /// Single-key shortcuts yield whenever a modal panel with text input is open.
    @ViewBuilder
    private var keyboardShortcuts: some View {
        if !model.booting {
            ZStack {
                Button("") {
                    if model.panel != nil { model.panel = nil }
                    else if model.arrangementsOpen { model.setArrangements(false) }
                    else if model.overview { model.toggleOverview() }
                    else if model.mode == .detail { model.back() }
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("") { model.panel = model.panel == .search ? nil : .search }
                    .keyboardShortcut("f", modifiers: .command)

                Button("") { model.toggleTheme() }
                    .keyboardShortcut("t", modifiers: .command)

                if model.panel == nil {
                    Button("") { model.player.toggle() }
                        .keyboardShortcut(.space, modifiers: [])
                    Button("") {
                        if model.mode == .detail { model.navigateDetail(-1) }
                        else { model.navigate(axis: "row", direction: -1) }
                    }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    Button("") {
                        if model.mode == .detail { model.navigateDetail(1) }
                        else { model.navigate(axis: "row", direction: 1) }
                    }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    Button("") {
                        if model.mode == .detail { model.navigateDetail(-1) }
                        else { model.stepLane(-1, inOverview: model.overview) }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("") {
                        if model.mode == .detail { model.navigateDetail(1) }
                        else { model.stepLane(1, inOverview: model.overview) }
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    Button("") {
                        if model.overview { model.enterFromOverview(model.selectedId) }
                        else if model.mode == .archive { model.open() }
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
