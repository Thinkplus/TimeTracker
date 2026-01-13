import 'package:flutter/material.dart';
import 'dart:async';
import 'main_screen.dart';
import '../services/database_service.dart';
import '../services/google_calendar_service.dart';
import '../services/notification_service.dart';
import '../services/system_tray_service.dart';
import '../services/llm_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. 최소 로딩 시간 (로고 노출용)
    final minDelay = Future.delayed(const Duration(seconds: 2));
    
    // 2. 서비스 초기화
    final initBatch = Future(() async {
      try {
        await DatabaseService().isar;
        await DatabaseService().createDefaultCategories();
        
        // 중요치 않은 서비스는 실패해도 진행
        try { await GoogleCalendarService().init(); } catch (e) { debugPrint('Calendar init error: $e'); }
        try { await NotificationService().init(); } catch (e) { debugPrint('Notification init error: $e'); }
        try { await SystemTrayService().init(); } catch (e) { debugPrint('SystemTray init error: $e'); }
        try { await LLMService().init(); } catch (e) { debugPrint('LLM init error: $e'); }
        
      } catch (e) {
        debugPrint('Critical initialization error: $e');
      }
    });

    // 로딩과 초기화 동시 진행 및 대기
    await Future.wait([minDelay, initBatch]);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC), // 연한 배경색
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // 로고 카드
            Center(
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.05),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(30),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 48),
            // 앱 이름
            const Text(
              'Growth Clock',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E293B), // 진한 네이비/블랙
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            // 서브 타이틀
            const Text(
              'Personal Time Tracker',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B), // 회색
              ),
            ),
            const Spacer(flex: 1),
            // 로딩 인디케이터 섹션
            Column(
              children: [
                const Text(
                  'LOADING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3B82F6), // 메인 블루
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 200,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0), // 연한 회색 배경
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: const LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
            // 버전 정보
            const Text(
              'V1.0',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8), // 연한 회색
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
