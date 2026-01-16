import 'package:flutter/material.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../services/google_calendar_service.dart';
import '../services/notification_service.dart';
import '../services/llm_service.dart';
import '../models/activity_log.dart';
import '../models/category.dart';
import '../utils/categorizer.dart';
import 'settings_screen.dart';
import 'reports_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/calendar/v3.dart' as cal;

class CalendarHomeScreen extends StatefulWidget {
  const CalendarHomeScreen({super.key});

  @override
  State<CalendarHomeScreen> createState() => CalendarHomeScreenState();
}

class CalendarHomeScreenState extends State<CalendarHomeScreen> with WidgetsBindingObserver {
  final _dbService = DatabaseService();
  final _calendarService = GoogleCalendarService();
  final _notificationService = NotificationService();
  
  Timer? _timer;
  int _intervalMinutes = 60;
  DateTime? _lastReminderTime;
  DateTime _selectedDate = DateTime.now();
  
  List<cal.Event> _calendarEvents = [];
  String? _selectedCalendarId;
  bool _isLoadingEvents = false;
  bool _hasInitialized = false; // 초기화 완료 플래그
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cleanupAndInit();
    _startTimer();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱이 resumed될 때 (알림 클릭 포함) 인증 갱신 후 데이터 새로고침
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed - refreshing auth and data');
      if (mounted) {
        _refreshAndLoad();
      }
    }
  }
  
  Future<void> _refreshAndLoad() async {
    // 인증 상태 갱신 (토큰 갱신 포함)
    if (_calendarService.isSignedIn) {
      await _calendarService.refreshAuth();
    }
    // 데이터 로드
    await _loadCalendarEvents();
  }
  
  Future<void> _cleanupAndInit() async {
    if (_hasInitialized) return; // 이미 초기화되었으면 스킵
    
    // 중복 카테고리 제거
    await _dbService.cleanupDuplicateCategories();
    // 설정 로드
    await _loadSettings();
    
    _hasInitialized = true;
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _intervalMinutes = prefs.getInt('reminder_interval') ?? 60;
      _selectedCalendarId = prefs.getString('selected_calendar_id');
    });
    
    if (_selectedCalendarId != null) {
      _loadCalendarEvents();
    }
  }
  
  Future<void> _loadCalendarEvents() async {
    if (_selectedCalendarId == null || !_calendarService.isSignedIn) {
      setState(() {
        _calendarEvents = [];
      });
      return;
    }
    
    setState(() {
      _isLoadingEvents = true;
    });
    
    try {
      final events = await _calendarService.getEventsForDate(
        _selectedDate,
        _selectedCalendarId!,
      );
      
      setState(() {
        _calendarEvents = events;
        _isLoadingEvents = false;
      });
    } catch (e) {
      print('Error loading calendar events: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load events: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadCalendarEvents,
            ),
          ),
        );
      }
      setState(() {
        _isLoadingEvents = false;
      });
    }
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
    showInputDialog();
  }
  
  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadCalendarEvents();
  }
  
  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadCalendarEvents();
  }
  
  // 시간을 설정된 간격으로 내림 (예: 09:27 -> 09:00 if interval is 60)
  DateTime _roundDownToInterval(DateTime time) {
    final minutes = time.minute;
    final roundedMinutes = (minutes ~/ _intervalMinutes) * _intervalMinutes;
    return DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      roundedMinutes,
    );
  }
  
  void showInputDialog({
    DateTime? initialTime, 
    DateTime? eventStartTime,
    String? eventTitle,
    String? eventDescription,
    bool isNewRecord = true,  // 새 기록인지 기존 기록 편집인지 구분
  }) async {
    final now = DateTime.now();
    DateTime currentEndTime;
    DateTime currentStartTime;
    DateTime selectedDate = _selectedDate;
    
    if (initialTime != null && eventStartTime != null) {
      currentStartTime = eventStartTime;
      currentEndTime = initialTime;
    } else if (initialTime != null) {
      currentEndTime = initialTime;
      currentStartTime = currentEndTime.subtract(Duration(minutes: _intervalMinutes));
    } else {
      currentEndTime = _roundDownToInterval(_lastReminderTime ?? now);
      currentStartTime = currentEndTime.subtract(Duration(minutes: _intervalMinutes));
    }
    
    // 새 기록일 때는 기존 로그를 불러오지 않음
    ActivityLog? existingLog;
    if (!isNewRecord) {
      existingLog = await _dbService.getActivityLogInTimeRange(
        currentStartTime,
        currentEndTime,
      );
    }
    
    String? categoryFromEvent;
    if (eventTitle != null) {
      final match = RegExp(r'\[(.+?)\]').firstMatch(eventTitle);
      if (match != null) {
        categoryFromEvent = match.group(1);
      }
    }
    
    final contentController = TextEditingController(
      text: existingLog?.content ?? eventDescription ?? ''
    );
    String? selectedCategory = existingLog?.category ?? categoryFromEvent;
    String? aiSuggestedCategory;
    bool isAnalyzing = false;
    
    // Timer for debounce AI suggestion
    Timer? debounceTimer;
    final focusNode = FocusNode();
    
    // AI category suggestion function
    Future<void> suggestCategoryFromContent(void Function(void Function()) setDialogState) async {
      final content = contentController.text.trim();
      if (content.length < 3 || isAnalyzing) return;
      
      setDialogState(() => isAnalyzing = true);
      
      final categories = await _dbService.getAllCategories();
      final llmService = LLMService();
      
      if (llmService.isConfigured) {
        final suggestion = await llmService.suggestCategory(content, categories);
        setDialogState(() {
          isAnalyzing = false;
          if (suggestion != null) {
            aiSuggestedCategory = suggestion;
            selectedCategory = suggestion; // Always update to AI suggestion
          }
        });
      } else {
        setDialogState(() => isAnalyzing = false);
      }
    }
    
    // Setup focus listener
    bool focusListenerAdded = false;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Add focus listener once
          if (!focusListenerAdded) {
            focusListenerAdded = true;
            focusNode.addListener(() {
              if (!focusNode.hasFocus) {
                // Focus lost - trigger AI suggestion
                debounceTimer?.cancel();
                suggestCategoryFromContent(setDialogState);
              }
            });
          }
          
          final duration = currentEndTime.difference(currentStartTime);
          final hours = duration.inHours;
          final minutes = duration.inMinutes % 60;
          final durationText = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel'),
                        style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Log Time',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      // 삭제 버튼 (기존 로그가 있거나 이벤트 수정인 경우에만 표시)
                      if (existingLog != null || eventTitle != null)
                        TextButton.icon(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('삭제 확인'),
                                content: const Text('이 활동 기록을 삭제하시겠습니까?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('취소'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('삭제'),
                                  ),
                                ],
                              ),
                            );
                            
                            if (confirm == true) {
                              // 로컬 DB에서 삭제
                              if (existingLog != null) {
                                await _dbService.deleteActivityLog(existingLog!.id);
                              }
                              
                              // Google Calendar에서 삭제
                              if (_calendarService.isSignedIn && _selectedCalendarId != null) {
                                String? eventIdToDelete = existingLog?.googleEventId;
                                
                                if (eventIdToDelete == null) {
                                  final existingCalendarEvent = await _calendarService.findEventByTimeRange(
                                    startTime: currentStartTime,
                                    endTime: currentEndTime,
                                    calendarId: _selectedCalendarId!,
                                  );
                                  eventIdToDelete = existingCalendarEvent?.id;
                                }
                                
                                if (eventIdToDelete != null) {
                                  await _calendarService.deleteEvent(
                                    eventIdToDelete,
                                    _selectedCalendarId!,
                                  );
                                }
                              }
                              
                              Navigator.of(context).pop();
                              _loadCalendarEvents();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('활동 기록이 삭제되었습니다'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('삭제'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        )
                      else
                        const SizedBox(width: 80),
                    ],
                  ),
                ),
                
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date & Time Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              // Date selector
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.chevron_left, color: Colors.grey.shade600),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedDate = selectedDate.subtract(const Duration(days: 1));
                                      });
                                    },
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.calendar_today, size: 16, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat('MMM dd, E').format(selectedDate),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.chevron_right, color: Colors.grey.shade600),
                                    onPressed: () {
                                      setDialogState(() {
                                        selectedDate = selectedDate.add(const Duration(days: 1));
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              
                              // Time pickers
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text('START', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            final time = await showTimePicker(
                                              context: context,
                                              initialTime: TimeOfDay.fromDateTime(currentStartTime),
                                            );
                                            if (time != null) {
                                              setDialogState(() {
                                                currentStartTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, time.hour, time.minute);
                                              });
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.grey.shade200),
                                            ),
                                            child: Text(
                                              DateFormat('hh:mm a').format(currentStartTime),
                                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text('END', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            final time = await showTimePicker(
                                              context: context,
                                              initialTime: TimeOfDay.fromDateTime(currentEndTime),
                                            );
                                            if (time != null) {
                                              setDialogState(() {
                                                currentEndTime = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, time.hour, time.minute);
                                              });
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.grey.shade200),
                                            ),
                                            child: Text(
                                              DateFormat('hh:mm a').format(currentEndTime),
                                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              Text('Total Duration: $durationText', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                              const SizedBox(height: 16),
                              
                              // Quick add buttons
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: ['+15m', '+30m', '+45m', '+1h'].map((label) {
                                  final mins = label == '+1h' ? 60 : int.parse(label.replaceAll('+', '').replaceAll('m', ''));
                                  return GestureDetector(
                                    onTap: () => setDialogState(() => currentEndTime = currentEndTime.add(Duration(minutes: mins))),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Details Section
                        const Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: TextField(
                            controller: contentController,
                            focusNode: focusNode,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: 'Add notes regarding this task...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
                              suffixIcon: isAnalyzing 
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : null,
                            ),
                            onChanged: (value) {
                              // Cancel previous timer
                              debounceTimer?.cancel();
                              
                              // Start new 3-second timer
                              debounceTimer = Timer(const Duration(seconds: 3), () {
                                suggestCategoryFromContent(setDialogState);
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Category Section
                        FutureBuilder<List<Category>>(
                          future: _dbService.getAllCategories(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                            
                            final categories = snapshot.data!;
                            selectedCategory ??= categories.isNotEmpty ? categories.first.name : null;
                            
                            return GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (ctx) => Container(
                                    padding: const EdgeInsets.all(16),
                                    constraints: BoxConstraints(
                                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('Select Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 16),
                                        Flexible(
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            itemCount: categories.length,
                                            itemBuilder: (context, index) {
                                              final cat = categories[index];
                                              return ListTile(
                                                leading: Icon(IconData(cat.iconCodePoint, fontFamily: 'MaterialIcons')),
                                                title: Text(cat.name),
                                                trailing: cat.name == selectedCategory ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
                                                onTap: () {
                                                  setDialogState(() => selectedCategory = cat.name);
                                                  Navigator.pop(ctx);
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.category_outlined, color: Theme.of(context).primaryColor),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(selectedCategory ?? 'Select Category', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                          Text('AI suggested category', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
                
                // Save Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final content = contentController.text.trim();
                          if (content.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add some details')));
                            return;
                          }
                          if (selectedCategory == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category')));
                            return;
                          }
                          
                          final dur = currentEndTime.difference(currentStartTime).inMinutes;
                          final log = existingLog ?? ActivityLog();
                          log.timestamp = currentStartTime;
                          log.content = content;
                          log.category = selectedCategory!;
                          log.durationMinutes = dur;
                          
                          await _dbService.saveActivityLog(log);
                          
                          if (_calendarService.isSignedIn && _selectedCalendarId != null) {
                            final llmService = LLMService();
                            final eventTitle = llmService.generateEventTitle(selectedCategory!);
                            String? existingEventId = existingLog?.googleEventId;
                            
                            if (existingEventId == null) {
                              final existingCalendarEvent = await _calendarService.findEventByTimeRange(
                                startTime: currentStartTime, endTime: currentEndTime, calendarId: _selectedCalendarId!,
                              );
                              existingEventId = existingCalendarEvent?.id;
                            }
                            
                            if (existingEventId != null) {
                              final success = await _calendarService.updateEvent(
                                eventId: existingEventId, title: eventTitle, description: content,
                                startTime: currentStartTime, endTime: currentEndTime, calendarId: _selectedCalendarId!,
                              );
                              if (success) {
                                log.googleEventId = existingEventId;
                                log.syncedToCalendar = true;
                                await _dbService.saveActivityLog(log);
                              }
                            } else {
                              final eventId = await _calendarService.createEventWithCustomFormat(
                                title: eventTitle, description: content,
                                startTime: currentStartTime, endTime: currentEndTime, calendarId: _selectedCalendarId!,
                              );
                              if (eventId != null) {
                                log.googleEventId = eventId;
                                log.syncedToCalendar = true;
                                await _dbService.saveActivityLog(log);
                              }
                            }
                          }
                          
                          Navigator.of(context).pop();
                          _loadCalendarEvents();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Activity saved: [$selectedCategory]'), backgroundColor: Colors.green),
                          );
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Save Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      // Cleanup
      debounceTimer?.cancel();
      focusNode.dispose();
      // 다이얼로그 닫힐 때 항상 데이터 갱신 (저장/취소 무관하게 최신 상태 유지)
      if (mounted) {
        _loadCalendarEvents();
      }
    });
  }
  
  String _formatEventTime(cal.Event event) {
    if (event.start?.dateTime != null) {
      final start = event.start!.dateTime!.toLocal();
      final end = event.end?.dateTime?.toLocal();
      
      if (end != null) {
        return '${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}';
      }
      return DateFormat('HH:mm').format(start);
    } else if (event.start?.date != null) {
      return '종일';
    }
    return '시간 미정';
  }
  
  Color _getCategoryColor(String title) {
    final lowerTitle = title.toLowerCase();
    
    // 카테고리별 색상 매핑
    if (lowerTitle.contains('health') || lowerTitle.contains('건강') || lowerTitle.contains('운동')) {
      return const Color(0xFF4CAF50); // Green
    } else if (lowerTitle.contains('email') || lowerTitle.contains('이메일')) {
      return const Color(0xFF9C27B0); // Purple
    } else if (lowerTitle.contains('meeting') || lowerTitle.contains('회의') || lowerTitle.contains('면담')) {
      return const Color(0xFFE91E63); // Pink
    } else if (lowerTitle.contains('break') || lowerTitle.contains('휴식')) {
      return const Color(0xFFFF9800); // Orange
    } else if (lowerTitle.contains('work') || lowerTitle.contains('업무') || lowerTitle.contains('문서')) {
      return const Color(0xFF2196F3); // Blue
    } else if (lowerTitle.contains('interview') || lowerTitle.contains('면접')) {
      return const Color(0xFFE91E63); // Pink
    } else if (lowerTitle.contains('자기계발') || lowerTitle.contains('study') || lowerTitle.contains('학습')) {
      return const Color(0xFFFF5722); // Deep Orange
    } else if (lowerTitle.contains('analysis') || lowerTitle.contains('분석')) {
      return const Color(0xFF1E88E5); // Primary Blue
    } else if (lowerTitle.contains('가족') || lowerTitle.contains('family')) {
      return const Color(0xFFE91E63); // Pink
    } else if (lowerTitle.contains('전화') || lowerTitle.contains('call') || lowerTitle.contains('phone')) {
      return const Color(0xFF00BCD4); // Cyan
    }
    
    // 기본 색상
    return const Color(0xFF1E88E5);
  }
  
  IconData _getCategoryIcon(String title) {
    final lowerTitle = title.toLowerCase();
    
    // 카테고리별 아이콘 매핑
    if (lowerTitle.contains('health') || lowerTitle.contains('건강') || lowerTitle.contains('운동')) {
      return Icons.fitness_center;
    } else if (lowerTitle.contains('email') || lowerTitle.contains('이메일')) {
      return Icons.email_outlined;
    } else if (lowerTitle.contains('meeting') || lowerTitle.contains('회의')) {
      return Icons.groups_outlined;
    } else if (lowerTitle.contains('break') || lowerTitle.contains('휴식')) {
      return Icons.restaurant_outlined;
    } else if (lowerTitle.contains('work') || lowerTitle.contains('업무')) {
      return Icons.code;
    } else if (lowerTitle.contains('interview') || lowerTitle.contains('면접') || lowerTitle.contains('면담')) {
      return Icons.person_outline;
    } else if (lowerTitle.contains('자기계발') || lowerTitle.contains('study') || lowerTitle.contains('학습')) {
      return Icons.auto_stories_outlined;
    } else if (lowerTitle.contains('analysis') || lowerTitle.contains('분석')) {
      return Icons.analytics_outlined;
    } else if (lowerTitle.contains('가족') || lowerTitle.contains('family')) {
      return Icons.family_restroom;
    } else if (lowerTitle.contains('전화') || lowerTitle.contains('call') || lowerTitle.contains('phone')) {
      return Icons.phone_outlined;
    } else if (lowerTitle.contains('문서') || lowerTitle.contains('document')) {
      return Icons.description_outlined;
    } else if (lowerTitle.contains('자료') || lowerTitle.contains('research')) {
      return Icons.search;
    }
    
    // 기본 아이콘
    return Icons.event_outlined;
  }
  
  @override
  Widget build(BuildContext context) {
    final isToday = _selectedDate.year == DateTime.now().year &&
                    _selectedDate.month == DateTime.now().month &&
                    _selectedDate.day == DateTime.now().day;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('GrowthClock'),
      ),
      body: Column(
        children: [
          // 날짜 네비게이션 (새 디자인)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left, color: Colors.grey.shade600),
                      onPressed: () => _changeDate(-1),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          DateFormat('yyyy MMM dd (E)', 'en').format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right, color: Colors.grey.shade600),
                      onPressed: () => _changeDate(1),
                    ),
                  ],
                ),
                if (!isToday)
                  GestureDetector(
                    onTap: _goToToday,
                    child: Text(
                      'Go to Today',
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // 캘린더 연동 상태
          if (!_calendarService.isSignedIn || _selectedCalendarId == null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade50, Colors.amber.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_off, size: 40, color: Colors.orange.shade700),
                  const SizedBox(height: 8),
                  Text(
                    !_calendarService.isSignedIn 
                        ? 'Google 캘린더 로그인 필요'
                        : '캘린더를 선택해주세요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    !_calendarService.isSignedIn 
                        ? '활동 기록을 위해 Google 캘린더에 로그인해주세요.'
                        : '활동을 저장할 캘린더를 선택해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                      _loadSettings();
                      _loadCalendarEvents();
                    },
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('설정으로 이동'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // 이벤트 목록
          Expanded(
            child: _isLoadingEvents
                ? const Center(child: CircularProgressIndicator())
                : _calendarEvents.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '등록된 일정이 없습니다',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCalendarEvents,
                        child: ListView.builder(
                          itemCount: _calendarEvents.length,
                          itemBuilder: (context, index) {
                            final event = _calendarEvents[index];
                            final isAllDay = event.start?.date != null;
                            return Dismissible(
                              key: Key(event.id ?? 'event_$index'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              confirmDismiss: (direction) async {
                                return await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('삭제 확인'),
                                    content: const Text('이 활동 기록을 삭제하시겠습니까?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('취소'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                                        child: const Text('삭제'),
                                      ),
                                    ],
                                  ),
                                ) ?? false;
                              },
                              onDismissed: (direction) async {
                                // Google Calendar에서 삭제
                                if (_calendarService.isSignedIn && _selectedCalendarId != null && event.id != null) {
                                  await _calendarService.deleteEvent(event.id!, _selectedCalendarId!);
                                }
                                
                                // 로컬 DB에서도 삭제 (시간 범위로 찾아서 삭제)
                                if (event.start?.dateTime != null && event.end?.dateTime != null) {
                                  final log = await _dbService.getActivityLogInTimeRange(
                                    event.start!.dateTime!.toLocal(),
                                    event.end!.dateTime!.toLocal(),
                                  );
                                  if (log != null) {
                                    await _dbService.deleteActivityLog(log.id);
                                  }
                                }
                                
                                setState(() {
                                  _calendarEvents.removeAt(index);
                                });
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('활동 기록이 삭제되었습니다'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () {
                                    if (event.start?.dateTime != null && event.end?.dateTime != null) {
                                      final eventStartTime = event.start!.dateTime!.toLocal();
                                      final eventEndTime = event.end!.dateTime!.toLocal();
                                      showInputDialog(
                                        initialTime: eventEndTime,
                                        eventStartTime: eventStartTime,
                                        eventTitle: event.summary,
                                        eventDescription: event.description,
                                        isNewRecord: false,  // 기존 이벤트 편집
                                      );
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        // 카테고리 아이콘
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: _getCategoryColor(event.summary ?? '').withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            _getCategoryIcon(event.summary ?? ''),
                                            color: _getCategoryColor(event.summary ?? ''),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // 내용
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                event.summary ?? '(제목 없음)',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _formatEventTime(event),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              if (event.description != null && event.description!.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    event.description!,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                          color: Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
      ],
      ),
    );
  }
}
