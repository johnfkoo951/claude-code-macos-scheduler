import Foundation
import AppKit

/// Claude CLI 명령을 실행하는 서비스
final class ExecutorService {
    static let shared = ExecutorService()

    private let fileManager = FileManager.default

    /// Claude CLI 경로
    private var claudePath: String {
        // 여러 가능한 경로 확인
        let possiblePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(fileManager.homeDirectoryForCurrentUser.path)/.claude/local/claude",
            "/usr/bin/claude"
        ]

        for path in possiblePaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // which 명령으로 찾기
        if let path = findClaudeWithWhich() {
            return path
        }

        // 기본값
        return "/usr/local/bin/claude"
    }

    private init() {}

    // MARK: - Public Methods

    /// Job 즉시 실행
    @discardableResult
    func executeJob(_ job: Job, completion: ((Result<String, ExecutorError>) -> Void)? = nil) -> Bool {
        if job.runInBackground {
            return executeInBackground(job: job, completion: completion)
        } else {
            return executeInITerm(job: job, completion: completion)
        }
    }

    /// 백그라운드 모드로 실행
    func executeInBackground(job: Job, completion: ((Result<String, ExecutorError>) -> Void)? = nil) -> Bool {
        let logPath = StorageService.shared.logFilePath(for: job)

        // 로그 파일 헤더 작성
        let header = """
        === ClaudeScheduler Job Execution ===
        Job ID: \(job.id.uuidString)
        Job Name: \(job.name)
        Mode: Background
        Time: \(Date())
        ======================================

        Prompt: \(job.prompt)

        --- Output ---

        """

        fileManager.createFile(atPath: logPath.path, contents: header.data(using: .utf8))

        // 비동기로 실행
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.claudePath)
            process.arguments = ["--dangerously-skip-permissions", "-p", job.prompt]

            // 환경 변수 설정
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:\(environment["PATH"] ?? "")"
            process.environment = environment

            // 출력을 로그 파일에 append
            let logHandle: FileHandle
            do {
                logHandle = try FileHandle(forWritingTo: logPath)
                logHandle.seekToEndOfFile()
            } catch {
                completion?(.failure(.logFileError(error.localizedDescription)))
                return
            }

            process.standardOutput = logHandle
            process.standardError = logHandle

            do {
                try process.run()
                process.waitUntilExit()

                // 종료 로그 작성
                let footer = """

                --- End of Output ---
                Exit Code: \(process.terminationStatus)
                End Time: \(Date())
                """
                logHandle.write(footer.data(using: .utf8) ?? Data())
                try? logHandle.close()

                // lastRunAt 업데이트
                DispatchQueue.main.async {
                    StorageService.shared.updateLastRunAt(jobId: job.id)
                }

                if process.terminationStatus == 0 {
                    completion?(.success(logPath.path))
                } else {
                    completion?(.failure(.executionFailed(Int(process.terminationStatus))))
                }

            } catch {
                try? logHandle.close()
                completion?(.failure(.processError(error.localizedDescription)))
            }
        }

        return true
    }

    /// iTerm에서 새 탭으로 실행
    func executeInITerm(job: Job, completion: ((Result<String, ExecutorError>) -> Void)? = nil) -> Bool {
        // 프롬프트 이스케이프
        let escapedPrompt = job.prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "'\\''")

        let claudePath = self.claudePath

        let script = """
        tell application "iTerm"
            activate

            -- 윈도우가 없으면 새로 생성
            if (count of windows) = 0 then
                create window with default profile
            end if

            tell current window
                -- 새 탭 생성
                create tab with default profile

                tell current session
                    -- 헤더 출력
                    write text "echo ''"
                    write text "echo '=== ClaudeScheduler Job Execution ==='"
                    write text "echo 'Job: \(job.name)'"
                    write text "echo 'Time: '$(date)"
                    write text "echo '======================================'"
                    write text "echo ''"

                    -- Claude 실행
                    write text "\(claudePath) --dangerously-skip-permissions -p '\(escapedPrompt)'"
                end tell
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                print("[ExecutorService] AppleScript error: \(errorMessage)")
                completion?(.failure(.appleScriptError(errorMessage)))
                return false
            }

            // lastRunAt 업데이트
            StorageService.shared.updateLastRunAt(jobId: job.id)

            completion?(.success("Executed in iTerm"))
            return true
        }

        completion?(.failure(.appleScriptError("Failed to create AppleScript")))
        return false
    }

    /// iTerm에서 실행하고 완료 후 탭 닫기
    func executeInITermAndClose(job: Job, completion: ((Result<String, ExecutorError>) -> Void)? = nil) -> Bool {
        let escapedPrompt = job.prompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "'\\''")

        let claudePath = self.claudePath

        // 완료 후 탭 닫기를 위한 스크립트
        let script = """
        tell application "iTerm"
            activate

            if (count of windows) = 0 then
                create window with default profile
            end if

            tell current window
                create tab with default profile

                tell current session
                    write text "echo '=== ClaudeScheduler Job: \(job.name) ==='"
                    write text "\(claudePath) --dangerously-skip-permissions -p '\(escapedPrompt)' && echo '' && echo '=== Job Completed ===' && sleep 2 && exit"
                end tell
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)

            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                completion?(.failure(.appleScriptError(errorMessage)))
                return false
            }

            StorageService.shared.updateLastRunAt(jobId: job.id)
            completion?(.success("Executed in iTerm (will close on completion)"))
            return true
        }

        completion?(.failure(.appleScriptError("Failed to create AppleScript")))
        return false
    }

    /// Claude CLI 존재 여부 확인
    func isClaudeAvailable() -> Bool {
        fileManager.isExecutableFile(atPath: claudePath)
    }

    /// Claude CLI 경로 반환
    func getClaudePath() -> String {
        claudePath
    }

    /// Claude 버전 확인
    func getClaudeVersion() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Private Methods

    /// which 명령으로 claude 찾기
    private func findClaudeWithWhich() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // ignore
        }

        return nil
    }
}

// MARK: - Errors
enum ExecutorError: LocalizedError {
    case claudeNotFound
    case executionFailed(Int)
    case processError(String)
    case appleScriptError(String)
    case logFileError(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude CLI not found. Please ensure it's installed and in your PATH."
        case .executionFailed(let exitCode):
            return "Execution failed with exit code: \(exitCode)"
        case .processError(let message):
            return "Process error: \(message)"
        case .appleScriptError(let message):
            return "AppleScript error: \(message)"
        case .logFileError(let message):
            return "Log file error: \(message)"
        }
    }
}

// MARK: - Execution Result
struct ExecutionResult {
    let jobId: UUID
    let startTime: Date
    let endTime: Date
    let exitCode: Int
    let logPath: String?

    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    var isSuccess: Bool {
        exitCode == 0
    }
}
