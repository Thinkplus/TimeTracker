import 'package:flutter/material.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../services/google_calendar_service.dart';
import '../services/notification_service.dart';
import '../models/activity_log.dart';
import '../models/category.dart';
import '../utils/categorizer.dart';
import 'settings_screen.dart';
import 'reports_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dbService = DatabaseService();
  final _calendarService = GoogleCalendarService();
  final _notificationService = NotificationService();
  
  Timer? _timer;
  int _intervalMinutes = 60; // 기본값 60분
  DateTime? _lastReminderTime;
  
  List<ActivityLog> _todayLogs = [];
  Map<String, int> _todayStats = {};
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTodayData();
    _startTimer();
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _intervalMinutes = prefs.getInt('reminder_interval') ?? 60;
    });
  }
  
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _intervalMinutes), (timer) {
      _triggerReminder();
    });
  }
  
  Future<void> _triggerReminder() async {
    _lastReminderTime = DateTime.now();
    await _notificationService.showActivityReminderNotification();
    _showInputDialog();
  }
  
  Future<void> _loadTodayData() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final logs = await _dbService.getActivityLogsByDateRange(startOfDay, endOfDay);
    final stats = await _dbService.getCategoryStats(startOfDay, endOfDay);
    
    setState(() {
      _todayLogs = logs;
      _todayStats = stats;
    });
  }
  
  void _showInputDialog() {
    final contentController = TextEditingController();
    String selectedCategory = '업무';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('활동 기록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: contentController,
                decoration: const InputDecoration(
                  labelText: '무엇을 하셨나요?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<Category>>(
                future: _dbService.getAllCategories(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  final categories = snapshot.data!;
                  return DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: '카테고리',
                      border: OutlineInputBorder(),
                    ),
                    items: categories.map((cat) {
                      return DropdownMenuItem(
                        value: cat.name,
                        child: Row(
                          children: [
                            Icon(
                              IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons'),
                              color: Color(int.parse(cat.color.substring(1), radix: 16) + 0xFF000000),
                            ),
                            const SizedBox(width: 8),
                            Text(cat.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedCategory = value!;
                      });
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final content = contentController.text.trim();
                if (content.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('내용을 입력해주세요')),
                  );
                  return;
                }
                
                // 자동 분류 (사용자가 선택하지 않았다면)
                final categories = await _dbService.getAllCategories();
                final autoCategory = Categorizer.categorize(content, categories);
                
                final log = ActivityLog()
                  ..timestamp = _lastReminderTime ?? DateTime.now().subtract(Duration(minutes: _intervalMinutes))
                  ..content = content
                  ..category = selectedCategory
                  ..durationMinutes = _intervalMinutes;
                
                await _dbService.saveActivityLog(log);
                
                // Google Calendar에 동기화
                if (_calendarService.isSignedIn) {
                  final prefs = await SharedPreferences.getInstance();
                  final calendarId = prefs.getString('selected_calendar_id');
                  if (calendarId != null) {
                    final eventId = await _calendarService.createEventFromActivityLog(log, calendarId);
                    if (eventId != null) {
                      log.googleEventId = eventId;
                      log.syncedToCalendar = true;
                      await _dbService.saveActivityLog(log);
                    }
                  }
                }
                
                Navigator.of(context).pop();
                _loadTodayData();
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Growth Clock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.assessment),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReportsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadSettings();
              _startTimer(); // 설정이 변경되었을 수 있으므로 타이머 재시작
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 오늘의 통계 카드
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 (${DateFormat('yyyy-MM-dd').format(DateTime.now())})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (_todayStats.isEmpty)
                    const Text('아직 기록된 활동이 없습니다.')
                  else
                    ..._todayStats.entries.map((entry) {
                      final hours = entry.value ~/ 60;
                      final minutes = entry.value % 60;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              '${hours}h ${minutes}m',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          
          // 최근 활동 목록
          Expanded(
            child: _todayLogs.isEmpty
                ? const Center(child: Text('최근 활동 기록이 없습니다.'))
                : ListView.builder(
                    itemCount: _todayLogs.length,
                    itemBuilder: (context, index) {
                      final log = _todayLogs[index];
                      return ListTile(
                        leading: Icon(
                          log.syncedToCalendar ? Icons.cloud_done : Icons.cloud_off,
                          color: log.syncedToCalendar ? Colors.green : Colors.grey,
                        ),
                        title: Text(log.content),
                        subtitle: Text(
                          '${log.category} • ${DateFormat('HH:mm').format(log.timestamp)} (${log.durationMinutes}분)',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            await _dbService.deleteActivityLog(log.id);
                            _loadTodayData();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showInputDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
