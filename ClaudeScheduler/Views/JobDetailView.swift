import SwiftUI

struct JobDetailView: View {
    @Environment(JobViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let job = viewModel.selectedJob {
                JobEditForm(job: job)
            } else if viewModel.selectedJobIDs.count > 1 {
                multipleSelectionView
            } else {
                noSelectionView
            }
        }
    }

    private var multipleSelectionView: some View {
        ContentUnavailableView {
            Label("\(viewModel.selectedJobIDs.count)개 선택됨", systemImage: "checkmark.circle.fill")
        } description: {
            Text("여러 작업이 선택되었습니다.\n일괄 작업을 수행하거나 하나만 선택하세요.")
        } actions: {
            HStack(spacing: 12) {
                Button("모두 실행") {
                    viewModel.runSelectedJobs()
                }
                .buttonStyle(.borderedProminent)

                Button("모두 삭제", role: .destructive) {
                    viewModel.showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var noSelectionView: some View {
        ContentUnavailableView {
            Label("작업을 선택하세요", systemImage: "sidebar.left")
        } description: {
            Text("왼쪽 목록에서 작업을 선택하면\n여기에서 편집할 수 있습니다.")
        }
    }
}

// MARK: - JobEditForm

struct JobEditForm: View {
    @Environment(JobViewModel.self) private var viewModel
    let job: Job

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var selectedFolder: String = "Default"
    @State private var schedule: Schedule = .interval(seconds: 3600)
    @State private var isEnabled: Bool = true
    @State private var runInBackground: Bool = true
    @State private var selectedLogURL: URL?

    /// Debounce용 Task (이전 Task를 취소하고 새로 생성)
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("기본 정보") {
                TextField("이름", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("폴더", selection: $selectedFolder) {
                    ForEach(viewModel.folders) { folder in
                        Text(folder.name).tag(folder.name)
                    }
                }
            }

            Section("프롬프트") {
                TextEditor(text: $prompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 120, maxHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            Section("스케줄") {
                SchedulePicker(schedule: $schedule)
            }

            Section("실행 옵션") {
                Toggle("활성화", isOn: $isEnabled)

                Toggle("백그라운드 실행", isOn: $runInBackground)

                if !runInBackground {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("iTerm에서 새 창을 열어 실행합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 실행 로그 섹션
            Section("실행 로그") {
                let logs = viewModel.logFiles(for: job)
                if logs.isEmpty {
                    Text("로그가 없습니다")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                } else {
                    ForEach(logs.prefix(5), id: \.self) { logURL in
                        Button {
                            selectedLogURL = logURL
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(logURL.lastPathComponent)
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if logs.count > 5 {
                        Button("Finder에서 열기") {
                            if let firstLog = logs.first {
                                NSWorkspace.shared.activateFileViewerSelecting([firstLog.deletingLastPathComponent()])
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Section {
                HStack {
                    if let lastRun = job.lastRunAt {
                        Label {
                            Text("마지막 실행: \(lastRun, style: .relative)")
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("즉시 실행") {
                        flushSave()
                        if let updatedJob = viewModel.jobs.first(where: { $0.id == job.id }) {
                            viewModel.runJob(updatedJob)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .sheet(item: $selectedLogURL) { logURL in
            LogViewerSheet(logURL: logURL)
        }
        .onAppear {
            loadJobData()
        }
        .onDisappear {
            // 뷰 떠날 때 즉시 저장 + launchd 동기화
            flushSave()
            if let updatedJob = viewModel.jobs.first(where: { $0.id == job.id }) {
                viewModel.syncJobToLaunchd(updatedJob)
            }
        }
        .onChange(of: job.id) { _, _ in
            loadJobData()
        }
        // 활성화/스케줄 변경은 즉시 저장 (launchd 동기화 필요)
        .onChange(of: isEnabled) { _, _ in saveImmediately() }
        .onChange(of: schedule) { _, _ in saveImmediately() }
        // 텍스트 입력은 debounce (0.5초)
        .onChange(of: name) { _, _ in debounceSave() }
        .onChange(of: prompt) { _, _ in debounceSave() }
        .onChange(of: selectedFolder) { _, _ in debounceSave() }
        .onChange(of: runInBackground) { _, _ in debounceSave() }
    }

    private func loadJobData() {
        name = job.name
        prompt = job.prompt
        selectedFolder = job.folder
        schedule = job.schedule
        isEnabled = job.isEnabled
        runInBackground = job.runInBackground
    }

    /// debounce 저장 — 0.5초 후 storage에만 저장 (launchd 미동기화)
    private func debounceSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveToStorage()
        }
    }

    /// 즉시 저장 + launchd 동기화 (활성화/스케줄 변경 시)
    private func saveImmediately() {
        saveTask?.cancel()
        let updatedJob = buildUpdatedJob()
        viewModel.updateJob(updatedJob)
    }

    /// 즉시 flush — pending debounce가 있으면 즉시 실행
    private func flushSave() {
        saveTask?.cancel()
        saveToStorage()
    }

    /// storage에만 저장 (launchd 동기화 없이)
    private func saveToStorage() {
        let updatedJob = buildUpdatedJob()
        viewModel.updateJob(updatedJob)
    }

    private func buildUpdatedJob() -> Job {
        var updatedJob = job
        updatedJob.name = name
        updatedJob.prompt = prompt
        updatedJob.folder = selectedFolder
        updatedJob.schedule = schedule
        updatedJob.isEnabled = isEnabled
        updatedJob.runInBackground = runInBackground
        return updatedJob
    }
}

// MARK: - LogViewerSheet

struct LogViewerSheet: View {
    let logURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(logURL.lastPathComponent)
                    .font(.headline)
                Spacer()
                Button("Finder에서 열기") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .controlSize(.small)
                Button("닫기") { dismiss() }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                Text(content)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 600, height: 400)
        .onAppear {
            content = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "로그를 읽을 수 없습니다"
        }
    }
}

// URL을 sheet(item:)에서 사용하기 위한 Identifiable 적합
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#Preview {
    JobDetailView()
        .environment(JobViewModel())
        .frame(width: 350, height: 600)
}
