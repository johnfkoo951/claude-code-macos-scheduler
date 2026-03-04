# Claude Code macOS Scheduler

**macOS 네이티브 앱으로 Claude Code CLI를 스케줄링하고 자동 실행하는 도구**

> A native macOS app to schedule and automate Claude Code CLI tasks using launchd.

---

## 소개 / Overview

Claude Code Scheduler는 Claude Code CLI를 **정해진 시간에 자동으로 실행**하는 macOS 네이티브 앱입니다.
서버나 클라우드 없이 **내 Mac에서 직접** AI 자동화 파이프라인을 구축할 수 있습니다.

### 주요 기능

- **launchd 기반 스케줄링** — 앱이 꺼져 있어도 macOS가 알아서 실행
- **3가지 스케줄 모드** — 간격(매 N분), 매일 특정 시간, 매주 특정 요일
- **2가지 실행 모드** — 백그라운드(자동) / iTerm(실시간 확인)
- **폴더 분류** — Job을 폴더로 정리 (색상 커스터마이징)
- **메뉴 바 아이콘** — 빠른 접근 및 즉시 실행
- **실행 로그** — Job별 로그 자동 저장 및 아카이브

<!-- 스크린샷 자리
![Main Window](docs/assets/screenshot-main.png)
-->

---

## 아키텍처 / Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    ClaudeSchedulerApp                         │
│              (@main, WindowGroup + MenuBarExtra)              │
└───────────────────────────┬──────────────────────────────────┘
                            │ .environment(viewModel)
┌───────────────────────────▼──────────────────────────────────┐
│                      JobViewModel                             │
│                     (@Observable)                             │
│  jobs, folders, selectedJobIDs, filteredJobs                  │
└──────┬────────────────────┬────────────────────┬─────────────┘
       │                    │                    │
┌──────▼──────┐   ┌────────▼────────┐   ┌──────▼──────────┐
│  Storage    │   │    Launchd      │   │   Executor      │
│  Service    │   │    Service      │   │   Service       │
│             │   │                 │   │                 │
│ jobs.json   │   │ ~/Library/      │   │ Process()       │
│ folders.json│   │ LaunchAgents/   │   │ (background)    │
│ Logs/       │   │ *.plist         │   │                 │
│             │   │                 │   │ NSAppleScript   │
│ ~/Library/  │   │ launchctl       │   │ (iTerm)         │
│ Application │   │ load/unload     │   │                 │
│ Support/    │   │                 │   │ claude CLI      │
└─────────────┘   └─────────────────┘   └─────────────────┘
```

### UI 구조

```
┌─ Sidebar ──┬─── Job List (Table) ───┬─── Job Detail ──────────┐
│            │                        │                          │
│ 전체       │  ☑ Job Name  Schedule  │  Section: 기본 정보      │
│ ─────────  │  ☐ Job Name  Schedule  │    이름 / 폴더 선택      │
│ Default    │  ☑ Job Name  Schedule  │  Section: 프롬프트       │
│ Gmail      │                        │    TextEditor            │
│ Work       │                        │  Section: 스케줄         │
│            │                        │    SchedulePicker        │
│ [+] [-]   │                        │  Section: 옵션           │
│            │                        │    활성화 / 백그라운드    │
│            │                        │  [즉시 실행] [삭제]      │
└────────────┴────────────────────────┴──────────────────────────┘
```

---

## 기술 스택 / Tech Stack

| 항목 | 기술 |
|------|------|
| **언어** | Swift 5.9 |
| **UI** | SwiftUI (NavigationSplitView, Table, MenuBarExtra) |
| **패턴** | MVVM + Service Layer |
| **상태 관리** | @Observable (Observation framework) + Combine |
| **스케줄링** | macOS launchd (LaunchAgents) |
| **빌드** | XcodeGen (`project.yml`) |
| **최소 요구** | macOS 14.0 (Sonoma) |
| **아키텍처** | arm64 (Apple Silicon) |
| **외부 의존성** | 없음 (순수 Apple 프레임워크) |

---

## 빌드 및 설치 / Build & Install

### 사전 요구사항

- macOS 14.0 (Sonoma) 이상
- Xcode 15.0 이상
- Claude Code CLI 설치됨 (`claude --version`으로 확인)

### 방법 1: Xcode에서 직접 빌드

```bash
git clone https://github.com/johnfkoo951/claude-code-macos-scheduler.git
cd claude-code-macos-scheduler
open ClaudeScheduler.xcodeproj
```

Xcode에서 `Cmd + R`로 빌드 및 실행.

### 방법 2: XcodeGen 사용 (선택)

```bash
brew install xcodegen
xcodegen generate
open ClaudeScheduler.xcodeproj
```

### 앱을 Applications에 설치

Xcode에서 빌드 후:
1. `Product > Archive`
2. `Distribute App > Copy App`
3. `/Applications/`로 복사

또는 빌드된 `.app`을 직접 복사:
```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeScheduler-*/Build/Products/Debug/ClaudeScheduler.app /Applications/
```

---

## 사용법 / Usage

### 1. Job 생성

앱 실행 → 툴바의 `+` 버튼 → Job 편집 폼에서:

- **이름**: Job 이름 입력
- **프롬프트**: Claude에게 전달할 프롬프트 작성
- **스케줄**: 간격 / 매일 / 매주 중 선택
- **실행 모드**: 백그라운드 또는 iTerm
- **활성화**: 토글 ON으로 스케줄 등록

### 2. 스케줄 모드

| 모드 | 설명 | 예시 |
|------|------|------|
| **간격** | 매 N초/분/시간마다 실행 | 매 30분 |
| **매일** | 매일 지정된 시간에 실행 | 매일 09:00 |
| **매주** | 매주 지정된 요일+시간 | 매주 월요일 09:00 |

### 3. 실행 모드

| 모드 | 설명 | 적합한 상황 |
|------|------|------------|
| **백그라운드** | 화면 없이 자동 실행, 로그에 기록 | 자동화, 스케줄 실행 |
| **iTerm** | iTerm에 새 탭을 열어 실행 과정 표시 | 디버깅, 실시간 모니터링 |

### 4. 메뉴 바

메뉴 바의 달력 아이콘에서:
- 활성화된 Job 목록 확인
- 즉시 실행 버튼
- 앱 열기 / 종료

---

## 데이터 저장 위치

```
~/Library/Application Support/ClaudeScheduler/
├── jobs.json          # Job 목록
├── folders.json       # 폴더 목록
├── executor.sh        # Claude CLI 실행 스크립트
└── Logs/
    └── <job-uuid>/
        ├── latest.log           # 최근 실행 로그
        └── 2026-02-04_012512.log  # 아카이브 로그
```

스케줄 등록 위치:
```
~/Library/LaunchAgents/com.claude.scheduler.<job-uuid>.plist
```

---

## GitHub Actions 버전과의 비교

| 비교 항목 | 이 프로젝트 (로컬) | [GitHub Actions 버전](https://github.com/joonlab/claude-code-with-github-actions) |
|-----------|:------------------:|:------------------:|
| **실행 환경** | 내 Mac | GitHub 서버 |
| **비용** | 무료 (전기세만) | 무료 (2000분/월) |
| **항상 실행** | Mac 켜져있어야 함 | 24/7 (GitHub 서버) |
| **MCP 서버** | 로컬 MCP 사용 가능 | Chrome DevTools 등 |
| **실행 모드** | Background / iTerm | Background only |
| **로그 확인** | 앱 내 + 로컬 파일 | GitHub Actions 로그 |
| **네트워크** | 로컬 리소스 접근 가능 | GitHub runner 환경만 |
| **적합 용도** | 개인 자동화, 로컬 파일 처리 | CI/CD, 공개 프로젝트 자동화 |

---

## 프로젝트 구조

```
claude-code-macos-scheduler/
├── project.yml                      # XcodeGen 프로젝트 정의
├── ClaudeScheduler.xcodeproj/       # Xcode 프로젝트
└── ClaudeScheduler/
    ├── ClaudeSchedulerApp.swift     # 앱 엔트리포인트 + MenuBarView
    ├── ClaudeScheduler.entitlements # 앱 권한 (샌드박스 OFF)
    ├── Models/
    │   ├── Job.swift                # Job + Schedule enum
    │   └── Folder.swift             # Folder + Color hex 확장
    ├── Services/
    │   ├── ExecutorService.swift    # Claude CLI 실행 (Process / AppleScript)
    │   ├── LaunchdService.swift     # launchd plist 생성/로드/언로드
    │   └── StorageService.swift     # JSON 파일 CRUD + 로그 관리
    ├── ViewModels/
    │   └── JobViewModel.swift       # @Observable MVVM ViewModel
    └── Views/
        ├── ContentView.swift        # 3-column NavigationSplitView
        ├── JobDetailView.swift      # Job 편집 Form
        ├── JobListView.swift        # Table 기반 Job 목록
        ├── SidebarView.swift        # 폴더 사이드바
        └── Components/
            └── SchedulePicker.swift # 스케줄 설정 컴포넌트
```

---

## 문서 / Documentation

| 문서 | 설명 |
|------|------|
| [Installation Guide](docs/installation.md) | 상세 설치 가이드 |
| [Usage Guide](docs/usage.md) | 사용법 상세 설명 |
| [Architecture](docs/architecture.md) | 아키텍처 및 코드 구조 설명 |

---

## 관련 프로젝트

- [claude-code-with-github-actions](https://github.com/joonlab/claude-code-with-github-actions) — GitHub Actions를 활용한 서버리스 Claude Code 스케줄러

---

## License

MIT License - [LICENSE](LICENSE)

---

<p align="center">
  <sub>Built with Swift + SwiftUI for macOS</sub>
</p>
