# TimeTracker

매 시간마다 사용자에게 알림을 보내 활동을 기록하고, 구글 캘린더에 자동으로 동기화하는 Flutter 애플리케이션입니다.

## 주요 기능

- ⏰ **설정 가능한 주기 알림**: 사용자가 설정한 간격(15분~180분)으로 활동 기록 알림
- 📝 **활동 자동 분류**: 키워드 기반 자동 카테고리 분류
- 📅 **구글 캘린더 연동**: 기록된 활동을 자동으로 구글 캘린더에 저장
- 📊 **시각화된 리포트**: 일별/주별/월별 활동 통계 및 차트
- 🏷️ **사용자 정의 카테고리**: 카테고리와 키워드를 직접 관리
- 💾 **로컬 데이터베이스**: Isar를 사용한 빠른 로컬 저장

## 지원 플랫폼

- ✅ macOS
- ✅ Windows
- ✅ Android
- ✅ iOS

## 시작하기

### 필수 요구사항

- Flutter SDK 3.10.4 이상
- Google Cloud Platform 프로젝트 (Google Calendar API 사용을 위함)

### Google Cloud 설정

TimeTracker는 Google Calendar API를 사용합니다. 다음 단계를 따라 설정하세요:

1. [Google Cloud Console](https://console.cloud.google.com/)에서 새 프로젝트 생성
2. Google Calendar API 활성화
3. OAuth 2.0 클라이언트 ID 생성:
   - **Android**: SHA-1 인증서 지문 필요
   - **iOS**: Bundle ID 필요
   - **macOS**: Bundle ID 필요
   - **Windows**: 웹 애플리케이션 클라이언트 ID 필요

#### Android 설정

1. SHA-1 인증서 지문 얻기:
   ```bash
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore
   # 기본 비밀번호: android
   ```

2. Google Cloud Console에서 Android OAuth 클라이언트 ID 생성 시 SHA-1 입력

3. `android/app/build.gradle.kts` 파일에 applicationId 확인:
   ```kotlin
   defaultConfig {
       applicationId = "com.ybsoft.time_tracker"
       // ...
   }
   ```

#### iOS 설정

1. `ios/Runner/Info.plist` 파일에 다음 추가:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleTypeRole</key>
           <string>Editor</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
           </array>
       </dict>
   </array>
   ```

2. Bundle Identifier를 Google Cloud Console에 등록

#### macOS 설정

1. `macos/Runner/Info.plist` 파일에 다음 추가:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleTypeRole</key>
           <string>Editor</string>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
           </array>
       </dict>
   </array>
   ```

2. 네트워크 권한 활성화:
   - Xcode에서 macOS Runner 열기
   - Signing & Capabilities 탭
   - "Outgoing Connections (Client)" 체크

### 설치 및 실행

1. 의존성 설치:
   ```bash
   flutter pub get
   ```

2. Isar 코드 생성 (이미 완료됨):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

3. 실행:
   ```bash
   # macOS
   flutter run -d macos
   
   # Windows
   flutter run -d windows
   
   # Android
   flutter run -d <device-id>
   
   # iOS
   flutter run -d <device-id>
   ```

## 사용 방법

### 초기 설정

1. 앱 실행 후 **설정** 아이콘 클릭
2. **Google Calendar** 섹션에서 **로그인** 버튼 클릭
3. 구글 계정으로 로그인 및 권한 승인
4. **대상 캘린더** 선택
5. **알림 간격** 조정 (15분~180분)

### 활동 기록

1. 설정한 간격마다 알림이 표시됩니다
2. 알림을 클릭하거나 메인 화면의 **+** 버튼을 눌러 활동 입력
3. 활동 내용과 카테고리 선택 (자동 분류도 가능)
4. **저장** 버튼을 클릭하면 로컬 DB와 구글 캘린더에 기록됩니다

### 카테고리 관리

1. **설정** > **카테고리 관리**
2. 기본 카테고리: 업무, 개인, 휴식
3. **+** 버튼으로 새 카테고리 추가
4. 각 카테고리마다 키워드 설정 가능 (쉼표로 구분)
   - 예: "회의,미팅,작업" → 입력한 내용에 이 키워드가 있으면 자동으로 해당 카테고리로 분류

### 리포트 확인

1. 메인 화면 상단의 **리포트** 아이콘 클릭
2. **일별/주별/월별** 탭에서 통계 확인
3. 파이 차트로 카테고리별 시간 분포 시각화
4. **이 리포트를 캘린더에 저장** 버튼으로 일일 요약을 캘린더에 기록 가능

## 프로젝트 구조

```
lib/
├── main.dart                    # 앱 진입점
├── models/                      # 데이터 모델
│   ├── activity_log.dart        # 활동 기록 모델
│   └── category.dart            # 카테고리 모델
├── services/                    # 비즈니스 로직
│   ├── database_service.dart    # Isar DB 관리
│   ├── google_calendar_service.dart  # Google Calendar API
│   └── notification_service.dart     # 로컬 알림
├── screens/                     # UI 화면
│   ├── home_screen.dart         # 메인 화면
│   ├── settings_screen.dart     # 설정 화면
│   └── reports_screen.dart      # 리포트 화면
└── utils/                       # 유틸리티
    └── categorizer.dart         # 자동 분류 로직
```

## 기술 스택

- **Flutter**: 크로스 플랫폼 UI 프레임워크
- **Isar**: 고성능 로컬 데이터베이스
- **Google Sign-In**: 구글 인증
- **Google Calendar API**: 캘린더 이벤트 관리
- **fl_chart**: 데이터 시각화
- **flutter_local_notifications**: 플랫폼별 알림
- **window_manager**: 데스크톱 창 관리

## 문제 해결

### Google Sign-In이 작동하지 않는 경우

- OAuth 클라이언트 ID가 올바르게 설정되었는지 확인
- Android: SHA-1 인증서 지문이 정확한지 확인
- iOS/macOS: Info.plist에 URL Scheme이 추가되었는지 확인
- 캐시 삭제 후 재빌드: `flutter clean && flutter pub get`

### 알림이 표시되지 않는 경우

- 시스템 설정에서 앱 알림 권한이 허용되었는지 확인
- Android: 배터리 최적화 해제
- iOS/macOS: 알림 권한 요청 승인

### 빌드 오류

```bash
# 캐시 삭제
flutter clean

# 의존성 재설치
flutter pub get

# Isar 코드 재생성
dart run build_runner build --delete-conflicting-outputs
```

## 라이선스

이 프로젝트는 개인용으로 개발되었습니다.

## 개발자

ybsoft - TimeTracker Project
