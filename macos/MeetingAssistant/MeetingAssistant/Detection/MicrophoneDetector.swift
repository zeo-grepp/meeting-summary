import CoreAudio
import Foundation

enum MicrophoneState: Equatable {
    case unknown, inactive, active
}

@MainActor
final class MicrophoneDetector {
    var onChange: ((MicrophoneState) -> Void)?
    private(set) var state: MicrophoneState = .unknown
    /// 지금 마이크를 쓰고 있는 프로세스들의 번들 ID.
    /// 늘 떠 있는 브라우저 때문에 "앱이 실행 중"만으로는 회의를 알 수 없어 누가 쓰는지까지 본다.
    private(set) var activeBundleIDs: Set<String> = []
    private let queue = DispatchQueue.main
    private var systemAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var inputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningInput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var refreshTimer: Timer?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &systemAddress) else {
            update(.unknown)
            return
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemAddress, queue, listener) == noErr else {
            update(.unknown)
            return
        }
        systemListener = listener
        isRunning = true
        reconcile()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let systemListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemAddress, queue, systemListener)
            self.systemListener = nil
        }
        for (id, listener) in processListeners {
            AudioObjectRemovePropertyListenerBlock(id, &inputAddress, queue, listener)
        }
        processListeners.removeAll()
        update(.unknown)
    }

    private func reconcile() {
        guard isRunning, let ids = processIDs() else {
            update(.unknown)
            return
        }
        let current = Set(ids)
        for (id, listener) in processListeners.filter({ !current.contains($0.key) }) {
            AudioObjectRemovePropertyListenerBlock(id, &inputAddress, queue, listener)
            processListeners.removeValue(forKey: id)
        }
        var failed = false
        for id in ids where processListeners[id] == nil {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &inputAddress, queue, listener) == noErr {
                processListeners[id] = listener
            } else {
                failed = true
            }
        }
        var active = false
        var bundleIDs: Set<String> = []
        for id in ids {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &size, &value) == noErr else {
                failed = true
                continue
            }
            guard value != 0 else { continue }
            active = true
            if let bundleID = bundleID(of: id) { bundleIDs.insert(bundleID) }
        }
        update(active ? .active : failed ? .unknown : .inactive, bundleIDs)
    }

    private func update(_ next: MicrophoneState, _ bundleIDs: Set<String> = []) {
        // 상태가 .active 그대로여도 마이크를 쓰는 앱이 바뀌면 알려야 한다.
        guard next != state || bundleIDs != activeBundleIDs else { return }
        state = next
        activeBundleIDs = bundleIDs
        onChange?(next)
    }

    /// 마이크를 실제로 잡는 것은 헬퍼 프로세스인 경우가 많다(com.google.Chrome.helper).
    /// 앱으로 되돌리지 않고 프로세스의 번들 ID를 그대로 돌려준다 — 판정은 부르는 쪽이 한다.
    private func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(process, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let bundleID = value as String?, !bundleID.isEmpty else { return nil }
        return bundleID
    }

    private func processIDs() -> [AudioObjectID]? {
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &systemAddress, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &systemAddress, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return nil }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
