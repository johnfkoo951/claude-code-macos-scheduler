import SwiftUI

struct ContentView: View {
    @Environment(JobViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } content: {
            JobListView()
                .navigationSplitViewColumnWidth(min: 350, ideal: 450, max: 600)
        } detail: {
            JobDetailView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        }
        .navigationTitle("Claude Scheduler")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    viewModel.addJob()
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .help("새 작업 추가")

                Button {
                    viewModel.deleteSelectedJobs()
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                .disabled(viewModel.selectedJobIDs.isEmpty)
                .help("선택한 작업 삭제")

                Divider()

                Button {
                    viewModel.runSelectedJobs()
                } label: {
                    Label("실행", systemImage: "play.fill")
                }
                .disabled(viewModel.selectedJobIDs.isEmpty)
                .help("선택한 작업 즉시 실행")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(JobViewModel())
        .frame(width: 1000, height: 600)
}
