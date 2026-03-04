# 설치 가이드 / Installation Guide

## 사전 요구사항

### 1. macOS 버전
- **macOS 14.0 (Sonoma)** 이상 필요
- `@Observable` 매크로, `ContentUnavailableView` 등 최신 API 사용

### 2. Xcode
- **Xcode 15.0** 이상 필요
- App Store에서 설치: [Xcode](https://apps.apple.com/app/xcode/id497799835)

### 3. Claude Code CLI
```bash
# 설치 확인
claude --version

# 설치되어 있지 않다면
npm install -g @anthropic-ai/claude-code
```

### 4. (선택) XcodeGen
```bash
brew install xcodegen
```

---

## 빌드 방법

### 방법 1: Xcode에서 직접

```bash
# 1. 클론
git clone https://github.com/joonlab/claude-code-macos-scheduler.git
cd claude-code-macos-scheduler

# 2. Xcode에서 열기
open ClaudeScheduler.xcodeproj

# 3. Cmd + R 로 빌드 및 실행
```

### 방법 2: XcodeGen 사용

`project.yml`이 포함되어 있어 XcodeGen으로 프로젝트를 재생성할 수 있습니다.

```bash
# 1. 클론
git clone https://github.com/joonlab/claude-code-macos-scheduler.git
cd claude-code-macos-scheduler

# 2. 프로젝트 생성
xcodegen generate

# 3. Xcode에서 열기
open ClaudeScheduler.xcodeproj
```

---

## Applications에 설치

### 방법 A: Xcode Archive

1. Xcode 메뉴: `Product > Archive`
2. Archives 창에서: `Distribute App > Copy App`
3. 저장 위치 선택 후 `/Applications/`로 이동

### 방법 B: 빌드된 앱 직접 복사

```bash
# DerivedData에서 빌드된 앱 찾기
find ~/Library/Developer/Xcode/DerivedData -name "ClaudeScheduler.app" -type d 2>/dev/null

# Applications로 복사
cp -R <찾은 경로>/ClaudeScheduler.app /Applications/
```

---

## 권한 설정

앱은 **App Sandbox가 비활성화**되어 있습니다 (`ClaudeScheduler.entitlements`).
이는 다음 기능에 필요합니다:

- Claude CLI 프로세스 직접 실행 (`Process`)
- iTerm AppleScript 자동화 (`NSAppleScript`)
- `~/Library/LaunchAgents/` plist 파일 관리
- `~/Library/Application Support/` 데이터 저장

첫 실행 시 macOS가 다음 권한을 요청할 수 있습니다:
- **자동화 접근**: iTerm 제어 (iTerm 모드 사용 시)
- **파일 접근**: LaunchAgents 디렉토리

---

## 트러블슈팅

### "Claude CLI를 찾을 수 없습니다"
```bash
# Claude CLI 경로 확인
which claude

# PATH에 포함되어 있는지 확인
echo $PATH
```

앱이 찾는 경로 순서:
1. `/usr/local/bin/claude`
2. `/opt/homebrew/bin/claude`
3. `~/.claude/local/claude`
4. `/usr/bin/claude`
5. `which claude` 결과

### "개발자를 확인할 수 없습니다" 경고
```bash
# Gatekeeper 허용
xattr -cr /Applications/ClaudeScheduler.app
```

### Xcode 빌드 실패
- Signing Team이 설정되어 있는지 확인
- `project.yml`의 `DEVELOPMENT_TEAM`이 비어있으므로, Xcode에서 직접 Team을 선택해야 합니다

---

[← README](../README.md) | [사용법 →](usage.md)
