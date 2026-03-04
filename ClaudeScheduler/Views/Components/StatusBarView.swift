import SwiftUI

/// CmdMD 스타일 하단 상태바
struct StatusBarView: View {
    @Environment(JobViewModel.self) private var viewModel

    private var enabledCount: Int {
        viewModel.jobs.filter(\.isEnabled).count
    }

    var body: some View {
        HStack(spacing: 16) {
            // 왼쪽: 작업 통계
            HStack(spacing: 12) {
                statusItem("\(viewModel.jobs.count) 작업", icon: "list.bullet")

                statusItem("\(enabledCount) 활성", icon: "checkmark.circle")

                if !viewModel.runningJobIDs.isEmpty {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                        Text("\(viewModel.runningJobIDs.count) 실행 중")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }

            Spacer()

            // 오른쪽: Claude CLI 상태
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isClaudeAvailable ? .green : .red)
                    .frame(width: 6, height: 6)

                if let version = viewModel.claudeVersion {
                    Text("Claude \(version)")
                } else {
                    Text(viewModel.isClaudeAvailable ? "Claude CLI" : "CLI 없음")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func statusItem(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
