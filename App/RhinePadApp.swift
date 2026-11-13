import SwiftUI

@main
struct RhinePadApp: App {
    @State private var model: AppModel

    init() {
        Fonts.register()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}
