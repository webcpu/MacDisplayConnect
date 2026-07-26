import SwiftUI

@main
struct MacDisplayConnectVisionApp: App {
    @State private var model = VisionConnectionModel()

    var body: some Scene {
        WindowGroup {
            VisionConnectionView(model: model)
        }
        .defaultSize(width: 560, height: 460)
    }
}
