import AppKit

@MainActor
final class UninstallModel: ObservableObject {
    enum Phase {
        case empty
        case ready
        case working
        case finished(failures: [RemovalFailure])
        case failed(String)
    }

    @Published var phase: Phase = .empty
    @Published var app: AppInfo?
    @Published var items: [Leftover] = []
    @Published var selected: Set<URL> = []
    @Published var sizes: [URL: Int64] = [:]

    var categories: [String] {
        var seen = Set<String>()
        return items.map(\.category).filter { seen.insert($0).inserted }
    }

    var selectedSize: Int64 {
        selected.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    func load(_ url: URL) {
        items = []
        selected = []
        sizes = [:]
        app = nil
        do {
            let info = try Scanner.inspect(url)
            let found = Scanner.scan(info)
            app = info
            items = found
            selected = Set(found.filter(\.selectedByDefault).map(\.url))
            phase = .ready
            measure(found)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func measure(_ found: [Leftover]) {
        for item in found {
            Task.detached(priority: .utility) { [weak self] in
                let size = Scanner.size(of: item.url)
                await MainActor.run { self?.sizes[item.url] = size }
            }
        }
    }

    func toggle(_ url: URL) {
        if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
    }

    func uninstall() {
        guard let app else { return }
        let chosen = items.filter { selected.contains($0.url) }
        phase = .working
        Task {
            do {
                try await Remover.quit(app)
                let failures = await Task.detached { Remover.remove(chosen) }.value
                phase = .finished(failures: failures)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// The app only exists for this one job, so finishing or cancelling quits it.
    func close() {
        NSApp.terminate(nil)
    }
}
