import Foundation

/// launchd를 통해 스케줄된 작업을 관리하는 서비스
final class LaunchdService {
    static let shared = LaunchdService()

    private let fileManager = FileManager.default
    private let plistPrefix = "com.claude.scheduler"

    /// LaunchAgents 디렉토리 경로
    private var launchAgentsDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    /// 앱 실행 경로 (ExecutorService 스크립트를 호출하기 위한 wrapper)
    private var executorScriptPath: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("ClaudeScheduler/executor.sh")
    }

    private init() {
        ensureExecutorScriptExists()
    }

    // MARK: - Plist File Management

    /// Job ID에 해당하는 plist 파일 경로
    private func plistPath(for jobId: UUID) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(plistPrefix).\(jobId.uuidString).plist")
    }

    /// 해당 Job의 launchd label
    private func label(for jobId: UUID) -> String {
        "\(plistPrefix).\(jobId.uuidString)"
    }

    // MARK: - Public Methods

    /// Job에 대한 launchd plist 생성 및 로드
    func registerJob(_ job: Job) throws {
        // plist 생성
        let plistContent = generatePlist(for: job)
        let plistURL = plistPath(for: job.id)

        // 기존 plist가 있으면 먼저 언로드
        if fileManager.fileExists(atPath: plistURL.path) {
            try? unloadPlist(for: job.id)
        }

        // plist 파일 쓰기
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        print("[LaunchdService] Created plist: \(plistURL.path)")

        // Job이 활성화되어 있으면 로드
        if job.isEnabled {
            try loadPlist(for: job.id)
        }
    }

    /// Job의 launchd plist 삭제 및 언로드
    func unregisterJob(_ job: Job) throws {
        try unregisterJob(id: job.id)
    }

    /// Job ID로 launchd plist 삭제 및 언로드
    func unregisterJob(id: UUID) throws {
        let plistURL = plistPath(for: id)

        // 언로드
        try? unloadPlist(for: id)

        // 파일 삭제
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
            print("[LaunchdService] Removed plist: \(plistURL.path)")
        }
    }

    /// Job 활성화 (plist 로드)
    func enableJob(_ job: Job) throws {
        // plist가 없으면 생성
        let plistURL = plistPath(for: job.id)
        if !fileManager.fileExists(atPath: plistURL.path) {
            try registerJob(job)
            return
        }

        try loadPlist(for: job.id)
    }

    /// Job 비활성화 (plist 언로드 및 파일 삭제)
    func disableJob(_ job: Job) throws {
        let plistURL = plistPath(for: job.id)

        // 언로드
        try unloadPlist(for: job.id)

        // 파일 삭제 (재부팅 시 자동 로드 방지)
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
            print("[LaunchdService] Removed plist on disable: \(plistURL.path)")
        }
    }

    /// Job 스케줄 업데이트
    func updateJob(_ job: Job) throws {
        try registerJob(job)
    }

    /// 현재 로드된 상태 확인
    func isJobLoaded(_ job: Job) -> Bool {
        isJobLoaded(id: job.id)
    }

    func isJobLoaded(id: UUID) -> Bool {
        let label = label(for: id)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 모든 ClaudeScheduler 관련 launchd 작업 목록
    func listAllJobs() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return output
                .components(separatedBy: .newlines)
                .filter { $0.contains(plistPrefix) }
                .compactMap { line -> String? in
                    let components = line.components(separatedBy: .whitespaces)
                    return components.last
                }
        } catch {
            return []
        }
    }

    // MARK: - Private Methods

    /// plist 내용 생성
    private func generatePlist(for job: Job) -> String {
        let label = label(for: job.id)
        // 고정된 로그 경로 사용 (타임스탬프 로그는 executor.sh에서 생성)
        let logDir = StorageService.shared.logsDirectory.appendingPathComponent(job.id.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logPath = logDir.appendingPathComponent("latest.log").path

        // 스케줄에 따른 StartCalendarInterval 또는 StartInterval 설정
        let scheduleConfig: String
        switch job.schedule {
        case .interval(let seconds):
            scheduleConfig = """
                <key>StartInterval</key>
                <integer>\(seconds)</integer>
            """

        case .daily(let hour, let minute):
            scheduleConfig = """
                <key>StartCalendarInterval</key>
                <dict>
                    <key>Hour</key>
                    <integer>\(hour)</integer>
                    <key>Minute</key>
                    <integer>\(minute)</integer>
                </dict>
            """

        case .weekly(let weekday, let hour, let minute):
            scheduleConfig = """
                <key>StartCalendarInterval</key>
                <dict>
                    <key>Weekday</key>
                    <integer>\(weekday)</integer>
                    <key>Hour</key>
                    <integer>\(hour)</integer>
                    <key>Minute</key>
                    <integer>\(minute)</integer>
                </dict>
            """
        }

        // 프롬프트에서 특수문자 이스케이프
        let escapedPrompt = job.prompt
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")

        let runMode = job.runInBackground ? "background" : "iterm"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(executorScriptPath.path)</string>
                <string>\(job.id.uuidString)</string>
                <string>\(runMode)</string>
                <string>\(escapedPrompt)</string>
            </array>

            \(scheduleConfig)

            <key>StandardOutPath</key>
            <string>\(logPath)</string>

            <key>StandardErrorPath</key>
            <string>\(logPath)</string>

            <key>RunAtLoad</key>
            <false/>

            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
            </dict>
        </dict>
        </plist>
        """
    }

    /// plist 로드
    private func loadPlist(for jobId: UUID) throws {
        let plistURL = plistPath(for: jobId)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw LaunchdError.loadFailed(errorMessage)
        }

        print("[LaunchdService] Loaded: \(label(for: jobId))")
    }

    /// plist 언로드
    private func unloadPlist(for jobId: UUID) throws {
        let plistURL = plistPath(for: jobId)

        guard fileManager.fileExists(atPath: plistURL.path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        // 언로드는 이미 언로드된 상태여도 에러가 아님
        print("[LaunchdService] Unloaded: \(label(for: jobId))")
    }

    /// Executor 스크립트 생성 (앱 최초 실행 시)
    private func ensureExecutorScriptExists() {
        let scriptDir = executorScriptPath.deletingLastPathComponent()

        // 디렉토리 생성
        if !fileManager.fileExists(atPath: scriptDir.path) {
            try? fileManager.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        }

        // 스크립트 내용
        let scriptContent = """
        #!/bin/bash
        # ClaudeScheduler Executor Script
        # Usage: executor.sh <job-id> <mode> <prompt>
        # mode: "background" or "iterm"

        JOB_ID="$1"
        MODE="$2"
        PROMPT="$3"

        LOG_DIR="$HOME/Library/Application Support/ClaudeScheduler/Logs/$JOB_ID"
        LATEST_LOG="$LOG_DIR/latest.log"
        TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
        ARCHIVE_LOG="$LOG_DIR/${TIMESTAMP}.log"

        # 로그 디렉토리 생성
        mkdir -p "$LOG_DIR"

        # Claude CLI 경로 찾기
        CLAUDE_PATH=$(which claude 2>/dev/null || echo "/usr/local/bin/claude")

        if [ ! -x "$CLAUDE_PATH" ]; then
            CLAUDE_PATH="$HOME/.claude/local/claude"
        fi

        if [ ! -x "$CLAUDE_PATH" ]; then
            echo "Error: claude CLI not found"
            exit 1
        fi

        echo "=== ClaudeScheduler Job Execution ==="
        echo "Job ID: $JOB_ID"
        echo "Mode: $MODE"
        echo "Time: $(date)"
        echo "======================================"
        echo ""

        if [ "$MODE" = "background" ]; then
            # 백그라운드 모드: 직접 실행
            "$CLAUDE_PATH" --dangerously-skip-permissions -p "$PROMPT"
        else
            # iTerm 모드: AppleScript로 iTerm 탭에서 실행
            osascript <<EOF
        tell application "iTerm"
            activate

            -- 새 탭 생성 또는 기존 윈도우 사용
            if (count of windows) = 0 then
                create window with default profile
            end if

            tell current window
                create tab with default profile
                tell current session
                    write text "echo '=== ClaudeScheduler Job: $JOB_ID ==='"
                    write text "$CLAUDE_PATH --dangerously-skip-permissions -p \\"$PROMPT\\""
                end tell
            end tell
        end tell
        EOF
        fi

        echo ""
        echo "=== Job Completed ==="
        echo "End Time: $(date)"

        # latest.log를 타임스탬프 로그로 복사 (아카이브)
        if [ -f "$LATEST_LOG" ]; then
            cp "$LATEST_LOG" "$ARCHIVE_LOG"
        fi
        """

        // 스크립트 파일 쓰기
        do {
            try scriptContent.write(to: executorScriptPath, atomically: true, encoding: .utf8)

            // 실행 권한 부여
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executorScriptPath.path)

            print("[LaunchdService] Executor script created: \(executorScriptPath.path)")
        } catch {
            print("[LaunchdService] Failed to create executor script: \(error)")
        }
    }
}

// MARK: - Errors
enum LaunchdError: LocalizedError {
    case loadFailed(String)
    case unloadFailed(String)
    case plistCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Failed to load launchd job: \(message)"
        case .unloadFailed(let message):
            return "Failed to unload launchd job: \(message)"
        case .plistCreationFailed(let message):
            return "Failed to create plist: \(message)"
        }
    }
}
