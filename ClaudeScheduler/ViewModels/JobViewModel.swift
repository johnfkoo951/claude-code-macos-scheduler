import Foundation
import SwiftUI

@MainActor
@Observable
class JobViewModel {
    // MARK: - Properties
    var selectedJobIDs: Set<UUID> = []
    var selectedFolderID: UUID? = nil
    var runningJobIDs: Set<UUID> = []
    var toastMessage: String?
    var showDeleteConfirmation = false

    // Services
    private let storage = StorageService.shared
    private let launchd = LaunchdService.shared
    private let executor = ExecutorService.shared

    // MARK: - Computed Properties (storage 직접 참조)

    var jobs: [Job] { storage.jobs }
    var folders: [Folder] { storage.folders }

    /// 선택된 폴더에 해당하는 Job만 필터링
    var filteredJobs: [Job] {
        guard let folderID = selectedFolderID,
              let folder = folders.first(where: { $0.id == folderID }) else {
            return jobs
        }
        return jobs.filter { $0.folder == folder.name }
    }

    /// 현재 선택된 단일 Job
    var selectedJob: Job? {
        guard selectedJobIDs.count == 1,
              let id = selectedJobIDs.first else { return nil }
        return jobs.first { $0.id == id }
    }

    /// Claude CLI 사용 가능 여부 (캐싱)
    private(set) var isClaudeAvailable: Bool = false
    private(set) var claudeVersion: String?

    // MARK: - Settings
    var appTheme: AppTheme = .system

    // MARK: - Initialization

    init() {
        // CLI 상태를 비동기로 확인
        Task {
            isClaudeAvailable = executor.isClaudeAvailable()
            claudeVersion = executor.getClaudeVersion()
        }
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

        do {
            try launchd.registerJob(newJob)
        } catch {
            print("[JobViewModel] Failed to register job: \(error)")
        }
    }

    func updateJob(_ job: Job) {
        let previousJob = jobs.first { $0.id == job.id }
        let wasEnabled = previousJob?.isEnabled ?? false

        storage.updateJob(job)

        // launchd는 활성화 상태 변경 시에만 동기화
        do {
            if job.isEnabled != wasEnabled {
                if job.isEnabled {
                    try launchd.enableJob(job)
                } else {
                    try launchd.disableJob(job)
                }
            }
        } catch {
            print("[JobViewModel] Failed to update launchd: \(error)")
        }
    }

    /// launchd 스케줄까지 동기화 (debounce 후 호출용)
    func syncJobToLaunchd(_ job: Job) {
        guard job.isEnabled else { return }
        do {
            try launchd.updateJob(job)
        } catch {
            print("[JobViewModel] Failed to sync launchd: \(error)")
        }
    }

    func deleteSelectedJobs() {
        for id in selectedJobIDs {
            if let job = jobs.first(where: { $0.id == id }) {
                deleteJob(job)
            }
        }
        selectedJobIDs.removeAll()
        showToast("작업이 삭제되었습니다")
    }

    func deleteJob(_ job: Job) {
        do {
            try launchd.unregisterJob(job)
        } catch {
            print("[JobViewModel] Failed to unregister job: \(error)")
        }

        storage.deleteJob(job)
        selectedJobIDs.remove(job.id)
    }

    // MARK: - Folder CRUD

    func addFolder() {
        // 중복 이름 자동 넘버링
        var name = "새 폴더"
        var counter = 2
        while folders.contains(where: { $0.name == name }) {
            name = "새 폴더 \(counter)"
            counter += 1
        }

        let newFolder = Folder(name: name)
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
                // launchd도 동기화
                if updatedJob.isEnabled {
                    try? launchd.updateJob(updatedJob)
                }
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

    /// 폴더 내 Job 수
    func jobCount(for folder: Folder) -> Int {
        jobs.filter { $0.folder == folder.name }.count
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
        runningJobIDs.insert(job.id)
        showToast("'\(job.name)' 실행 중...")

        executor.executeJob(job) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.runningJobIDs.remove(job.id)

                switch result {
                case .success:
                    self.showToast("'\(job.name)' 완료")
                case .failure(let error):
                    self.showToast("'\(job.name)' 실패: \(error.localizedDescription)")
                }
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

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message {
                toastMessage = nil
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
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Codable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
