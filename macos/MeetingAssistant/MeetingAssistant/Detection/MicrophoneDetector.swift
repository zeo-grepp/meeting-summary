import CoreAudio
import Foundation

enum MicrophoneState: Equatable {
    case unknown, inactive, active
}

@MainActor
final class MicrophoneDetector {
    var onChange: ((MicrophoneState) -> Void)?
    private(set) var state: MicrophoneState = .unknown {
        didSet { if oldValue != state { onChange?(state) } }
    }
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
            state = .unknown
            return
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &systemAddress, queue, listener) == noErr else {
            state = .unknown
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
        state = .unknown
    }

    private func reconcile() {
        guard isRunning, let ids = processIDs() else {
            state = .unknown
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
        for id in ids {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &size, &value) == noErr {
                active = active || value != 0
            } else {
                failed = true
            }
        }
        state = active ? .active : failed ? .unknown : .inactive
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
