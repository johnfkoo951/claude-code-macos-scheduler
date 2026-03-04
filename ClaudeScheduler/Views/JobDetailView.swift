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
                    viewModel.deleteSelectedJobs()
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
                        saveChanges()
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
        .onAppear {
            loadJobData()
        }
        .onChange(of: job.id) { _, _ in
            loadJobData()
        }
        .onChange(of: name) { _, _ in saveChanges() }
        .onChange(of: prompt) { _, _ in saveChanges() }
        .onChange(of: selectedFolder) { _, _ in saveChanges() }
        .onChange(of: schedule) { _, _ in saveChanges() }
        .onChange(of: isEnabled) { _, _ in saveChanges() }
        .onChange(of: runInBackground) { _, _ in saveChanges() }
    }

    private func loadJobData() {
        name = job.name
        prompt = job.prompt
        selectedFolder = job.folder
        schedule = job.schedule
        isEnabled = job.isEnabled
        runInBackground = job.runInBackground
    }

    private func saveChanges() {
        var updatedJob = job
        updatedJob.name = name
        updatedJob.prompt = prompt
        updatedJob.folder = selectedFolder
        updatedJob.schedule = schedule
        updatedJob.isEnabled = isEnabled
        updatedJob.runInBackground = runInBackground

        viewModel.updateJob(updatedJob)
    }
}

#Preview {
    JobDetailView()
        .environment(JobViewModel())
        .frame(width: 350, height: 600)
}
