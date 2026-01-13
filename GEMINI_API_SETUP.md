# Gemini API 설정 가이드

TimeTracker 앱의 AI 기반 카테고리 자동 분류 기능을 사용하려면 Google Gemini API 키가 필요합니다.

## 🔑 Gemini API 키 발급 방법

### 1. Google AI Studio 접속
[https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)

### 2. API 키 생성
1. **"Create API key"** 버튼 클릭
2. 프로젝트 선택 또는 새 프로젝트 생성
3. API 키 복사

### 3. API 키를 앱에 설정

1. `lib/services/llm_service.dart` 파일 열기
2. 5번째 줄의 `_apiKey` 상수에 발급받은 키 입력:

```dart
static const String _apiKey = '여기에_발급받은_API_키_입력';
```

예시:
```dart
static const String _apiKey = 'AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
```

### 4. 앱 다시 시작

API 키를 설정한 후 앱을 다시 시작하면 AI 기반 카테고리 분류 기능이 활성화됩니다.

## 🎯 AI 카테고리 분류 기능

### 작동 방식
1. 활동 내용을 5글자 이상 입력하면 자동으로 AI 분석 시작
2. AI가 입력한 내용을 분석하여 가장 적절한 카테고리 자동 선택
3. 사용자가 원하면 카테고리를 수동으로 변경 가능

### API 키가 설정되지 않은 경우
- AI 분석 기능은 비활성화됩니다
- 카테고리는 수동으로 선택해야 합니다
- 다른 모든 기능은 정상적으로 작동합니다

## 💰 Gemini API 무료 할당량

- **무료 티어**: 분당 15 요청, 일일 1,500 요청
- 개인 사용에는 충분한 할당량입니다
- 자세한 내용: [Google AI Pricing](https://ai.google.dev/pricing)

## 🔒 보안 참고사항

⚠️ **중요**: API 키는 민감한 정보입니다!

- 프로덕션 환경에서는 환경 변수나 안전한 저장소 사용 권장
- 개인 프로젝트에서는 코드에 직접 입력해도 무방
- GitHub 등에 코드를 공유할 때는 API 키를 제거하세요

---

## 문제 해결

### "API 키가 설정되지 않았습니다" 메시지가 표시되는 경우
1. `lib/services/llm_service.dart` 파일의 `_apiKey` 확인
2. 빈 문자열(`''`)이 아닌 실제 API 키가 입력되었는지 확인
3. 앱을 완전히 재시작 (Hot Reload가 아닌 완전 재시작)

### AI 분석이 작동하지 않는 경우
1. 인터넷 연결 확인
2. Gemini API 키가 유효한지 확인
3. API 할당량을 초과하지 않았는지 확인

---

이제 활동을 입력할 때 AI가 자동으로 적절한 카테고리를 추천해드립니다! 🚀
