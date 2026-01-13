# Google OAuth 설정 가이드 (macOS)

TimeTracker 앱이 Google Calendar에 접근하려면 Google Cloud Console에서 OAuth 2.0 클라이언트 ID를 설정해야 합니다.

## 1. Google Cloud Console 설정

### 1.1 프로젝트 생성
1. [Google Cloud Console](https://console.cloud.google.com/) 방문
2. 상단의 "프로젝트 선택" 클릭
3. "새 프로젝트" 클릭
4. 프로젝트 이름 입력 (예: "TimeTracker")
5. "만들기" 클릭

### 1.2 Google Calendar API 활성화
1. 왼쪽 메뉴에서 "API 및 서비스" > "라이브러리" 클릭
2. 검색창에 "Google Calendar API" 입력
3. "Google Calendar API" 선택
4. "사용" 버튼 클릭

### 1.3 OAuth 동의 화면 구성
1. 왼쪽 메뉴에서 "API 및 서비스" > "OAuth 동의 화면" 클릭
2. 사용자 유형에서 "외부" 선택 (개인 사용인 경우)
3. "만들기" 클릭
4. 필수 정보 입력:
   - 앱 이름: TimeTracker
   - 사용자 지원 이메일: 본인 이메일
   - 개발자 연락처 정보: 본인 이메일
5. "저장 후 계속" 클릭
6. 범위 단계는 건너뛰기 (기본값 사용)
7. 테스트 사용자 추가:
   - 본인의 Gmail 주소 입력
   - "저장 후 계속" 클릭

### 1.4 OAuth 2.0 클라이언트 ID 생성 (macOS)

1. 왼쪽 메뉴에서 "API 및 서비스" > "사용자 인증 정보" 클릭
2. 상단의 "+ 사용자 인증 정보 만들기" 클릭
3. "OAuth 클라이언트 ID" 선택
4. 애플리케이션 유형: **"iOS"** 선택 (macOS는 iOS와 동일하게 처리)
5. 이름 입력: "TimeTracker macOS"
6. 번들 ID 입력: `com.ybsoft.timeTracker`
   - **중요**: 대소문자를 정확히 입력해야 함
7. "만들기" 클릭

## 2. 클라이언트 ID 확인

생성이 완료되면 클라이언트 ID가 표시됩니다. 이 ID는 나중에 필요하지 않지만, 설정이 올바르게 되었는지 확인하려면 다음을 확인하세요:

- 클라이언트 ID 형식: `xxxxx.apps.googleusercontent.com`
- 번들 ID: `com.ybsoft.timeTracker`

## 3. 앱 실행 및 테스트

1. 앱을 실행합니다:
   ```bash
   flutter run -d macos
   ```

2. 설정 화면으로 이동
3. "로그인" 버튼 클릭
4. 웹 브라우저가 열리면서 Google 로그인 페이지 표시
5. 구글 계정으로 로그인
6. TimeTracker가 Google Calendar에 접근하는 것을 허용
7. 브라우저가 자동으로 닫히고 앱으로 돌아옴

## 문제 해결

### "로그인 오류" 다이얼로그가 표시되는 경우

**원인**: OAuth 클라이언트 ID가 설정되지 않았거나 번들 ID가 일치하지 않음

**해결 방법**:
1. Google Cloud Console에서 OAuth 클라이언트 ID가 생성되었는지 확인
2. 번들 ID가 정확히 `com.ybsoft.timeTracker`인지 확인
3. OAuth 동의 화면의 테스트 사용자에 본인 이메일이 추가되었는지 확인
4. 앱을 완전히 종료하고 다시 실행

### 브라우저가 열리지 않는 경우

**원인**: macOS 시스템 권한 문제

**해결 방법**:
1. 시스템 환경설정 > 보안 및 개인 정보 보호
2. 앱에 필요한 권한 허용

### "This app is blocked" 메시지가 표시되는 경우

**원인**: OAuth 동의 화면이 "게시되지 않음" 상태

**해결 방법**:
- 테스트 모드에서는 본인의 구글 계정만 사용 가능합니다
- 테스트 사용자 목록에 본인 이메일을 추가했는지 확인하세요
- 개인 용도로만 사용하는 경우 게시할 필요 없습니다

## 참고 사항

- 테스트 모드의 앱은 최대 100명의 테스트 사용자만 추가 가능
- 개인용으로 사용하는 경우 앱을 게시(Publish)할 필요 없음
- OAuth 토큰은 macOS 키체인에 안전하게 저장됨
