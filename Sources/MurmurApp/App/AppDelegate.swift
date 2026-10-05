import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        let environment = AppEnvironment()
        self.environment = environment
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }
}
