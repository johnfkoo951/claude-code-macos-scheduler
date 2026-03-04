import SwiftUI

struct ContentView: View {
    @Environment(JobViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
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
                    .help("새 작업 추가 (⌘N)")

                    Button {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                    .disabled(viewModel.selectedJobIDs.isEmpty)
                    .help("선택한 작업 삭제 (⌘⌫)")

                    Divider()

                    Button {
                        viewModel.runSelectedJobs()
                    } label: {
                        Label("실행", systemImage: "play.fill")
                    }
                    .disabled(viewModel.selectedJobIDs.isEmpty)
                    .help("선택한 작업 즉시 실행 (⌘R)")
                }
            }

            // 하단 상태바
            StatusBarView()
        }
        .toast(message: viewModel.toastMessage)
        .preferredColorScheme(viewModel.appTheme.colorScheme)
        .confirmationDialog(
            "선택한 작업을 삭제하시겠습니까?",
            isPresented: $vm.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                viewModel.deleteSelectedJobs()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 작업을 삭제하면 launchd 스케줄도 함께 제거됩니다.\n이 동작은 되돌릴 수 없습니다.")
        }
    }
}

#Preview {
    ContentView()
        .environment(JobViewModel())
        .frame(width: 1000, height: 600)
}
