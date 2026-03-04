import SwiftUI

struct SidebarView: View {
    @Environment(JobViewModel.self) private var viewModel
    @State private var editingFolderID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        @Bindable var vm = viewModel

        List(selection: $vm.selectedFolderID) {
            // "전체" 항목
            Label {
                Text("전체")
            } icon: {
                Image(systemName: "tray.full.fill")
            }
            .tag(nil as UUID?)
            .listRowSeparator(.hidden)

            Section("폴더") {
                ForEach(viewModel.folders) { folder in
                    folderRow(folder)
                        .tag(folder.id as UUID?)
                        .contextMenu {
                            if folder.name != "Default" {
                                Button("이름 변경") {
                                    startEditing(folder)
                                }

                                Divider()

                                Button("삭제", role: .destructive) {
                                    viewModel.deleteFolder(folder)
                                }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    viewModel.addFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("새 폴더 추가")

                Spacer()

                if let folderID = viewModel.selectedFolderID,
                   let folder = viewModel.folders.first(where: { $0.id == folderID }),
                   folder.name != "Default" {
                    Button {
                        viewModel.deleteFolder(folder)
                    } label: {
                        Image(systemName: "folder.badge.minus")
                    }
                    .buttonStyle(.borderless)
                    .help("폴더 삭제")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Folder) -> some View {
        if editingFolderID == folder.id {
            TextField("폴더 이름", text: $editingName, onCommit: {
                saveEditing(folder)
            })
            .textFieldStyle(.roundedBorder)
            .onExitCommand {
                cancelEditing()
            }
        } else {
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: folder.name == "Default" ? "folder.fill" : "folder")
                    .foregroundStyle(folder.swiftUIColor)
            }
            .onTapGesture(count: 2) {
                if folder.name != "Default" {
                    startEditing(folder)
                }
            }
        }
    }

    private func startEditing(_ folder: Folder) {
        editingFolderID = folder.id
        editingName = folder.name
    }

    private func saveEditing(_ folder: Folder) {
        var updatedFolder = folder
        updatedFolder.name = editingName.isEmpty ? folder.name : editingName
        viewModel.updateFolder(updatedFolder)
        cancelEditing()
    }

    private func cancelEditing() {
        editingFolderID = nil
        editingName = ""
    }
}

#Preview {
    SidebarView()
        .environment(JobViewModel())
        .frame(width: 200, height: 400)
}
