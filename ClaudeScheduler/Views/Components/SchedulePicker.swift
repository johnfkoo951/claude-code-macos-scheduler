import SwiftUI

struct SchedulePicker: View {
    @Binding var schedule: Schedule

    @State private var scheduleType: ScheduleType = .interval
    @State private var intervalValue: Int = 60
    @State private var intervalUnit: IntervalUnit = .minutes
    @State private var dailyTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var weeklyTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var selectedWeekday: Int = 1  // 월요일

    enum ScheduleType: String, CaseIterable {
        case interval = "간격"
        case daily = "매일"
        case weekly = "매주"
    }

    enum IntervalUnit: String, CaseIterable {
        case seconds = "초"
        case minutes = "분"
        case hours = "시간"

        var multiplier: Int {
            switch self {
            case .seconds: return 1
            case .minutes: return 60
            case .hours: return 3600
            }
        }
    }

    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 스케줄 타입 선택
            Picker("타입", selection: $scheduleType) {
                ForEach(ScheduleType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // 타입별 설정 UI
            switch scheduleType {
            case .interval:
                intervalPicker
            case .daily:
                dailyPicker
            case .weekly:
                weeklyPicker
            }

            // 다음 실행 시간 표시
            if let nextFire = schedule.nextFireDate() {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.blue)
                    Text("다음 실행: \(nextFire, formatter: Self.dateFormatter)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            loadFromSchedule()
        }
        .onChange(of: scheduleType) { _, _ in updateSchedule() }
        .onChange(of: intervalValue) { _, _ in updateSchedule() }
        .onChange(of: intervalUnit) { _, _ in updateSchedule() }
        .onChange(of: dailyTime) { _, _ in updateSchedule() }
        .onChange(of: weeklyTime) { _, _ in updateSchedule() }
        .onChange(of: selectedWeekday) { _, _ in updateSchedule() }
    }

    // MARK: - Interval Picker

    private var intervalPicker: some View {
        HStack {
            Text("매")

            Stepper(value: $intervalValue, in: 1...999) {
                TextField("", value: $intervalValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
            }

            Picker("", selection: $intervalUnit) {
                ForEach(IntervalUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .labelsHidden()
            .frame(width: 70)

            Text("마다")

            Spacer()
        }
    }

    // MARK: - Daily Picker

    private var dailyPicker: some View {
        HStack {
            Text("매일")

            DatePicker("", selection: $dailyTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .frame(width: 100)

            Text("에 실행")

            Spacer()
        }
    }

    // MARK: - Weekly Picker

    private var weeklyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("매주")

                Picker("", selection: $selectedWeekday) {
                    ForEach(0..<7, id: \.self) { index in
                        Text("\(weekdays[index])요일").tag(index)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                DatePicker("", selection: $weeklyTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 100)

                Text("에 실행")

                Spacer()
            }

            // 요일 빠른 선택 버튼
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Button {
                        selectedWeekday = index
                    } label: {
                        Text(weekdays[index])
                            .font(.caption)
                            .frame(width: 28, height: 28)
                            .background(selectedWeekday == index ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundStyle(selectedWeekday == index ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func loadFromSchedule() {
        switch schedule {
        case .interval(let seconds):
            scheduleType = .interval
            if seconds >= 3600 && seconds % 3600 == 0 {
                intervalUnit = .hours
                intervalValue = seconds / 3600
            } else if seconds >= 60 && seconds % 60 == 0 {
                intervalUnit = .minutes
                intervalValue = seconds / 60
            } else {
                intervalUnit = .seconds
                intervalValue = seconds
            }

        case .daily(let hour, let minute):
            scheduleType = .daily
            dailyTime = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()

        case .weekly(let weekday, let hour, let minute):
            scheduleType = .weekly
            selectedWeekday = weekday
            weeklyTime = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        }
    }

    private func updateSchedule() {
        switch scheduleType {
        case .interval:
            let totalSeconds = intervalValue * intervalUnit.multiplier
            schedule = .interval(seconds: max(1, totalSeconds))

        case .daily:
            let components = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            schedule = .daily(hour: components.hour ?? 9, minute: components.minute ?? 0)

        case .weekly:
            let components = Calendar.current.dateComponents([.hour, .minute], from: weeklyTime)
            schedule = .weekly(
                weekday: selectedWeekday,
                hour: components.hour ?? 9,
                minute: components.minute ?? 0
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()
}

#Preview {
    struct PreviewWrapper: View {
        @State var schedule: Schedule = .interval(seconds: 3600)

        var body: some View {
            Form {
                Section("스케줄 설정") {
                    SchedulePicker(schedule: $schedule)
                }

                Section("현재 값") {
                    Text(schedule.displayText)
                }
            }
            .formStyle(.grouped)
            .frame(width: 400, height: 300)
        }
    }

    return PreviewWrapper()
}
