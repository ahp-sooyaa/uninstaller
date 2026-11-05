import Cocoa
import FinderSync

/// Adds "Uninstall" to Finder's right-click menu for a single selected .app.
/// The extension is sandboxed, so it only hands the path to the main app.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // In the sandbox, NSHomeDirectory() is the container, so ask for the real home.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        // Finder never asks about /Applications when only that path is listed, because it is
        // a firmlink to the Data volume. Watching the root works, and menu(for:) ignores non-apps.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Volumes/Data/Applications"),
            URL(fileURLWithPath: home),
        ]
    }

    private var selectedApp: URL? {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              items.count == 1, items[0].pathExtension == "app" else { return nil }
        let dataVolume = "/System/Volumes/Data"
        let path = items[0].path
        return path.hasPrefix(dataVolume + "/")
            ? URL(fileURLWithPath: String(path.dropFirst(dataVolume.count)))
            : items[0]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, selectedApp != nil else { return nil }
        let menu = NSMenu(title: "")
        let item = menu.addItem(withTitle: "Uninstall", action: #selector(uninstall(_:)), keyEquivalent: "")
        item.image = trashIcon()
        return menu
    }

    /// Finder drops the template flag when it copies an extension's menu image, so a plain
    /// symbol shows up black. Baking the colour into a bitmap keeps it readable in dark mode.
    private func trashIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor = isDark ? .white : .black

        let scale = 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(symbol.size.width) * scale, pixelsHigh: Int(symbol.size.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        // Set the point size first: the context takes its scale from it when created.
        bitmap.size = NSSize(width: Int(symbol.size.width), height: Int(symbol.size.height))
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: bitmap.size)
        symbol.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    @objc private func uninstall(_ sender: AnyObject?) {
        guard let app = selectedApp else { return }
        var components = URLComponents()
        components.scheme = "uninstaller-app"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: app.path)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
