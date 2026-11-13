import RhineKit
import SwiftUI

/// The 2D layer above the shelf (music-app.ts stage children).
struct MusicOverlay: View {
    let portrait: Bool
    let size: CGSize
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let browsing = model.mode == .archive && !model.overview
        let drawerAllowed = browsing && model.panel == nil
        ZStack {
            Group {
                // .music-browse-veil (music.css:561-569, 2483-2490).
                LinearGradient(stops: portrait ? [
                    .init(color: .clear, location: 0.40), .init(color: palette.veil, location: 0.62),
                    .init(color: palette.pageBackground, location: 0.86),
                ] : [
                    .init(color: .clear, location: 0.42), .init(color: palette.veil, location: 0.66),
                    .init(color: palette.pageBackground, location: 0.96),
                ], startPoint: portrait ? .top : .leading, endPoint: portrait ? .bottom : .trailing)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                AlbumCallout(portrait: portrait, size: size)
                ShelfNavigation(portrait: portrait)
            }
            .opacity(browsing ? 1 : 0)
            .allowsHitTesting(browsing)
            .animation(browsing ? .timingCurve(0.45, 0, 0.25, 1, duration: 0.72) : .timingCurve(0.4, 0, 1, 1, duration: 0.14), value: browsing)

            if model.mode == .detail {
                DetailView(portrait: portrait, size: size)
                    .transition(.opacity.animation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.72)))
            }
            if model.overview { OverviewLayer(portrait: portrait) }

            BottomLine(portrait: portrait)

            // Arrangements live in a drawer: swipe in from the left edge to show, tap outside or swipe back to hide.
            if drawerAllowed && model.arrangementsOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { model.setArrangements(false) }
                    .gesture(DragGesture(minimumDistance: 20).onEnded { if $0.translation.width < -40 { model.setArrangements(false) } })
                LinearGradient(stops: [
                    .init(color: palette.pageBackground.opacity(0.96), location: 0),
                    .init(color: palette.pageBackground.opacity(0.86), location: 0.6),
                    .init(color: palette.pageBackground.opacity(0), location: 1),
                ], startPoint: .leading, endPoint: .trailing)
                .frame(width: 320)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if drawerAllowed && !model.arrangementsOpen {
                Color.clear
                    .frame(width: 22)
                    .contentShape(Rectangle())
                    .onTapGesture { model.setArrangements(true) }
                    .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.width > 40 { model.setArrangements(true) } })
                    .overlay(alignment: .leading) {
                        // Faint handle hinting at the drawer.
                        Capsule().fill(palette.ink.opacity(0.18)).frame(width: 2, height: 36).padding(.leading, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .ignoresSafeArea()
            }

            TopBar(portrait: portrait)

            // Above the top bar so nothing in it can intercept the tap.
            if model.mode == .detail {
                Button { model.back() } label: {
                    Text("← 返回专辑架").font(.mi(11)).foregroundStyle(palette.ink)
                        .padding(.trailing, 40).frame(minHeight: 48).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, portrait ? 16 : 20).padding(.top, portrait ? 128 : 74)
            }
            PanelHost()
        }
        .animation(.default, value: model.panel)
        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3), value: model.arrangementsOpen)
    }
}

/// `.music-overview` chrome over the zoomed-out shelf: heading, return button, column stepper.
struct OverviewLayer: View {
    let portrait: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let layout = model.layout
        ZStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("COLLECTION / OVERVIEW").font(.mi(9)).tracking(1.5).foregroundStyle(palette.muted)
                Text(model.sortMode == .playlists ? "歌单 · \(model.arrangementName)" : "\(model.sortMode.name)浏览收藏").font(.mi(21))
                Text(layout.columnNames[safe: model.selectedLane] ?? "").font(.mi(12)).foregroundStyle(palette.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, portrait ? 16 : 20).padding(.top, portrait ? 134 : 76)

            Button { model.toggleOverview() } label: {
                HStack(spacing: 11) { IconView(icon: .chevronLeft, size: 16); Text("返回近景").font(.mi(12)) }
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 20).padding(.bottom, 30)

            HStack(spacing: 12) {
                Button("←") { model.stepLane(-1, inOverview: true) }.font(.mi(25)).frame(width: 48, height: 48)
                Button("进入") { model.enterFromOverview(model.selectedId) }.font(.mi(12)).frame(minHeight: 48)
                Button("→") { model.stepLane(1, inOverview: true) }.font(.mi(25)).frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20).padding(.bottom, 30)
        }
        .foregroundStyle(palette.ink)
        .transition(.opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.42)))
    }
}
