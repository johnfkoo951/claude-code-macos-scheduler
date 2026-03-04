import Foundation

struct Job: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var prompt: String
    var folder: String
    var schedule: Schedule
    var isEnabled: Bool
    var runInBackground: Bool  // true = 백그라운드, false = iTerm 창
    var createdAt: Date
    var lastRunAt: Date?

    init(id: UUID = UUID(), name: String, prompt: String, folder: String = "Default", schedule: Schedule, isEnabled: Bool = true, runInBackground: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.folder = folder
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.runInBackground = runInBackground
        self.createdAt = createdAt
    }
}

enum Schedule: Codable, Hashable {
    case interval(seconds: Int)  // 매 N초마다
    case daily(hour: Int, minute: Int)  // 매일 특정 시간
    case weekly(weekday: Int, hour: Int, minute: Int)  // 매주 특정 요일+시간 (0=일요일)

    var displayText: String {
        switch self {
        case .interval(let seconds):
            if seconds < 60 { return "매 \(seconds)초" }
            if seconds < 3600 { return "매 \(seconds/60)분" }
            return "매 \(seconds/3600)시간"
        case .daily(let hour, let minute):
            return "매일 \(String(format: "%02d:%02d", hour, minute))"
        case .weekly(let weekday, let hour, let minute):
            let days = ["일", "월", "화", "수", "목", "금", "토"]
            return "매주 \(days[weekday])요일 \(String(format: "%02d:%02d", hour, minute))"
        }
    }

    /// 다음 실행 시간 계산
    func nextFireDate(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current

        switch self {
        case .interval(let seconds):
            return date.addingTimeInterval(TimeInterval(seconds))

        case .daily(let hour, let minute):
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let targetDate = calendar.date(from: components) else { return nil }

            // 이미 지났으면 다음 날로
            if targetDate <= date {
                return calendar.date(byAdding: .day, value: 1, to: targetDate)
            }
            return targetDate

        case .weekly(let weekday, let hour, let minute):
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let baseDate = calendar.date(from: components) else { return nil }

            let currentWeekday = calendar.component(.weekday, from: date) - 1  // 0-indexed (일=0)
            var daysToAdd = weekday - currentWeekday

            if daysToAdd < 0 || (daysToAdd == 0 && baseDate <= date) {
                daysToAdd += 7
            }

            return calendar.date(byAdding: .day, value: daysToAdd, to: baseDate)
        }
    }
}
