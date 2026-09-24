import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let notifications: NotificationManager

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
                            VStack(alignment: .leading) {
                                Text(app.displayName)
                                Text(app.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
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
                LabeledContent("macOS 알림 권한", value: notifications.statusText)
                if notifications.authorizationStatus == .authorized {
                    LabeledContent("알림 소리", value: notifications.soundsEnabled ? "허용됨" : "꺼짐 — 시스템 설정 > 알림에서 확인")
                    if settings.notificationsEnabled && !notifications.soundsEnabled {
                        Button("알림 소리 권한 요청") {
                            Task { await notifications.requestAuthorization() }
                        }
                        .disabled(notifications.isRequesting)
                    }
                }
                if settings.notificationsEnabled && notifications.authorizationStatus == .notDetermined {
                    Button("알림 권한 요청") {
                        Task { await notifications.requestAuthorization() }
                    }
                    .disabled(notifications.isRequesting)
                }
                if let error = notifications.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                Text("알림이 거부된 경우 macOS 시스템 설정 > 알림 > Meeting Assistant에서 허용해주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("프로젝트 폴더") {
                Text(settings.projectRootPath.isEmpty ? "선택하지 않음" : settings.projectRootPath)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                Button("프로젝트 폴더 선택…", action: chooseProject)
                Text("meeting.py가 있는 폴더를 선택하세요. 녹음은 이 폴더의 recordings에 .m4a로 저장됩니다.")
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
        .frame(width: 560, height: 600)
        .navigationTitle("Meeting Assistant 설정")
        .task { await notifications.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refresh() }
        }
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
