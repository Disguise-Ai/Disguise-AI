import SwiftUI

@main
struct DisguiseAIApp: App {

    init() {
        // TEMPORARY: Force fresh start for testing - remove this later
        SharedDefaults.shared.clearAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
