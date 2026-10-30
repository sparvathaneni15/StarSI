import SwiftUI

@main
struct StarSIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(appState)
        }
    }
}
