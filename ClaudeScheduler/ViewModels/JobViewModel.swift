import Foundation
import SwiftUI
import Combine

@Observable
class JobViewModel {
    // MARK: - Properties
    var jobs: [Job] = []
    var folders: [Folder] = []
    var selectedJobIDs: Set<UUID> = []
    var selectedFolderID: UUID? = nil

    // Services
    private let storage = StorageService.shared
    private let launchd = LaunchdService.shared
    private let executor = ExecutorService.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// 선택된 폴더에 해당하는 Job만 필터링
    var filteredJobs: [Job] {
        guard let folderID = selectedFolderID,
              let folder = folders.first(where: { $0.id == folderID }) else {
            return jobs
        }
        return jobs.filter { $0.folder == folder.name }
    }

    /// 현재 선택된 단일 Job (디테일 뷰용)
    var selectedJob: Job? {
        guard selectedJobIDs.count == 1,
              let id = selectedJobIDs.first else { return nil }
        return jobs.first { $0.id == id }
    }

    /// Claude CLI 사용 가능 여부
    var isClaudeAvailable: Bool {
        executor.isClaudeAvailable()
    }

    /// Claude CLI 버전
    var claudeVersion: String? {
        executor.getClaudeVersion()
    }

    // MARK: - Initialization

    init() {
        // StorageService에서 데이터 구독
        storage.$jobs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newJobs in
                self?.jobs = newJobs
            }
            .store(in: &cancellables)

        storage.$folders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newFolders in
                self?.folders = newFolders
            }
            .store(in: &cancellables)
    }

    // MARK: - Job CRUD

    func addJob() {
        let folderName = selectedFolderID.flatMap { id in
            folders.first { $0.id == id }?.name
        } ?? "Default"

        let newJob = Job(
            name: "새 작업",
            prompt: "",
            folder: folderName,
            schedule: .interval(seconds: 3600)
        )

        storage.addJob(newJob)
        selectedJobIDs = [newJob.id]

        // launchd에 등록 (비활성화 상태로)
        do {
            try launchd.registerJob(newJob)
        } catch {
            print("[JobViewModel] Failed to register job with launchd: \(error)")
        }
    }

    func updateJob(_ job: Job) {
        // 이전 상태와 비교하여 활성화 상태 변경 감지
        let previousJob = jobs.first { $0.id == job.id }
        let wasEnabled = previousJob?.isEnabled ?? false

        storage.updateJob(job)

        // launchd 업데이트
        do {
            if job.isEnabled != wasEnabled {
                // 활성화 상태 변경
                if job.isEnabled {
                    try launchd.enableJob(job)
                } else {
                    try launchd.disableJob(job)
                }
            } else if job.isEnabled {
                // 활성화 상태 유지 중 스케줄 변경
                try launchd.updateJob(job)
            }
        } catch {
            print("[JobViewModel] Failed to update launchd: \(error)")
        }
    }

    func deleteSelectedJobs() {
        for id in selectedJobIDs {
            if let job = jobs.first(where: { $0.id == id }) {
                deleteJob(job)
            }
        }
        selectedJobIDs.removeAll()
    }

    func deleteJob(_ job: Job) {
        // launchd에서 제거
        do {
            try launchd.unregisterJob(job)
        } catch {
            print("[JobViewModel] Failed to unregister job from launchd: \(error)")
        }

        storage.deleteJob(job)
        selectedJobIDs.remove(job.id)
    }

    // MARK: - Folder CRUD

    func addFolder() {
        let newFolder = Folder(name: "새 폴더")
        storage.addFolder(newFolder)
        selectedFolderID = newFolder.id
    }

    func updateFolder(_ folder: Folder) {
        let oldFolder = folders.first { $0.id == folder.id }
        let oldName = oldFolder?.name

        storage.updateFolder(folder)

        // 폴더명 변경 시 해당 폴더의 Job들도 업데이트
        if let oldName = oldName, oldName != folder.name {
            for job in jobs where job.folder == oldName {
                var updatedJob = job
                updatedJob.folder = folder.name
                storage.updateJob(updatedJob)
            }
        }
    }

    func deleteFolder(_ folder: Folder) {
        guard folder.name != "Default" else { return }

        storage.deleteFolder(folder)

        if selectedFolderID == folder.id {
            selectedFolderID = nil
        }
    }

    // MARK: - Job Execution

    func runSelectedJobs() {
        for id in selectedJobIDs {
            if let job = jobs.first(where: { $0.id == id }) {
                runJob(job)
            }
        }
    }

    func runJob(_ job: Job) {
        executor.executeJob(job) { result in
            switch result {
            case .success(let message):
                print("[JobViewModel] Job executed successfully: \(message)")
            case .failure(let error):
                print("[JobViewModel] Job execution failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bulk Operations

    func enableSelectedJobs() {
        for id in selectedJobIDs {
            if var job = jobs.first(where: { $0.id == id }) {
                job.isEnabled = true
                updateJob(job)
            }
        }
    }

    func disableSelectedJobs() {
        for id in selectedJobIDs {
            if var job = jobs.first(where: { $0.id == id }) {
                job.isEnabled = false
                updateJob(job)
            }
        }
    }

    // MARK: - Log Management

    func logFiles(for job: Job) -> [URL] {
        storage.logFiles(for: job)
    }

    func cleanupOldLogs() {
        storage.cleanupOldLogs()
    }

    // MARK: - Launchd Status

    func isJobLoaded(_ job: Job) -> Bool {
        launchd.isJobLoaded(job)
    }

    func listLoadedJobs() -> [String] {
        launchd.listAllJobs()
    }
}
