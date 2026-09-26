import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let notifications: NotificationManager
    @State private var microphoneGranted = false
    @State private var screenRecordingGranted = false

    var body: some View {
        Form {
            Section {
                Text("감시 앱과 알림을 설정하세요. 녹음 시작 시 마이크 권한을 요청하고 녹음 파일을 프로젝트 폴더에 저장합니다.")
                    .foregroundStyle(.secondary)
            }
            Section("감시할 앱") {
                if settings.watchedApplications.isEmpty {
                    Text("감시할 앱을 추가해주세요.").foregroundStyle(.secondary)
                }
                ForEach($settings.watchedApplications) { $app in
                    HStack {
                        Toggle(isOn: $app.isEnabled) {
                            HStack {
                                Image(nsImage: icon(for: app))
                                    .resizable().frame(width: 20, height: 20)
                                VStack(alignment: .leading) {
                                    Text(app.displayName)
                                    Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            settings.watchedApplications.removeAll { $0.id == app.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(app.displayName) 삭제")
                    }
                }
                Button("앱 추가…", action: chooseApplication)
                Text("감지 조건: 선택한 앱 실행 중 + 오디오 입력 사용 시작")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // 권한이 없으면 "녹음 시작"을 누른 뒤에야 시스템 다이얼로그가 뜨고,
            // 화면 녹음은 허용해도 재시작이 필요해 그 회의를 통째로 놓친다. 미리 받아둔다.
            Section("권한") {
                LabeledContent("마이크") {
                    HStack {
                        Text(microphoneGranted ? "허용됨" : "필요함")
                        Button("요청") {
                            Task {
                                _ = await AVCaptureDevice.requestAccess(for: .audio)
                                refreshPermissions()
                            }
                        }
                        .disabled(microphoneGranted)
                    }
                }
                LabeledContent("화면·시스템 오디오 녹음") {
                    HStack {
                        Text(screenRecordingGranted ? "허용됨" : "필요함")
                        Button("요청") {
                            CGRequestScreenCaptureAccess()
                            refreshPermissions()
                        }
                        .disabled(screenRecordingGranted)
                    }
                }
                Text("앱 소리를 함께 녹음하려면 화면 녹음 권한이 필요합니다. 허용한 뒤에는 앱을 한 번 재시작해주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("알림") {
                Toggle("회의 감지 시 녹음 여부 알림", isOn: $settings.notificationsEnabled)
                    .disabled(notifications.isRequesting)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            await notifications.refresh()
                            if notifications.authorizationStatus == .notDetermined {
                                await notifications.requestAuthorization()
                            }
                        }
                    }
                // 권한 상태에 따라 줄이 생겼다 사라지면 레이아웃이 튄다.
                // 줄은 항상 두고 버튼만 비활성으로 바꾼다.
                LabeledContent("macOS 알림 권한") {
                    HStack {
                        Text(notifications.statusText)
                        Button(notifications.authorizationStatus == .notDetermined ? "요청" : "시스템 설정") {
                            // 권한이 한 번 결정된 뒤에는 requestAuthorization이 다이얼로그를 띄우지 않는다.
                            if notifications.authorizationStatus == .notDetermined {
                                Task { await notifications.requestAuthorization() }
                            } else {
                                openNotificationSettings()
                            }
                        }
                        .disabled(notifications.isRequesting
                                  || (notifications.authorizationStatus == .authorized && notifications.alertsEnabled))
                    }
                }
                LabeledContent("알림 소리") {
                    HStack {
                        Text(notifications.soundsEnabled ? "허용됨" : "꺼짐")
                        Button("시스템 설정", action: openNotificationSettings)
                            .disabled(notifications.soundsEnabled)
                    }
                }
                if let error = notifications.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            // 사용자가 궁금한 건 "어디에 저장되나"지 "프로젝트 루트가 어디냐"가 아니다.
            Section("녹음 저장 위치") {
                Text(settings.recordingsURL?.path(percentEncoded: false) ?? "선택하지 않음")
                    .textSelection(.enabled)
                    .lineLimit(nil)
                Button("프로젝트 폴더 선택…", action: chooseProject)
                Text("meeting.py가 있는 프로젝트 폴더를 고르면 그 안의 recordings 폴더에 .m4a로 저장됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = settings.errorMessage {
                Section("설정 오류") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("닫기") { settings.errorMessage = nil }
                }
            }
        }
        .formStyle(.grouped)
        // 감시 앱이 늘거나 프로젝트 경로가 길면 내용이 넘치므로 크기를 고정하지 않는다.
        .frame(minWidth: 460, minHeight: 420)
        .navigationTitle("Meeting Assistant 설정")
        .task {
            await notifications.refresh()
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refresh() }
            refreshPermissions()
        }
    }

    /// 경로는 저장하지 않으므로 bundle identifier로 매번 찾는다. 앱이 없으면 일반 앱 아이콘으로 자리를 지킨다.
    private func icon(for app: WatchedApplication) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
        else { return NSWorkspace.shared.icon(for: .applicationBundle) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "감시할 앱 선택"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        do {
            for url in panel.urls { try settings.addApplication(at: url) }
        } catch {
            settings.errorMessage = error.localizedDescription
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "meeting-summary 프로젝트 폴더 선택"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.selectProject(at: url)
        } catch {
            settings.errorMessage = error.localizedDescription
        }
    }
}
