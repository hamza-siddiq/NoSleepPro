import AppKit

// NoSleep Pro is a pure AppKit menu-bar (accessory) app — no storyboard, no SwiftUI scene.
// The entry point is main-actor isolated so it can touch AppKit at startup.
@main
enum NoSleepProApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
