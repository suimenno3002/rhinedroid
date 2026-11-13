import RhineKit
import SwiftUI

/// The full-width rule under the close-up title, doubling as the progress line; times sit under its ends.
struct DetailProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @State private var scrub: Double?

    var body: some View {
        let player = model.player
        let hasSong = player.current != nil
        VStack(spacing: 0) {
            ProgressRule(value: hasSong ? (scrub ?? player.currentTime) : 0, total: player.duration) { value, done in
                scrub = done ? nil : value
                if done { player.seek(to: value) }
            }
            .disabled(!hasSong)
            HStack {
                Text(clockText(Int(scrub ?? player.currentTime)))
                Spacer()
                Text(clockText(Int(player.duration)))
            }
            .font(.mi(9)).monospacedDigit().foregroundStyle(palette.muted)
            .opacity(hasSong ? 1 : 0)
            .padding(.top, -6)
        }
    }
}

/// 1 pt rule: played part in --accent, the rest --ink (it is the title's divider). 24 pt touch band.
private struct ProgressRule: View {
    let value: Double
    let total: Double
    let changed: (_ value: Double, _ done: Bool) -> Void
    @State private var dragging = false
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { g in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            let x = g.size.width * fraction
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.ink).frame(height: 1)
                Rectangle().fill(palette.accent).frame(width: x, height: dragging ? 2 : 1)
                Circle().fill(palette.accent).frame(width: 7, height: 7).offset(x: x - 3.5)
                    .opacity(dragging ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    dragging = true
                    changed(min(max(drag.location.x / max(g.size.width, 1), 0), 1) * total, false)
                }
                .onEnded { drag in
                    dragging = false
                    changed(min(max(drag.location.x / max(g.size.width, 1), 0), 1) * total, true)
                })
            .animation(.easeOut(duration: 0.16), value: dragging)
        }
        .frame(height: 24)
    }
}
