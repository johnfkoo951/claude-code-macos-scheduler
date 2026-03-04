import Foundation
import Combine

/// 앱 데이터를 로컬 파일시스템에 저장/로드하는 서비스
final class StorageService: ObservableObject {
    static let shared = StorageService()

    // MARK: - Published Properties
    @Published private(set) var jobs: [Job] = []
    @Published private(set) var folders: [Folder] = []

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 앱 데이터 저장 디렉토리
    private var appSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("ClaudeScheduler", isDirectory: true)

        // 디렉토리가 없으면 생성
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        return appSupport
    }

    /// 로그 디렉토리
    var logsDirectory: URL {
        let logs = appSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
        if !fileManager.fileExists(atPath: logs.path) {
            try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        }
        return logs
    }

    private var jobsFileURL: URL {
        appSupportDirectory.appendingPathComponent("jobs.json")
    }

    private var foldersFileURL: URL {
        appSupportDirectory.appendingPathComponent("folders.json")
    }

    // MARK: - Initialization
    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        loadAll()
    }

    // MARK: - Load Methods

    /// 모든 데이터 로드
    func loadAll() {
        loadFolders()
        loadJobs()
    }

    /// Jobs 로드
    private func loadJobs() {
        guard fileManager.fileExists(atPath: jobsFileURL.path) else {
            jobs = []
            return
        }

        do {
            let data = try Data(contentsOf: jobsFileURL)
            jobs = try decoder.decode([Job].self, from: data)
            print("[StorageService] Loaded \(jobs.count) jobs")
        } catch {
            print("[StorageService] Failed to load jobs: \(error)")
            jobs = []
        }
    }

    /// Folders 로드
    private func loadFolders() {
        guard fileManager.fileExists(atPath: foldersFileURL.path) else {
            // 기본 폴더 생성
            folders = [Folder.defaultFolder]
            saveFolders()
            return
        }

        do {
            let data = try Data(contentsOf: foldersFileURL)
            folders = try decoder.decode([Folder].self, from: data)

            // Default 폴더가 없으면 추가
            if !folders.contains(where: { $0.name == "Default" }) {
                folders.insert(Folder.defaultFolder, at: 0)
                saveFolders()
            }

            print("[StorageService] Loaded \(folders.count) folders")
        } catch {
            print("[StorageService] Failed to load folders: \(error)")
            folders = [Folder.defaultFolder]
            saveFolders()
        }
    }

    // MARK: - Save Methods

    /// Jobs 저장
    private func saveJobs() {
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: jobsFileURL, options: .atomic)
            print("[StorageService] Saved \(jobs.count) jobs")
        } catch {
            print("[StorageService] Failed to save jobs: \(error)")
        }
    }

    /// Folders 저장
    private func saveFolders() {
        do {
            let data = try encoder.encode(folders)
            try data.write(to: foldersFileURL, options: .atomic)
            print("[StorageService] Saved \(folders.count) folders")
        } catch {
            print("[StorageService] Failed to save folders: \(error)")
        }
    }

    // MARK: - Job CRUD Operations

    /// Job 추가
    func addJob(_ job: Job) {
        jobs.append(job)
        saveJobs()
    }

    /// Job 업데이트
    func updateJob(_ job: Job) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
            saveJobs()
        }
    }

    /// Job 삭제
    func deleteJob(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        saveJobs()
    }

    /// Job 삭제 (ID로)
    func deleteJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        saveJobs()
    }

    /// Job의 lastRunAt 업데이트
    func updateLastRunAt(jobId: UUID, date: Date = Date()) {
        if let index = jobs.firstIndex(where: { $0.id == jobId }) {
            jobs[index].lastRunAt = date
            saveJobs()
        }
    }

    /// Job 활성화/비활성화 토글
    func toggleJobEnabled(jobId: UUID) {
        if let index = jobs.firstIndex(where: { $0.id == jobId }) {
            jobs[index].isEnabled.toggle()
            saveJobs()
        }
    }

    /// 특정 폴더의 Jobs 조회
    func jobs(inFolder folderName: String) -> [Job] {
        jobs.filter { $0.folder == folderName }
    }

    /// 활성화된 Jobs만 조회
    var enabledJobs: [Job] {
        jobs.filter { $0.isEnabled }
    }

    // MARK: - Folder CRUD Operations

    /// Folder 추가
    func addFolder(_ folder: Folder) {
        // 중복 이름 방지
        guard !folders.contains(where: { $0.name == folder.name }) else {
            print("[StorageService] Folder with name '\(folder.name)' already exists")
            return
        }
        folders.append(folder)
        saveFolders()
    }

    /// Folder 업데이트
    func updateFolder(_ folder: Folder) {
        // Default 폴더는 이름 변경 불가
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            if folders[index].name == "Default" && folder.name != "Default" {
                print("[StorageService] Cannot rename Default folder")
                return
            }
            folders[index] = folder
            saveFolders()
        }
    }

    /// Folder 삭제
    func deleteFolder(_ folder: Folder) {
        // Default 폴더는 삭제 불가
        guard folder.name != "Default" else {
            print("[StorageService] Cannot delete Default folder")
            return
        }

        // 해당 폴더의 Jobs를 Default로 이동
        for index in jobs.indices where jobs[index].folder == folder.name {
            jobs[index].folder = "Default"
        }
        saveJobs()

        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }

    /// 폴더명으로 Folder 조회
    func folder(named name: String) -> Folder? {
        folders.first { $0.name == name }
    }

    // MARK: - Log File Management

    /// Job 실행 로그 파일 경로 생성
    func logFilePath(for job: Job) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let jobLogsDir = logsDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: jobLogsDir.path) {
            try? fileManager.createDirectory(at: jobLogsDir, withIntermediateDirectories: true)
        }

        return jobLogsDir.appendingPathComponent("\(timestamp).log")
    }

    /// 특정 Job의 로그 파일 목록 조회
    func logFiles(for job: Job) -> [URL] {
        let jobLogsDir = logsDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(
            at: jobLogsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }  // 최신순
    }

    /// 오래된 로그 파일 정리 (30일 이상)
    func cleanupOldLogs(daysToKeep: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()

        guard let jobDirs = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for jobDir in jobDirs {
            guard let logFiles = try? fileManager.contentsOfDirectory(
                at: jobDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for logFile in logFiles {
                guard let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
                      let creationDate = attributes[.creationDate] as? Date,
                      creationDate < cutoffDate else { continue }

                try? fileManager.removeItem(at: logFile)
                print("[StorageService] Removed old log: \(logFile.lastPathComponent)")
            }
        }
    }
}
