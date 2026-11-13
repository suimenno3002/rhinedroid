import RhineKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var night: Double = 0

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
                Vignette(night: night, detail: model.mode == .detail, portrait: portrait)
                    .ignoresSafeArea()
                    .animation(Palette.themeAnimation, value: model.mode)
                if model.signedIn {
                    MusicOverlay(portrait: portrait, size: geometry.size)
                        .opacity(model.booting ? 0 : 1)
                        .allowsHitTesting(!model.booting)
                    if model.booting {
                        BootView(portrait: portrait, size: geometry.size).transition(.opacity)
                    }
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
    }
}
