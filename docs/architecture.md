# 아키텍처 / Architecture

## 전체 구조

MVVM (Model-View-ViewModel) + Service Layer 패턴을 사용합니다.

```
┌─────────────────────────────────────────────────┐
│                     Views                        │
│  ContentView, SidebarView, JobListView,          │
│  JobDetailView, SchedulePicker, MenuBarView      │
└──────────────────────┬──────────────────────────┘
                       │ @Environment
┌──────────────────────▼──────────────────────────┐
│                  JobViewModel                    │
│              (@Observable class)                 │
│                                                  │
│  jobs, folders, selectedJobIDs                   │
│  filteredJobs, addJob(), deleteJob(), runJob()   │
└───────┬──────────────┬──────────────┬───────────┘
        │ Combine sink │              │
┌───────▼───────┐ ┌────▼──────┐ ┌────▼──────────┐
│ StorageService│ │ Launchd   │ │ Executor      │
│  (Singleton)  │ │ Service   │ │ Service       │
│               │ │(Singleton)│ │ (Singleton)   │
│ @Published    │ │           │ │               │
│ jobs/folders  │ │ plist CRUD│ │ Process()     │
│ JSON I/O     │ │ launchctl │ │ AppleScript   │
│ Log mgmt    │ │           │ │               │
└───────────────┘ └───────────┘ └───────────────┘
```

---

## 데이터 흐름

### 읽기 (Load)
```
StorageService.loadJobs()
  → @Published jobs 업데이트
    → Combine sink
      → JobViewModel.jobs 업데이트
        → SwiftUI View 자동 갱신
```

### 쓰기 (Save)
```
View에서 필드 변경 (onChange)
  → JobViewModel.updateJob()
    → StorageService.updateJob()
      → jobs.json 파일 쓰기
      → @Published jobs 업데이트
    → LaunchdService.registerJob() (활성화 상태 변경 시)
```

### 스케줄 실행
```
macOS launchd (시스템 레벨)
  → executor.sh 실행
    → claude CLI 찾기
    → claude --dangerously-skip-permissions -p "<prompt>"
    → 결과를 로그 파일에 기록
```

---

## 파일별 역할

### Models

#### `Job.swift`
- `Job` struct: Identifiable, Codable, Hashable
- `Schedule` enum: interval / daily / weekly (Codable)
- `displayText`: 한글 스케줄 표시 ("매 30분", "매일 09:00")
- `nextFireDate(from:)`: 다음 실행 시간 계산

#### `Folder.swift`
- `Folder` struct: id, name, color (hex)
- `Color(hex:)` 확장: 6자리/8자리 hex 지원
- `presetColors`: 9가지 프리셋 색상

### Services

#### `StorageService.swift`
- **역할**: JSON 파일 기반 데이터 영속화
- **저장 위치**: `~/Library/Application Support/ClaudeScheduler/`
- **파일**: jobs.json, folders.json
- **인코딩**: prettyPrinted, sortedKeys, iso8601
- **로그 관리**: Job별 UUID 디렉토리, 30일 자동 정리
- `ObservableObject` + `@Published`로 데이터 변경 발행

#### `LaunchdService.swift`
- **역할**: macOS launchd를 통한 스케줄 관리
- **plist 위치**: `~/Library/LaunchAgents/com.claude.scheduler.<id>.plist`
- **executor.sh**: Claude CLI 찾기 + 실행 + 로그 기록
- `launchctl load/unload`로 등록/해제
- Schedule enum에 따라 `StartInterval` 또는 `StartCalendarInterval` 설정

#### `ExecutorService.swift`
- **역할**: Claude CLI 직접 실행
- **Background 모드**: `Process`로 실행, stdout/stderr 캡처
- **iTerm 모드**: `NSAppleScript`로 iTerm 새 탭 열기
- Claude CLI 경로 자동 탐색 (4개 경로 + which)

### ViewModel

#### `JobViewModel.swift`
- `@Observable` 매크로 (Swift Observation framework)
- StorageService의 `@Published` 프로퍼티를 Combine `sink`로 구독
- `filteredJobs`: 선택된 폴더 기준 필터링
- Job/Folder CRUD + LaunchdService 자동 연동
- 벌크 작업 지원 (다중 선택)

### Views

#### `ContentView.swift`
- 3-column `NavigationSplitView`
- 사이드바 폭: 180-250pt
- 콘텐츠 폭: 350-600pt
- 디테일 최소 폭: 300pt
- 툴바: 추가(+), 삭제, 실행 버튼

#### `SidebarView.swift`
- "전체" + 폴더 Section 구성
- 더블클릭 inline 이름 변경
- Default 폴더 보호 (삭제/변경 불가)

#### `JobListView.swift`
- `Table` 기반 다중 선택
- 컬럼: 활성화, 이름, 스케줄, 폴더, 실행방식, 최종실행
- 컨텍스트 메뉴 + 더블클릭 즉시 실행

#### `JobDetailView.swift`
- 상태별 분기: 단일/다중/미선택
- `JobEditForm`: Form .grouped 스타일
- 모든 필드 `onChange` 자동 저장

#### `SchedulePicker.swift`
- Segmented Picker: 간격/매일/매주
- 간격: Stepper + 단위 선택
- 매일: DatePicker (시:분)
- 매주: 요일 Circle 버튼 + DatePicker

---

## 스케줄링 메커니즘

### launchd plist 구조

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.scheduler.{job-uuid}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>~/Library/Application Support/ClaudeScheduler/executor.sh</string>
        <string>{job-uuid}</string>
        <string>{mode}</string>
        <string>{prompt}</string>
    </array>

    <!-- 간격 모드 -->
    <key>StartInterval</key>
    <integer>1800</integer>

    <!-- 또는 매일/매주 모드 -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
        <!-- 매주인 경우 -->
        <key>Weekday</key><integer>1</integer>
    </dict>

    <key>RunAtLoad</key>
    <false/>

    <key>StandardOutPath</key>
    <string>~/Library/Application Support/ClaudeScheduler/Logs/{uuid}/latest.log</string>

    <key>StandardErrorPath</key>
    <string>~/Library/Application Support/ClaudeScheduler/Logs/{uuid}/latest.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
```

### 앱이 꺼져 있을 때의 동작

launchd는 **macOS 시스템 레벨 데몬**이므로:
- 앱이 꺼져 있어도 등록된 plist는 유효
- Mac이 켜져 있으면 예약 시간에 executor.sh 실행
- Mac이 잠자기 상태였다면, 깨어난 후 실행

---

[← 사용법](usage.md) | [README →](../README.md)
