import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/database_service.dart';
import '../services/google_calendar_service.dart';
import '../services/llm_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _dbService = DatabaseService();
  final _calendarService = GoogleCalendarService();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('리포트'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: '일별'),
            Tab(text: '주별'),
            Tab(text: '월별'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DailyReport(dbService: _dbService, calendarService: _calendarService),
          _WeeklyReport(dbService: _dbService, calendarService: _calendarService),
          _MonthlyReport(dbService: _dbService, calendarService: _calendarService),
        ],
      ),
    );
  }
}

// =====================================================
// 일별 리포트
// =====================================================
class _DailyReport extends StatefulWidget {
  final DatabaseService dbService;
  final GoogleCalendarService calendarService;
  
  const _DailyReport({required this.dbService, required this.calendarService});

  @override
  State<_DailyReport> createState() => _DailyReportState();
}

class _DailyReportState extends State<_DailyReport> {
  DateTime _selectedDate = DateTime.now();
  Map<String, int> _stats = {};
  List<String> _activities = [];
  String? _aiAnalysis;
  bool _isAnalyzing = false;
  bool _isAnalysisFromCalendar = false;
  String? _existingAnalysisEventId;
  String? _selectedCalendarId;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCalendarId = prefs.getString('selected_calendar_id');
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // 캘린더 미연결 시 빈 데이터 설정
    if (!widget.calendarService.isSignedIn || _selectedCalendarId == null) {
      if (!mounted) return;
      setState(() {
        _stats = {};
        _activities = [];
        _aiAnalysis = null;
        _isLoading = false;
      });
      return;
    }
    
    // 캘린더 연결된 경우 캘린더에서 로드
    final events = await widget.calendarService.getEventsForDate(_selectedDate, _selectedCalendarId!);
    
    final stats = <String, int>{};
    final activities = <String>[];
    String? existingAnalysis;
    String? existingAnalysisId;
    
    for (var event in events) {
      if (event.start?.date != null && event.end?.date != null) {
        if (event.summary != null && 
            (event.summary!.contains('일일 분석 리포트') || event.summary!.contains('📊'))) {
          existingAnalysis = event.description;
          existingAnalysisId = event.id;
        }
      } else if (event.start?.dateTime != null && event.end?.dateTime != null) {
        final summary = event.summary ?? '';
        final categoryMatch = RegExp(r'\[([^\]]+)\]').firstMatch(summary);
        if (categoryMatch != null) {
          final category = categoryMatch.group(1)!;
          final start = event.start!.dateTime!.toLocal();
          final end = event.end!.dateTime!.toLocal();
          final duration = end.difference(start).inMinutes;
          
          stats[category] = (stats[category] ?? 0) + duration;
          
          if (event.description != null && event.description!.isNotEmpty) {
            activities.add('$category: ${event.description}');
          }
        }
      }
    }
    
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _activities = activities;
      _aiAnalysis = existingAnalysis;
      _isAnalysisFromCalendar = existingAnalysis != null;
      _existingAnalysisEventId = existingAnalysisId;
      _isLoading = false;
    });
  }
  
  Future<void> _analyzeWithAI() async {
    if (_stats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('분석할 데이터가 없습니다')),
      );
      return;
    }
    
    setState(() {
      _isAnalyzing = true;
    });
    
    try {
      final llmService = LLMService();
      final analysis = await llmService.analyzeDailyActivity(
        date: _selectedDate,
        categoryStats: _stats,
        activities: _activities,
      );
      
      setState(() {
        _aiAnalysis = analysis;
        _isAnalyzing = false;
        _isAnalysisFromCalendar = false;
      });
      
      if (analysis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석 실패. Gemini API 키를 확인하세요')),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('분석 중 오류 발생: $e')),
      );
    }
  }
  
  Future<void> _saveAnalysisToCalendar() async {
    if (_aiAnalysis == null || _selectedCalendarId == null) return;
    
    final title = '📊 ${DateFormat('yyyy-MM-dd').format(_selectedDate)} 일일 분석 리포트';
    bool success = false;
    
    if (_existingAnalysisEventId != null) {
      success = await widget.calendarService.updateAllDayEvent(
        eventId: _existingAnalysisEventId!,
        title: title,
        description: _aiAnalysis!,
        date: _selectedDate,
        calendarId: _selectedCalendarId!,
      );
    } else {
      final newId = await widget.calendarService.createAllDayEvent(
        title: title,
        description: _aiAnalysis!,
        date: _selectedDate,
        calendarId: _selectedCalendarId!,
      );
      
      if (newId != null) {
        success = true;
        setState(() {
          _existingAnalysisEventId = newId;
        });
      }
    }
    
    if (success) {
      setState(() {
        _isAnalysisFromCalendar = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI 분석 리포트가 캘린더에 저장되었습니다'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장 실패'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  int get _totalMinutes => _stats.values.isEmpty ? 0 : _stats.values.reduce((a, b) => a + b);
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 리포트 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📅 일일 리포트',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '하루 동안의 활동을 분석합니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          
          // 날짜 선택기
          _buildDateSelector(
            label: DateFormat('yyyy년 MM월 dd일 (E)', 'ko').format(_selectedDate),
            onPrevious: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _loadData();
            },
            onNext: () {
              setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 1));
              });
              _loadData();
            },
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() {
                  _selectedDate = date;
                });
                _loadData();
              }
            },
          ),
          
          // 로그인 안내
          // 로딩 인디케이터
          if (_isLoading)
            _buildLoadingIndicator(),
          
          // 로그인 안내
          if (!_isLoading && !widget.calendarService.isSignedIn)
            _buildLoginPrompt(),
          
          // 데이터 없음 안내
          if (!_isLoading && _stats.isEmpty && widget.calendarService.isSignedIn)
            _buildNoDataMessage(),
          
          // 차트
          if (!_isLoading && _stats.isNotEmpty)
            _buildPieChart(_stats, _totalMinutes),
          
          // AI 분석 버튼
          if (!_isLoading && _stats.isNotEmpty)
            _buildAnalyzeButton(
              isAnalyzing: _isAnalyzing,
              hasAnalysis: _aiAnalysis != null,
              onPressed: _analyzeWithAI,
            ),
          
          // AI 분석 결과
          if (_aiAnalysis != null)
            _buildAnalysisCard(
              analysis: _aiAnalysis!,
              isFromCalendar: _isAnalysisFromCalendar,
              onSave: _saveAnalysisToCalendar,
            ),
        ],
      ),
    );
  }
  
  Color _getCategoryColor(String category) {
    const colors = [
      Color(0xFF1E88E5),
      Color(0xFF8BC34A),
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
    ];
    return colors[category.hashCode % colors.length];
  }
}

// =====================================================
// 주별 리포트
// =====================================================
class _WeeklyReport extends StatefulWidget {
  final DatabaseService dbService;
  final GoogleCalendarService calendarService;
  
  const _WeeklyReport({required this.dbService, required this.calendarService});

  @override
  State<_WeeklyReport> createState() => _WeeklyReportState();
}

class _WeeklyReportState extends State<_WeeklyReport> {
  DateTime _selectedDate = DateTime.now();
  Map<String, int> _stats = {};
  List<String> _activities = [];
  String? _aiAnalysis;
  bool _isAnalyzing = false;
  bool _isAnalysisFromCalendar = false;
  String? _existingAnalysisEventId;
  String? _selectedCalendarId;
  bool _isLoading = true;
  
  DateTime get _startOfWeek => _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
  DateTime get _endOfWeek => _startOfWeek.add(const Duration(days: 6));
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCalendarId = prefs.getString('selected_calendar_id');
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // 캘린더 미연결 시 빈 데이터 설정
    if (!widget.calendarService.isSignedIn || _selectedCalendarId == null) {
      if (!mounted) return;
      setState(() {
        _stats = {};
        _activities = [];
        _aiAnalysis = null;
        _isLoading = false;
      });
      return;
    }
    
    final stats = <String, int>{};
    final activities = <String>[];
    String? existingAnalysis;
    String? existingAnalysisId;
    
    // 주간 데이터 로드
    for (int i = 0; i < 7; i++) {
      final date = _startOfWeek.add(Duration(days: i));
      final events = await widget.calendarService.getEventsForDate(date, _selectedCalendarId!);
      
      for (var event in events) {
        // 주간 분석 리포트 찾기 (주 마지막 날에 저장됨)
        if (event.start?.date != null && event.end?.date != null) {
          if (event.summary != null && event.summary!.contains('주간 분석 리포트')) {
            existingAnalysis = event.description;
            existingAnalysisId = event.id;
          }
        } else if (event.start?.dateTime != null && event.end?.dateTime != null) {
          final summary = event.summary ?? '';
          final categoryMatch = RegExp(r'\[([^\]]+)\]').firstMatch(summary);
          if (categoryMatch != null) {
            final category = categoryMatch.group(1)!;
            final start = event.start!.dateTime!.toLocal();
            final end = event.end!.dateTime!.toLocal();
            final duration = end.difference(start).inMinutes;
            
            stats[category] = (stats[category] ?? 0) + duration;
            
            if (event.description != null && event.description!.isNotEmpty) {
              activities.add('$category: ${event.description}');
            }
          }
        }
      }
    }
    
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _activities = activities;
      _aiAnalysis = existingAnalysis;
      _isAnalysisFromCalendar = existingAnalysis != null;
      _existingAnalysisEventId = existingAnalysisId;
      _isLoading = false;
    });
  }
  
  Future<void> _analyzeWithAI() async {
    if (_stats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('분석할 데이터가 없습니다')),
      );
      return;
    }
    
    setState(() {
      _isAnalyzing = true;
    });
    
    try {
      final llmService = LLMService();
      final analysis = await llmService.analyzeWeeklyActivity(
        startDate: _startOfWeek,
        endDate: _endOfWeek,
        categoryStats: _stats,
        activities: _activities,
      );
      
      setState(() {
        _aiAnalysis = analysis;
        _isAnalyzing = false;
        _isAnalysisFromCalendar = false;
      });
      
      if (analysis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석 실패. Gemini API 키를 확인하세요')),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('분석 중 오류 발생: $e')),
      );
    }
  }
  
  Future<void> _saveAnalysisToCalendar() async {
    if (_aiAnalysis == null || _selectedCalendarId == null) return;
    
    // 주 마지막 날(일요일)에 저장
    final title = '📊 ${DateFormat('MM/dd').format(_startOfWeek)}~${DateFormat('MM/dd').format(_endOfWeek)} 주간 분석 리포트';
    bool success = false;
    
    if (_existingAnalysisEventId != null) {
      success = await widget.calendarService.updateAllDayEvent(
        eventId: _existingAnalysisEventId!,
        title: title,
        description: _aiAnalysis!,
        date: _endOfWeek,
        calendarId: _selectedCalendarId!,
      );
    } else {
      final newId = await widget.calendarService.createAllDayEvent(
        title: title,
        description: _aiAnalysis!,
        date: _endOfWeek,
        calendarId: _selectedCalendarId!,
      );
      
      if (newId != null) {
        success = true;
        setState(() {
          _existingAnalysisEventId = newId;
        });
      }
    }
    
    if (success) {
      setState(() {
        _isAnalysisFromCalendar = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('주간 분석 리포트가 캘린더에 저장되었습니다'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장 실패'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  int get _totalMinutes => _stats.values.isEmpty ? 0 : _stats.values.reduce((a, b) => a + b);
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 리포트 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📆 주간 리포트',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '한 주간의 활동 패턴을 분석합니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          
          // 주간 선택기
          _buildDateSelector(
            label: '${DateFormat('MM/dd').format(_startOfWeek)} ~ ${DateFormat('MM/dd').format(_endOfWeek)}',
            onPrevious: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 7));
              });
              _loadData();
            },
            onNext: () {
              setState(() {
                _selectedDate = _selectedDate.add(const Duration(days: 7));
              });
              _loadData();
            },
            onTap: null,
          ),
          
          // 로딩 인디케이터
          if (_isLoading)
            _buildLoadingIndicator(),
          
          // 로그인 안내
          if (!_isLoading && !widget.calendarService.isSignedIn)
            _buildLoginPrompt(),
          
          // 데이터 없음 안내
          if (!_isLoading && _stats.isEmpty && widget.calendarService.isSignedIn)
            _buildNoDataMessage(),
          
          if (!_isLoading && _stats.isNotEmpty)
            _buildPieChart(_stats, _totalMinutes),
          
          if (!_isLoading && _stats.isNotEmpty)
            _buildAnalyzeButton(
              isAnalyzing: _isAnalyzing,
              hasAnalysis: _aiAnalysis != null,
              onPressed: _analyzeWithAI,
            ),
          
          // AI 분석 결과
          if (_aiAnalysis != null)
            _buildAnalysisCard(
              analysis: _aiAnalysis!,
              isFromCalendar: _isAnalysisFromCalendar,
              onSave: _saveAnalysisToCalendar,
            ),
        ],
      ),
    );
  }
}

// =====================================================
// 월별 리포트
// =====================================================
class _MonthlyReport extends StatefulWidget {
  final DatabaseService dbService;
  final GoogleCalendarService calendarService;
  
  const _MonthlyReport({required this.dbService, required this.calendarService});

  @override
  State<_MonthlyReport> createState() => _MonthlyReportState();
}

class _MonthlyReportState extends State<_MonthlyReport> {
  DateTime _selectedDate = DateTime.now();
  Map<String, int> _stats = {};
  List<String> _activities = [];
  String? _aiAnalysis;
  bool _isAnalyzing = false;
  bool _isAnalysisFromCalendar = false;
  String? _existingAnalysisEventId;
  String? _selectedCalendarId;
  bool _isLoading = true;
  
  DateTime get _startOfMonth => DateTime(_selectedDate.year, _selectedDate.month, 1);
  DateTime get _endOfMonth => DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCalendarId = prefs.getString('selected_calendar_id');
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // 캘린더 미연결 시 빈 데이터 설정
    if (!widget.calendarService.isSignedIn || _selectedCalendarId == null) {
      if (!mounted) return;
      setState(() {
        _stats = {};
        _activities = [];
        _aiAnalysis = null;
        _isLoading = false;
      });
      return;
    }
    
    final stats = <String, int>{};
    final activities = <String>[];
    String? existingAnalysis;
    String? existingAnalysisId;
    
    // 월간 데이터 로드
    final daysInMonth = _endOfMonth.day;
    for (int i = 0; i < daysInMonth; i++) {
      final date = _startOfMonth.add(Duration(days: i));
      final events = await widget.calendarService.getEventsForDate(date, _selectedCalendarId!);
      
      for (var event in events) {
        // 월간 분석 리포트 찾기 (월 마지막 날에 저장됨)
        if (event.start?.date != null && event.end?.date != null) {
          if (event.summary != null && event.summary!.contains('월간 분석 리포트')) {
            existingAnalysis = event.description;
            existingAnalysisId = event.id;
          }
        } else if (event.start?.dateTime != null && event.end?.dateTime != null) {
          final summary = event.summary ?? '';
          final categoryMatch = RegExp(r'\[([^\]]+)\]').firstMatch(summary);
          if (categoryMatch != null) {
            final category = categoryMatch.group(1)!;
            final start = event.start!.dateTime!.toLocal();
            final end = event.end!.dateTime!.toLocal();
            final duration = end.difference(start).inMinutes;
            
            stats[category] = (stats[category] ?? 0) + duration;
            
            if (event.description != null && event.description!.isNotEmpty) {
              activities.add('$category: ${event.description}');
            }
          }
        }
      }
    }
    
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _activities = activities;
      _aiAnalysis = existingAnalysis;
      _isAnalysisFromCalendar = existingAnalysis != null;
      _existingAnalysisEventId = existingAnalysisId;
      _isLoading = false;
    });
  }
  
  Future<void> _analyzeWithAI() async {
    if (_stats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('분석할 데이터가 없습니다')),
      );
      return;
    }
    
    setState(() {
      _isAnalyzing = true;
    });
    
    try {
      final llmService = LLMService();
      final analysis = await llmService.analyzeMonthlyActivity(
        year: _selectedDate.year,
        month: _selectedDate.month,
        categoryStats: _stats,
        activities: _activities,
      );
      
      setState(() {
        _aiAnalysis = analysis;
        _isAnalyzing = false;
        _isAnalysisFromCalendar = false;
      });
      
      if (analysis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석 실패. Gemini API 키를 확인하세요')),
        );
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('분석 중 오류 발생: $e')),
      );
    }
  }
  
  Future<void> _saveAnalysisToCalendar() async {
    if (_aiAnalysis == null || _selectedCalendarId == null) return;
    
    // 월 마지막 날에 저장
    final title = '📊 ${DateFormat('yyyy년 MM월').format(_selectedDate)} 월간 분석 리포트';
    bool success = false;
    
    if (_existingAnalysisEventId != null) {
      success = await widget.calendarService.updateAllDayEvent(
        eventId: _existingAnalysisEventId!,
        title: title,
        description: _aiAnalysis!,
        date: _endOfMonth,
        calendarId: _selectedCalendarId!,
      );
    } else {
      final newId = await widget.calendarService.createAllDayEvent(
        title: title,
        description: _aiAnalysis!,
        date: _endOfMonth,
        calendarId: _selectedCalendarId!,
      );
      
      if (newId != null) {
        success = true;
        setState(() {
          _existingAnalysisEventId = newId;
        });
      }
    }
    
    if (success) {
      setState(() {
        _isAnalysisFromCalendar = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('월간 분석 리포트가 캘린더에 저장되었습니다'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장 실패'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  int get _totalMinutes => _stats.values.isEmpty ? 0 : _stats.values.reduce((a, b) => a + b);
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 리포트 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.purple.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🗓️ 월간 리포트',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '한 달간의 활동을 종합 분석합니다',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          
          // 월간 선택기
          _buildDateSelector(
            label: DateFormat('yyyy년 MM월').format(_selectedDate),
            onPrevious: () {
              setState(() {
                _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
              });
              _loadData();
            },
            onNext: () {
              setState(() {
                _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
              });
              _loadData();
            },
            onTap: null,
          ),
          
          // 로딩 인디케이터
          if (_isLoading)
            _buildLoadingIndicator(),
          
          // 로그인 안내
          if (!_isLoading && !widget.calendarService.isSignedIn)
            _buildLoginPrompt(),
          
          // 데이터 없음 안내
          if (!_isLoading && _stats.isEmpty && widget.calendarService.isSignedIn)
            _buildNoDataMessage(),
          
          if (!_isLoading && _stats.isNotEmpty)
            _buildPieChart(_stats, _totalMinutes),
          
          if (!_isLoading && _stats.isNotEmpty)
            _buildAnalyzeButton(
              isAnalyzing: _isAnalyzing,
              hasAnalysis: _aiAnalysis != null,
              onPressed: _analyzeWithAI,
            ),
          
          // AI 분석 결과
          if (_aiAnalysis != null)
            _buildAnalysisCard(
              analysis: _aiAnalysis!,
              isFromCalendar: _isAnalysisFromCalendar,
              onSave: _saveAnalysisToCalendar,
            ),
        ],
      ),
    );
  }
}

// =====================================================
// 공통 위젯 빌더 함수들
// =====================================================

Widget _buildDateSelector({
  required String label,
  required VoidCallback onPrevious,
  required VoidCallback onNext,
  VoidCallback? onTap,
}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        GestureDetector(
          onTap: onTap,
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    ),
  );
}

Widget _buildLoginPrompt() {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.orange.shade50, Colors.amber.shade50],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Column(
      children: [
        Icon(Icons.cloud_off, size: 48, color: Colors.orange.shade700),
        const SizedBox(height: 12),
        Text(
          'Google 캘린더 연결 필요',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.orange.shade800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '활동 기록과 분석 리포트를 확인하려면\nGoogle 캘린더에 로그인하고 캘린더를 선택해주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '설정 > Google 캘린더에서 연결할 수 있습니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.orange.shade700,
          ),
        ),
      ],
    ),
  );
}

Widget _buildLoadingIndicator() {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 80),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
        ),
        const SizedBox(height: 20),
        Text(
          '데이터 로딩 중...',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    ),
  );
}

Widget _buildNoDataMessage() {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      children: [
        Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          '기록된 활동이 없습니다',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '이 기간에 등록된 활동 기록이 없습니다.\n활동을 기록하고 분석을 받아보세요!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    ),
  );
}

Widget _buildPieChart(Map<String, int> stats, int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final mins = totalMinutes % 60;
  
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        // 도넛 차트 (큰 사이즈)
        Expanded(
          flex: 5,
          child: AspectRatio(
            aspectRatio: 1,
            child: PieChart(
              PieChartData(
                sections: stats.entries.map((entry) {
                  final percentage = totalMinutes > 0 
                      ? (entry.value / totalMinutes * 100) 
                      : 0.0;
                  return PieChartSectionData(
                    value: entry.value.toDouble(),
                    title: '${percentage.toStringAsFixed(0)}%',
                    color: _getChartColor(entry.key),
                    radius: 60,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    titlePositionPercentageOffset: 0.55,
                  );
                }).toList(),
                sectionsSpace: 3,
                centerSpaceRadius: 45,
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // 범례
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 총 시간 (큰 제목)
              Text(
                '총 ${hours}시간 ${mins}분',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              // 카테고리별 범례
              ...stats.entries.map((entry) {
                final h = entry.value ~/ 60;
                final m = entry.value % 60;
                final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _getChartColor(entry.key),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildAnalyzeButton({
  required bool isAnalyzing,
  required bool hasAnalysis,
  required VoidCallback onPressed,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: isAnalyzing ? null : onPressed,
        icon: isAnalyzing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(hasAnalysis ? Icons.refresh : Icons.auto_awesome, size: 18),
        label: Text(
          isAnalyzing
              ? 'AI 분석 중...'
              : hasAnalysis
                  ? '↻ AI 재분석'
                  : 'AI 분석 시작',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
  );
}

Widget _buildAnalysisCard({
  required String analysis,
  required bool isFromCalendar,
  required VoidCallback onSave,
}) {
  return Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 15,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.smart_toy, color: Color(0xFF3B82F6), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI 분석 결과',
                    style: TextStyle(
                      fontSize: 20, 
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  if (isFromCalendar)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '📅 캘린더에서 불러옴',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
            if (!isFromCalendar)
              TextButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.calendar_today, size: 16, color: Color(0xFF3B82F6)),
                label: const Text('저장', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        
        // 분석 내용
        MarkdownBody(
          data: analysis,
          styleSheet: MarkdownStyleSheet(
            h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
            h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
            p: const TextStyle(fontSize: 15, height: 1.7, color: Colors.black87),
            listBullet: const TextStyle(fontSize: 15, color: Colors.black87),
            blockquote: const TextStyle(
              color: Colors.blueGrey,
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
            code: TextStyle(
              backgroundColor: Colors.grey.shade100,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

Color _getChartColor(String category) {
  // 이미지 레퍼런스에 맞춘 선명한 색상
  const colors = [
    Color(0xFFEF4444), // 빨강 (27%)
    Color(0xFFEC4899), // 핑크/마젠타
    Color(0xFF10B981), // 초록
    Color(0xFF8B5CF6), // 보라
    Color(0xFF6366F1), // 진한 보라/인디고
    Color(0xFF3B82F6), // 파랑
    Color(0xFF14B8A6), // 청록
    Color(0xFFF59E0B), // 주황/노랑
    Color(0xFF06B6D4), // 시안
    Color(0xFFF97316), // 오렌지
  ];
  return colors[category.hashCode.abs() % colors.length];
}
