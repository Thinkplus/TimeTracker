import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  bool _initialized = false;
  
  Future<void> init() async {
    if (_initialized) return;
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const macSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    
    // 권한 요청
    await _requestPermissions();
    
    _initialized = true;
  }
  
  Future<void> _requestPermissions() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      
      await _notifications
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } else if (Platform.isAndroid) {
      final androidImplementation = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
    }
  }
  
  // 알림 탭 핸들러
  void _onNotificationTapped(NotificationResponse response) async {
    print('Notification tapped: ${response.payload}');
    
    // 데스크톱 환경에서 창 표시 및 포커스
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.show();
      await windowManager.focus();
    }
  }
  
  // 즉시 알림 표시
  Future<void> showActivityReminderNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'activity_reminder',
      'Activity Reminder',
      channelDescription: '활동 기록 알림',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const macDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: macDetails,
    );
    
    await _notifications.show(
      0,
      '활동 기록',
      '지난 시간 동안 무엇을 하셨나요?',
      details,
      payload: 'activity_log',
    );
  }
  
  // 정기 알림 스케줄링 (간단한 예시 - 실제로는 Timer나 Workmanager 사용)
  // Flutter Local Notifications의 periodic은 15분 단위이므로, 
  // 실제 구현은 Timer(Desktop) 또는 Workmanager(Mobile) 사용 예정
}
