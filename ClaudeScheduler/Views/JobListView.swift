import SwiftUI

struct JobListView: View {
    @Environment(JobViewModel.self) private var viewModel
    @State private var sortOrder = [KeyPathComparator(\Job.name)]

    var body: some View {
        @Bindable var vm = viewModel

        Table(viewModel.filteredJobs, selection: $vm.selectedJobIDs, sortOrder: $sortOrder) {
            TableColumn("") { job in
                Toggle("", isOn: Binding(
                    get: { job.isEnabled },
                    set: { newValue in
                        var updated = job
                        updated.isEnabled = newValue
                        viewModel.updateJob(updated)
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(30)

            TableColumn("이름", value: \.name) { job in
                HStack(spacing: 8) {
                    Image(systemName: job.isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(job.isEnabled ? .green : .secondary)
                        .font(.caption)

                    Text(job.name)
                        .lineLimit(1)
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("스케줄") { job in
                Text(job.schedule.displayText)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .width(min: 80, ideal: 120)

            TableColumn("폴더") { job in
                Label(job.folder, systemImage: "folder")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .width(min: 80, ideal: 100)

            TableColumn("실행 방식") { job in
                HStack(spacing: 4) {
                    Image(systemName: job.runInBackground ? "gearshape.2" : "terminal")
                        .font(.caption)
                    Text(job.runInBackground ? "백그라운드" : "iTerm")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("마지막 실행") { job in
                if let lastRun = job.lastRunAt {
                    Text(lastRun, style: .relative)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    Text("없음")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
            }
            .width(min: 80, ideal: 100)
        }
        .onChange(of: sortOrder) { _, newOrder in
            viewModel.jobs.sort(using: newOrder)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if !selectedIDs.isEmpty {
                Button {
                    for id in selectedIDs {
                        if let job = viewModel.jobs.first(where: { $0.id == id }) {
                            viewModel.runJob(job)
                        }
                    }
                } label: {
                    Label("즉시 실행", systemImage: "play.fill")
                }

                Divider()

                Button {
                    for id in selectedIDs {
                        if var job = viewModel.jobs.first(where: { $0.id == id }) {
                            job.isEnabled = true
                            viewModel.updateJob(job)
                        }
                    }
                } label: {
                    Label("활성화", systemImage: "checkmark.circle")
                }

                Button {
                    for id in selectedIDs {
                        if var job = viewModel.jobs.first(where: { $0.id == id }) {
                            job.isEnabled = false
                            viewModel.updateJob(job)
                        }
                    }
                } label: {
                    Label("비활성화", systemImage: "xmark.circle")
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.selectedJobIDs = selectedIDs
                    viewModel.deleteSelectedJobs()
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
        } primaryAction: { selectedIDs in
            // 더블클릭 시 첫 번째 선택된 Job 실행
            if let id = selectedIDs.first,
               let job = viewModel.jobs.first(where: { $0.id == id }) {
                viewModel.runJob(job)
            }
        }
        .overlay {
            if viewModel.filteredJobs.isEmpty {
                ContentUnavailableView {
                    Label("작업이 없습니다", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("툴바의 + 버튼을 눌러 새 작업을 추가하세요")
                } actions: {
                    Button("새 작업 추가") {
                        viewModel.addJob()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

#Preview {
    JobListView()
        .environment(JobViewModel())
        .frame(width: 500, height: 400)
}
