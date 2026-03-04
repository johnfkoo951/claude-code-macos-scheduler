import SwiftUI

@main
struct ClaudeSchedulerApp: App {
    @State private var viewModel = JobViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 600)
        .commands {
            // 키보드 단축키
            CommandGroup(after: .newItem) {
                Button("새 작업") {
                    viewModel.addJob()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .pasteboard) {
                Button("선택한 작업 삭제") {
                    guard !viewModel.selectedJobIDs.isEmpty else { return }
                    viewModel.showDeleteConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.selectedJobIDs.isEmpty)

                Divider()

                Button("선택한 작업 실행") {
                    viewModel.runSelectedJobs()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.selectedJobIDs.isEmpty)

                Button("활성화 토글") {
                    toggleSelectedJobsEnabled()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.selectedJobIDs.isEmpty)
            }
        }

        // 설정 (⌘,)
        Settings {
            SettingsView()
                .environment(viewModel)
        }

        // 메뉴바 아이콘
        MenuBarExtra("Claude Scheduler", systemImage: "calendar.badge.clock") {
            MenuBarView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)
    }

    private func toggleSelectedJobsEnabled() {
        let allEnabled = viewModel.selectedJobIDs.allSatisfy { id in
            viewModel.jobs.first(where: { $0.id == id })?.isEnabled ?? false
        }
        if allEnabled {
            viewModel.disableSelectedJobs()
        } else {
            viewModel.enableSelectedJobs()
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(JobViewModel.self) private var viewModel

    var body: some View {
        Form {
            Picker("테마", selection: Binding(
                get: { viewModel.appTheme },
                set: { viewModel.appTheme = $0 }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 100)
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @Environment(JobViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Scheduler")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // 활성화된 Job 목록
            let enabledJobs = viewModel.jobs.filter { $0.isEnabled }

            if enabledJobs.isEmpty {
                Text("활성화된 작업이 없습니다")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(enabledJobs) { job in
                    HStack {
                        if viewModel.runningJobIDs.contains(job.id) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        } else {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.name)
                                .font(.caption)
                            Text(job.schedule.displayText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.runJob(job)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.runningJobIDs.contains(job.id))
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Button("앱 열기") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                }
            }

            Button("종료") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 250)
    }
}
