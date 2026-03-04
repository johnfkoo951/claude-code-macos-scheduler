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

        // 메뉴바 아이콘
        MenuBarExtra("Claude Scheduler", systemImage: "calendar.badge.clock") {
            MenuBarView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)
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
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)

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
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Button("앱 열기") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("Claude") || $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
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
