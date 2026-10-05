import AppKit

/// Menu-bar agent: no Dock icon (LSUIElement), started from Finder or Spotlight so macOS attributes
/// permissions to Murmur rather than to a terminal.
@main
enum MurmurMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
