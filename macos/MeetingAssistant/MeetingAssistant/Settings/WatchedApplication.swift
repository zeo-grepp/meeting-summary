import Foundation

struct WatchedApplication: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
    var isEnabled = true

    init(bundleIdentifier: String, displayName: String, isEnabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.isEnabled = isEnabled
    }

    init(url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let identifier = bundle.bundleIdentifier,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "bundle identifier가 있는 macOS 앱을 선택해주세요."
            ])
        }
        bundleIdentifier = identifier
        displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}
