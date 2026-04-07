import SwiftUI

@main
struct FileSlicePeekApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
