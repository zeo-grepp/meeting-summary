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

    /// 오디오를 잡는 프로세스가 이 앱의 것인지. Chrome이나 Electron 앱은 앱 본체가 아니라
    /// com.google.Chrome.helper 같은 하위 프로세스가 마이크를 연다.
    func owns(audioProcess bundleID: String) -> Bool {
        bundleID == bundleIdentifier || bundleID.hasPrefix(bundleIdentifier + ".")
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
