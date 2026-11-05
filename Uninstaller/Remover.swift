import AppKit

struct RemovalFailure: Identifiable {
    var id: URL { url }
    let url: URL
    let reason: String
}

enum RemovalError: LocalizedError {
    case stillRunning(String)
    var errorDescription: String? {
        if case .stillRunning(let name) = self { return "\(name) didn't quit. Quit it and try again." }
        return nil
    }
}

/// Everything goes to the Trash, so a removal can always be undone.
enum Remover {
    static func isRunning(_ app: AppInfo) -> Bool { !running(app).isEmpty }

    private static func running(_ app: AppInfo) -> [NSRunningApplication] {
        app.ids.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { !$0.isTerminated }
    }

    static func quit(_ app: AppInfo) async throws {
        running(app).forEach { $0.terminate() }
        for _ in 0..<50 where isRunning(app) {
            try await Task.sleep(for: .milliseconds(100))
        }
        if isRunning(app) { throw RemovalError.stillRunning(app.name) }
    }

    static func remove(_ items: [Leftover]) -> [RemovalFailure] {
        // The app goes first: if it can't be removed, its data should stay with it.
        let ordered = items.sorted { $0.match == .app && $1.match != .app }
        var failures: [RemovalFailure] = []
        var needsAdmin: [Leftover] = []

        for item in ordered {
            stopIfBackgroundItem(item)
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            } catch {
                if item.needsAdmin {
                    needsAdmin.append(item)
                } else {
                    failures.append(RemovalFailure(url: item.url, reason: error.localizedDescription))
                }
            }
            if item.match == .app, !failures.isEmpty { return failures }
        }

        if !needsAdmin.isEmpty { failures += removeAsAdmin(needsAdmin) }
        return failures
    }

    private static func stopIfBackgroundItem(_ item: Leftover) {
        guard item.url.pathExtension == "plist",
              item.url.deletingLastPathComponent().lastPathComponent == "LaunchAgents",
              !item.needsAdmin else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(getuid())", item.url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// One password prompt for every root-owned item.
    private static func removeAsAdmin(_ items: [Leftover]) -> [RemovalFailure] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let stamp = Int(Date().timeIntervalSince1970)
        let commands = items.map { item -> String in
            let path = item.url.path
            let destination = trash.appendingPathComponent("\(stamp)-\(item.url.lastPathComponent)").path
            var command = "/bin/mv \(shellQuote(path)) \(shellQuote(destination))"
            if path.hasPrefix("/Library/LaunchDaemons/") {
                command = "/bin/launchctl bootout system \(shellQuote(path)); " + command
            }
            return command
        }
        let shell = commands.joined(separator: "; ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?
            .executeAndReturnError(&error)

        let reason = (error?[NSAppleScript.errorMessage] as? String) ?? "Couldn't move this to the Trash."
        return items
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .map { RemovalFailure(url: $0.url, reason: reason) }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
