import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: UninstallModel

    var body: some View {
        Group {
            switch model.phase {
            case .empty: EmptyStateView(model: model)
            case .ready: FileListView(model: model)
            case .working: ProgressView("Moving to Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished(let failures): ResultView(model: model, failures: failures)
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "Can't uninstall", detail: message) {
                    Button("OK") { model.close() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    @ObservedObject var model: UninstallModel

    var body: some View {
        MessageView(
            symbol: "trash",
            title: "Right-click an app in Finder and choose Uninstall",
            detail: "If the menu item is missing, turn on Uninstaller under Finder extensions in System Settings."
        ) {
            HStack {
                Button("Choose App…", action: choose).keyboardShortcut(.defaultAction)
                Button("Open Extension Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { model.load(url) }
    }
}

private struct FileListView: View {
    @ObservedObject var model: UninstallModel

    var body: some View {
        VStack(spacing: 0) {
            if let app = model.app { header(app) }
            Divider()
            List {
                ForEach(model.categories, id: \.self) { category in
                    Section(category) {
                        ForEach(model.items.filter { $0.category == category }) { item in
                            FileRow(model: model, item: item)
                        }
                    }
                }
            }
            Divider()
            footer
        }
    }

    private func header(_ app: AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title2.weight(.semibold))
                    Text(app.bundleID).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
            }
            if Remover.isRunning(app) {
                Label("\(app.name) is running and will be quit first.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let copy = app.otherCopies.first {
                Label("Another copy is at \(copy.path). It shares these data files.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text("\(model.selected.count) of \(model.items.count) selected · \(formatted(model.selectedSize))")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Cancel") { model.close() }.keyboardShortcut(.cancelAction)
            Button("Move to Trash") { model.uninstall() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selected.isEmpty)
        }
        .padding(12)
    }
}

private struct FileRow: View {
    @ObservedObject var model: UninstallModel
    let item: Leftover

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(item.url) },
                set: { _ in model.toggle(item.url) }
            ))
            .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if item.needsAdmin {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help("Needs your password")
            }
            Text(model.sizes[item.url].map(formatted) ?? "…")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
    }

    private var note: String? {
        switch item.match {
        case .name: return "Name match"
        case .appGroup: return "May be shared"
        default: return nil
        }
    }
}

private struct ResultView: View {
    @ObservedObject var model: UninstallModel
    let failures: [RemovalFailure]

    var body: some View {
        if failures.isEmpty {
            MessageView(
                symbol: "checkmark.circle",
                title: "\(model.app?.name ?? "App") moved to Trash",
                detail: "You can put it back from the Trash until you empty it."
            ) { doneButton }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Some items couldn't be removed").font(.title3.weight(.semibold))
                Text("If access was denied, give Uninstaller Full Disk Access and App Management in Privacy & Security, then try again.")
                    .font(.callout).foregroundStyle(.secondary)
                List(failures) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.url.path).lineLimit(1).truncationMode(.middle)
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack { Spacer(); doneButton }
            }
            .padding(16)
        }
    }

    private var doneButton: some View {
        Button("Done") { model.close() }.keyboardShortcut(.defaultAction)
    }
}

private struct MessageView<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions.padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
