import AppKit

@MainActor
final class AppDetector {
    var onChange: (([WatchedApplication]) -> Void)?
    private let settings: SettingsStore
    private let workspace = NSWorkspace.shared
    private var observation: NSKeyValueObservation?
    private(set) var running: [WatchedApplication] = []

    init(settings: SettingsStore) { self.settings = settings }

    func start() {
        guard observation == nil else { return }
        observation = workspace.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let bundleIDs = Set(workspace.runningApplications.compactMap(\.bundleIdentifier))
        let next = settings.watchedApplications.filter { $0.isEnabled && bundleIDs.contains($0.bundleIdentifier) }
        guard next != running else { return }
        running = next
        onChange?(next)
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        running = []
    }
}
