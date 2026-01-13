import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../models/activity_log.dart';

class GoogleCalendarService {
  static final GoogleCalendarService _instance = GoogleCalendarService._internal();
  factory GoogleCalendarService() => _instance;
  GoogleCalendarService._internal();
  
  // TODO: Google Cloud Console에서 OAuth 클라이언트 ID를 발급받아 여기에 입력하세요
  // macOS: iOS 유형으로 생성하고 번들 ID는 com.ybsoft.growthClock 사용
  static const String _clientId = '432128130176-fjvaeu56dv2ngisu3h3f8kthelfcb5dl.apps.googleusercontent.com'; // 예: 'xxxxx.apps.googleusercontent.com'
  
  late final GoogleSignIn _googleSignIn;
  
  GoogleSignInAccount? _currentUser;
  cal.CalendarApi? _calendarApi;
  
  // OAuth 설정 여부 확인
  bool get isConfigured => _clientId.isNotEmpty && _clientId.contains('googleusercontent.com');
  
  // 로그인 상태 확인
  bool get isSignedIn => _currentUser != null;
  
  // 현재 사용자 정보
  GoogleSignInAccount? get currentUser => _currentUser;
  
  // 초기화 및 자동 로그인 시도
  Future<void> init() async {
    if (!isConfigured) {
      print('⚠️ Google OAuth Client ID가 설정되지 않았습니다.');
      print('📋 GOOGLE_OAUTH_SETUP.md 파일을 참고하여 설정해주세요.');
      return;
    }
    
    _googleSignIn = GoogleSignIn(
      clientId: _clientId,
      scopes: [
        cal.CalendarApi.calendarScope,
      ],
    );
    
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
    });
    
    try {
      await _googleSignIn.signInSilently();
    } catch (e) {
      print('Silent sign in failed: $e');
    }
  }
  
  // 로그인
  Future<bool> signIn() async {
    try {
      print('Starting Google Sign In...');
      final account = await _googleSignIn.signIn();
      print('Sign in result: $account');
      
      if (account != null) {
        _currentUser = account;
        print('Getting authenticated client...');
        final auth = await _googleSignIn.authenticatedClient();
        print('Auth client: $auth');
        
        if (auth != null) {
          _calendarApi = cal.CalendarApi(auth);
          print('Google Sign In successful!');
          return true;
        } else {
          print('Failed to get authenticated client');
        }
      } else {
        print('Sign in was cancelled or failed');
      }
      return false;
    } catch (e, stackTrace) {
      print('Google Sign In Error: $e');
      print('Stack trace: $stackTrace');
      rethrow; // Re-throw to let the UI handle it
    }
  }
  
  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _calendarApi = null;
  }
  
  // 인증 상태 새로고침 (앱 재활성화 시 호출)
  Future<bool> refreshAuth() async {
    if (!isConfigured) return false;
    
    try {
      // 기존 캐시된 API 무효화
      _calendarApi = null;
      
      // 자동 로그인 재시도
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentUser = account;
        final auth = await _googleSignIn.authenticatedClient();
        if (auth != null) {
          _calendarApi = cal.CalendarApi(auth);
          print('Auth refreshed successfully');
          return true;
        }
      }
      print('Auth refresh failed - no account');
      return false;
    } catch (e) {
      print('Auth refresh error: $e');
      return false;
    }
  }
  
  // Calendar API 가져오기 (토큰 갱신 포함)
  Future<cal.CalendarApi?> _getCalendarApi() async {
    if (_currentUser == null) {
      return null;
    }
    
    // 매번 새로운 인증 클라이언트 가져오기 (토큰 자동 갱신)
    try {
      final auth = await _googleSignIn.authenticatedClient();
      if (auth != null) {
        _calendarApi = cal.CalendarApi(auth);
        return _calendarApi;
      }
    } catch (e) {
      print('Failed to get authenticated client: $e');
      // 인증 실패 시 재로그인 시도
      _calendarApi = null;
    }
    
    return null;
  }
  
  // ActivityLog를 Google Calendar 이벤트로 생성
  Future<String?> createEventFromActivityLog(
    ActivityLog log,
    String calendarId,
  ) async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      final event = cal.Event()
        ..summary = '[${log.category}] ${log.content}'
        ..start = cal.EventDateTime(
          dateTime: log.timestamp,
          timeZone: 'Asia/Seoul',
        )
        ..end = cal.EventDateTime(
          dateTime: log.timestamp.add(Duration(minutes: log.durationMinutes)),
          timeZone: 'Asia/Seoul',
        )
        ..description = '자동 기록됨 (GrowthClock)';
      
      final created = await api.events.insert(event, calendarId);
      return created.id;
    } catch (e) {
      print('Error creating event: $e');
      return null;
    }
  }
  
  // 캘린더 목록 가져오기
  Future<List<cal.CalendarListEntry>> getCalendarList() async {
    final api = await _getCalendarApi();
    if (api == null) return [];
    
    try {
      final calendarList = await api.calendarList.list();
      return calendarList.items ?? [];
    } catch (e) {
      print('Error fetching calendar list: $e');
      return [];
    }
  }
  
  // 기본 캘린더 ID 가져오기
  Future<String?> getPrimaryCalendarId() async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      final calendarList = await api.calendarList.list();
      final primary = calendarList.items?.firstWhere(
        (cal) => cal.primary == true,
        orElse: () => calendarList.items!.first,
      );
      return primary?.id;
    } catch (e) {
      print('Error getting primary calendar: $e');
      return null;
    }
  }
  
  // 리포트를 캘린더 이벤트로 생성
  Future<String?> createReportEvent({
    required String title,
    required String description,
    required DateTime date,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      // 종일 이벤트로 생성
      final event = cal.Event()
        ..summary = title
        ..description = description
        ..start = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day),
        )
        ..end = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day).add(Duration(days: 1)),
        );
      
      final created = await api.events.insert(event, calendarId);
      return created.id;
    } catch (e) {
      print('Error creating report event: $e');
      return null;
    }
  }
  
  // 특정 날짜의 이벤트 가져오기
  Future<List<cal.Event>> getEventsForDate(DateTime date, String calendarId) async {
    final api = await _getCalendarApi();
    if (api == null) return [];
    
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      
      final events = await api.events.list(
        calendarId,
        timeMin: startOfDay.toUtc(),
        timeMax: endOfDay.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );
      
      return events.items ?? [];
    } catch (e) {
      print('Error fetching events: $e');
      return [];
    }
  }
  
  // 커스텀 형식으로 이벤트 생성 ([카테고리] 형식의 제목, 내용은 설명에)
  Future<String?> createEventWithCustomFormat({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      final event = cal.Event()
        ..summary = title
        ..description = description
        ..start = cal.EventDateTime(dateTime: startTime.toUtc())
        ..end = cal.EventDateTime(dateTime: endTime.toUtc());
      
      final created = await api.events.insert(event, calendarId);
      print('Event created with custom format: ${created.id}');
      return created.id;
    } catch (e) {
      print('Error creating event with custom format: $e');
      return null;
    }
  }
  
  // 이벤트 업데이트
  Future<bool> updateEvent({
    required String eventId,
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return false;
    
    try {
      final event = cal.Event()
        ..summary = title
        ..description = description
        ..start = cal.EventDateTime(dateTime: startTime.toUtc())
        ..end = cal.EventDateTime(dateTime: endTime.toUtc());
      
      await api.events.update(event, calendarId, eventId);
      print('Event updated: $eventId');
      return true;
    } catch (e) {
      print('Error updating event: $e');
      return false;
    }
  }
  
  // 이벤트 삭제
  Future<bool> deleteEvent(String eventId, String calendarId) async {
    final api = await _getCalendarApi();
    if (api == null) return false;
    
    try {
      await api.events.delete(calendarId, eventId);
      print('Event deleted: $eventId');
      return true;
    } catch (e) {
      print('Error deleting event: $e');
      return false;
    }
  }
  
  // 특정 시간대의 이벤트 찾기 (중복 방지용)
  Future<cal.Event?> findEventByTimeRange({
    required DateTime startTime,
    required DateTime endTime,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      final events = await api.events.list(
        calendarId,
        timeMin: startTime.toUtc(),
        timeMax: endTime.toUtc(),
        singleEvents: true,
      );
      
      // 정확히 같은 시간대의 이벤트 찾기
      for (var event in events.items ?? []) {
        if (event.start?.dateTime != null && event.end?.dateTime != null) {
          final eventStart = event.start!.dateTime!.toLocal();
          final eventEnd = event.end!.dateTime!.toLocal();
          
          // 시작과 끝이 정확히 일치하는 이벤트 찾기
          if (eventStart == startTime && eventEnd == endTime) {
            return event;
          }
        }
      }
      
      return null;
    } catch (e) {
      print('Error finding event: $e');
      return null;
    }
  }
  
  // 종일 일정 생성 (AI 분석 리포트용)
  Future<String?> createAllDayEvent({
    required String title,
    required String description,
    required DateTime date,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return null;
    
    try {
      final event = cal.Event()
        ..summary = title
        ..description = description
        ..start = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day),
        )
        ..end = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day).add(const Duration(days: 1)),
        );
      
      final created = await api.events.insert(event, calendarId);
      print('All-day event created: ${created.id}');
      return created.id;
    } catch (e) {
      print('Error creating all-day event: $e');
      return null;
    }
  }

  // 종일 일정 업데이트
  Future<bool> updateAllDayEvent({
    required String eventId,
    required String title,
    required String description,
    required DateTime date,
    required String calendarId,
  }) async {
    final api = await _getCalendarApi();
    if (api == null) return false;
    
    try {
      final event = cal.Event()
        ..summary = title
        ..description = description
        ..start = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day),
        )
        ..end = cal.EventDateTime(
          date: DateTime(date.year, date.month, date.day).add(const Duration(days: 1)),
        );
      
      await api.events.update(event, calendarId, eventId);
      print('All-day event updated: $eventId');
      return true;
    } catch (e) {
      print('Error updating all-day event: $e');
      return false;
    }
  }
}
