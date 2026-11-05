import AppKit
import Security

struct AppInfo {
    let url: URL
    let name: String
    let bundleID: String
    let teamID: String?
    /// Main ID plus IDs of the app's own helpers and extensions.
    let ids: [String]
    let appGroups: [String]
    /// Other copies of the same app. Their data lives in the same places.
    let otherCopies: [URL]
}

enum MatchKind { case app, bundleID, appGroup, name }

struct Leftover: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let category: String
    let match: MatchKind
    /// Only exact bundle ID matches are selected by default.
    var selectedByDefault: Bool { match == .app || match == .bundleID }
    var needsAdmin: Bool {
        !FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }
}

enum ScanError: LocalizedError {
    case notAnApp, noBundleID, protected(String)
    var errorDescription: String? {
        switch self {
        case .notAnApp: return "That isn't an app."
        case .noBundleID: return "This app has no bundle ID, so its files can't be identified safely."
        case .protected(let name): return "\(name) is protected and can't be uninstalled."
        }
    }
}

enum Scanner {
    private struct Root {
        let path: String
        let category: String
        var matchesName = false
    }

    private static let roots: [Root] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = "\(home)/Library"
        return [
            Root(path: "\(user)/Application Support", category: "Application Support", matchesName: true),
            Root(path: "\(user)/Application Scripts", category: "Application Support"),
            Root(path: "\(user)/Containers", category: "Containers"),
            Root(path: "\(user)/Group Containers", category: "Containers"),
            Root(path: "\(user)/Caches", category: "Caches", matchesName: true),
            Root(path: "\(user)/HTTPStorages", category: "Caches"),
            Root(path: "\(user)/WebKit", category: "Caches"),
            Root(path: "\(user)/Preferences", category: "Preferences"),
            Root(path: "\(user)/Preferences/ByHost", category: "Preferences"),
            Root(path: "\(user)/Cookies", category: "Preferences"),
            Root(path: "\(user)/Saved Application State", category: "Saved State"),
            Root(path: "\(user)/Logs", category: "Logs", matchesName: true),
            Root(path: "\(user)/LaunchAgents", category: "Background Items"),
            Root(path: "/Library/LaunchAgents", category: "Background Items"),
            Root(path: "/Library/LaunchDaemons", category: "Background Items"),
            Root(path: "/Library/PrivilegedHelperTools", category: "Background Items"),
            Root(path: "/Library/Application Support", category: "Application Support", matchesName: true),
            Root(path: "/Library/Caches", category: "Caches"),
            Root(path: "/Library/Preferences", category: "Preferences"),
            Root(path: "/Library/Logs", category: "Logs"),
        ]
    }()

    static func inspect(_ url: URL) throws -> AppInfo {
        guard url.pathExtension == "app", let bundle = Bundle(url: url) else { throw ScanError.notAnApp }
        guard let bundleID = bundle.bundleIdentifier, !bundleID.isEmpty else { throw ScanError.noBundleID }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let isOwnApp = bundleID == Bundle.main.bundleIdentifier
        if bundleID.hasPrefix("com.apple.") || url.path.hasPrefix("/System/") || isOwnApp {
            throw ScanError.protected(name)
        }

        let signing = signingInfo(url)
        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
            .filter { $0.standardizedFileURL != url.standardizedFileURL }

        return AppInfo(
            url: url, name: name, bundleID: bundleID, teamID: signing.team,
            ids: [bundleID] + nestedIDs(in: url, mainID: bundleID),
            appGroups: signing.groups, otherCopies: copies
        )
    }

    static func scan(_ app: AppInfo) -> [Leftover] {
        var found: [URL: Leftover] = [:]
        let fm = FileManager.default
        let otherApps = installedIDs().subtracting(app.ids.map { $0.lowercased() })
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent]
            .map { $0.lowercased() }.filter { $0.count >= 3 })

        for root in roots {
            let rootURL = URL(fileURLWithPath: root.path)
            guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for entry in entries {
                guard let match = classify(entry, root: root, app: app, names: names, otherApps: otherApps) else { continue }
                let url = rootURL.appendingPathComponent(entry)
                found[url] = Leftover(url: url, category: root.category, match: match)
            }
            // "Google Chrome" keeps its data in Application Support/Google/Chrome.
            let words = app.name.split(separator: " ")
            if root.matchesName, words.count >= 2 {
                let url = rootURL.appendingPathComponent(String(words[0]))
                    .appendingPathComponent(words.dropFirst().joined(separator: " "))
                if fm.fileExists(atPath: url.path) {
                    found[url] = Leftover(url: url, category: root.category, match: .name)
                }
            }
        }

        let appItem = Leftover(url: app.url, category: "Application", match: .app)
        return [appItem] + found.values.sorted { $0.url.path < $1.url.path }
    }

    private static func classify(_ entry: String, root: Root, app: AppInfo, names: Set<String>, otherApps: Set<String>) -> MatchKind? {
        let lower = entry.lowercased()

        for group in app.appGroups where root.path.hasSuffix("/Group Containers") {
            if lower == group.lowercased() {
                // A group that doesn't carry this app's ID may be shared with sibling apps.
                return group.lowercased().contains(app.bundleID.lowercased()) ? .bundleID : .appGroup
            }
        }

        for id in app.ids {
            var candidates = [id.lowercased()]
            if let team = app.teamID { candidates.append("\(team).\(id)".lowercased()) }
            for candidate in candidates where lower == candidate || lower.hasPrefix(candidate + ".") {
                return belongsToAnotherApp(entry, matched: id, otherApps: otherApps) ? nil : .bundleID
            }
        }

        if root.matchesName && names.contains(lower) { return .name }
        return nil
    }

    /// com.foo.app must not claim com.foo.app.pro's data when that is a separate installed app.
    private static func belongsToAnotherApp(_ entry: String, matched id: String, otherApps: Set<String>) -> Bool {
        var candidate = entry.lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies"] where candidate.hasSuffix(suffix) {
            candidate = String(candidate.dropLast(suffix.count))
        }
        let moreSpecific = otherApps.filter { $0.hasPrefix(id.lowercased() + ".") }
        if moreSpecific.contains(where: { candidate == $0 || candidate.hasPrefix($0 + ".") }) { return true }
        guard candidate != id.lowercased() else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
    }

    /// Bundle IDs of apps in the Applications folders, including one level of subfolders.
    private static func installedIDs() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var ids = Set<String>()
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                if walker.level >= 2 { walker.skipDescendants() }
                if url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier {
                    ids.insert(id.lowercased())
                }
            }
        }
        return ids
    }

    /// IDs of bundles shipped inside the app. Third-party ones such as Sparkle are skipped
    /// because their data is shared with every other app that embeds them.
    private static func nestedIDs(in app: URL, mainID: String) -> [String] {
        let vendor = mainID.split(separator: ".").prefix(2).joined(separator: ".") + "."
        let folders = ["Library/LoginItems", "Library/LaunchServices", "PlugIns", "XPCServices", "Helpers"]
        var ids = Set<String>()
        for folder in folders {
            let dir = app.appendingPathComponent("Contents/\(folder)")
            let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                if let id = Bundle(url: entry)?.bundleIdentifier, id != mainID, id.hasPrefix(vendor) {
                    ids.insert(id)
                }
            }
        }
        return ids.sorted()
    }

    private static func signingInfo(_ url: URL) -> (team: String?, groups: [String]) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (nil, []) }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return (nil, []) }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return (team, groups)
    }

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isDirectory == true else { return Int64(values?.totalFileAllocatedSize ?? 0) }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
