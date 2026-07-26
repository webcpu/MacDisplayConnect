import SwiftUI

@main
struct MacDisplayConnectApp: App {
    @State private var model = ConnectionModel()

    var body: some Scene {
        WindowGroup("Mac Display Connect") {
            ConnectionView(model: model)
        }
        .defaultSize(width: 420, height: 330)
        .windowResizability(.contentSize)
    }
}
