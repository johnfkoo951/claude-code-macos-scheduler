import Foundation

/// 앱 데이터를 로컬 파일시스템에 저장/로드하는 서비스
@MainActor
@Observable
final class StorageService {
    static let shared = StorageService()

    // MARK: - Observable Properties
    private(set) var jobs: [Job] = []
    private(set) var folders: [Folder] = []

    // MARK: - Private Properties
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 앱 데이터 저장 디렉토리 (observation 추적 제외)
    @ObservationIgnored
    private(set) var appSupportDirectory: URL!

    /// 로그 디렉토리 (observation 추적 제외)
    @ObservationIgnored
    private(set) var logsDirectory: URL!

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

        // 디렉토리 초기화
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("ClaudeScheduler", isDirectory: true)
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        appSupportDirectory = appSupport

        let logs = appSupport.appendingPathComponent("Logs", isDirectory: true)
        if !fileManager.fileExists(atPath: logs.path) {
            try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        }
        logsDirectory = logs

        loadAll()
    }

    // MARK: - Load Methods

    func loadAll() {
        loadFolders()
        loadJobs()
    }

    private func loadJobs() {
        guard fileManager.fileExists(atPath: jobsFileURL.path) else {
            jobs = []
            return
        }

        do {
            let data = try Data(contentsOf: jobsFileURL)
            jobs = try decoder.decode([Job].self, from: data)
        } catch {
            print("[StorageService] Failed to load jobs: \(error)")
            jobs = []
        }
    }

    private func loadFolders() {
        guard fileManager.fileExists(atPath: foldersFileURL.path) else {
            folders = [Folder.defaultFolder]
            saveFolders()
            return
        }

        do {
            let data = try Data(contentsOf: foldersFileURL)
            folders = try decoder.decode([Folder].self, from: data)

            if !folders.contains(where: { $0.name == "Default" }) {
                folders.insert(Folder.defaultFolder, at: 0)
                saveFolders()
            }
        } catch {
            print("[StorageService] Failed to load folders: \(error)")
            folders = [Folder.defaultFolder]
            saveFolders()
        }
    }

    // MARK: - Save Methods

    private func saveJobs() {
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: jobsFileURL, options: .atomic)
        } catch {
            print("[StorageService] Failed to save jobs: \(error)")
        }
    }

    private func saveFolders() {
        do {
            let data = try encoder.encode(folders)
            try data.write(to: foldersFileURL, options: .atomic)
        } catch {
            print("[StorageService] Failed to save folders: \(error)")
        }
    }

    // MARK: - Job CRUD Operations

    func addJob(_ job: Job) {
        jobs.append(job)
        saveJobs()
    }

    func updateJob(_ job: Job) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
            saveJobs()
        }
    }

    func deleteJob(_ job: Job) {
        jobs.removeAll { $0.id == job.id }
        saveJobs()
    }

    func updateLastRunAt(jobId: UUID, date: Date = Date()) {
        if let index = jobs.firstIndex(where: { $0.id == jobId }) {
            jobs[index].lastRunAt = date
            saveJobs()
        }
    }

    // MARK: - Folder CRUD Operations

    func addFolder(_ folder: Folder) {
        guard !folders.contains(where: { $0.name == folder.name }) else { return }
        folders.append(folder)
        saveFolders()
    }

    func updateFolder(_ folder: Folder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            if folders[index].name == "Default" && folder.name != "Default" { return }
            folders[index] = folder
            saveFolders()
        }
    }

    func deleteFolder(_ folder: Folder) {
        guard folder.name != "Default" else { return }

        for index in jobs.indices where jobs[index].folder == folder.name {
            jobs[index].folder = "Default"
        }
        saveJobs()

        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }

    // MARK: - Log File Management

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    func logFilePath(for job: Job) -> URL {
        let timestamp = Self.logDateFormatter.string(from: Date())
        let jobLogsDir = logsDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: jobLogsDir.path) {
            try? fileManager.createDirectory(at: jobLogsDir, withIntermediateDirectories: true)
        }
        return jobLogsDir.appendingPathComponent("\(timestamp).log")
    }

    func logFiles(for job: Job) -> [URL] {
        let jobLogsDir = logsDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: jobLogsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func cleanupOldLogs(daysToKeep: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()
        guard let jobDirs = try? fileManager.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for jobDir in jobDirs {
            guard let logFiles = try? fileManager.contentsOfDirectory(
                at: jobDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for logFile in logFiles {
                guard let attributes = try? fileManager.attributesOfItem(atPath: logFile.path),
                      let creationDate = attributes[.creationDate] as? Date,
                      creationDate < cutoffDate else { continue }
                try? fileManager.removeItem(at: logFile)
            }
        }
    }
}
