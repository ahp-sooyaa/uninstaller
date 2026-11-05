import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--scan"), args.count > flag + 1 {
            printScan(args[flag + 1])
        } else {
            UninstallerApp.main()
        }
    }

    /// Read-only: prints what would be listed for an app. Nothing is removed.
    private static func printScan(_ path: String) {
        do {
            let app = try Scanner.inspect(URL(fileURLWithPath: path))
            print("\(app.name)  \(app.bundleID)  team=\(app.teamID ?? "-")")
            print("ids: \(app.ids.joined(separator: ", "))")
            for item in Scanner.scan(app) {
                print("[\(item.selectedByDefault ? "x" : " ")] \(item.category): \(item.url.path)")
            }
        } catch {
            print("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct UninstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = UninstallModel()

    var body: some Scene {
        Window("Uninstaller", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 560, minHeight: 440)
                .onOpenURL { url in
                    guard url.scheme == "uninstaller-app",
                          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                          let path = items.first(where: { $0.name == "path" })?.value else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    model.load(URL(fileURLWithPath: path))
                }
        }
        .windowResizability(.contentMinSize)
    }
}
