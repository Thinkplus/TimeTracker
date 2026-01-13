import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'dart:io';
import '../services/google_calendar_service.dart';
import '../services/database_service.dart';
import '../services/llm_service.dart';
import '../services/update_service.dart';
import '../models/category.dart';
import 'package:googleapis/calendar/v3.dart' as cal;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _calendarService = GoogleCalendarService();
  final _dbService = DatabaseService();
  
  // 일반 설정
  int _selectedInterval = 60;
  String? _selectedCalendarId;
  List<cal.CalendarListEntry> _calendars = [];
  final TextEditingController _categoryController = TextEditingController();
  
  // 윈도우 설정
  double _opacity = 1.0;

  bool _isAlwaysOnTop = false;
  bool _isLaunchAtStartup = false;
  
  // AI 설정
  final TextEditingController _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;
  
  // 프롬프트 설정
  final TextEditingController _dailyPromptController = TextEditingController();
  final TextEditingController _weeklyPromptController = TextEditingController();
  final TextEditingController _monthlyPromptController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
    _loadCategories();
    _loadPrompts();
    _loadApiKey();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _categoryController.dispose();
    _apiKeyController.dispose();
    _dailyPromptController.dispose();
    _weeklyPromptController.dispose();
    _monthlyPromptController.dispose();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedInterval = prefs.getInt('reminder_interval') ?? 60;
      _selectedCalendarId = prefs.getString('selected_calendar_id');
      _opacity = prefs.getDouble('window_opacity') ?? 1.0;
      _isAlwaysOnTop = prefs.getBool('window_always_on_top') ?? false;
    });
    
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setOpacity(_opacity);
      await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
      _isLaunchAtStartup = await launchAtStartup.isEnabled();
    }
    
    if (_calendarService.isSignedIn) {
      _loadCalendars();
    }
  }
  
  Future<void> _loadCalendars() async {
    final calendars = await _calendarService.getCalendarList();
    setState(() {
      _calendars = calendars;
    });
  }
  
  Future<void> _loadCategories() async {
    final categories = await _dbService.getAllCategories();
    final text = categories.map((c) => c.name).join(', ');
    _categoryController.text = text;
  }
  
  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyPromptController.text = prefs.getString(LLMService.dailyPromptKey) ?? LLMService.defaultDailyPrompt;
    _weeklyPromptController.text = prefs.getString(LLMService.weeklyPromptKey) ?? LLMService.defaultWeeklyPrompt;
    _monthlyPromptController.text = prefs.getString(LLMService.monthlyPromptKey) ?? LLMService.defaultMonthlyPrompt;
  }
  
  Future<void> _loadApiKey() async {
    final apiKey = await LLMService.getApiKey();
    setState(() {
      _apiKeyController.text = apiKey;
    });
  }
  
  Future<void> _saveApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    await LLMService.setApiKey(apiKey);
    // LLMService 재초기화
    await LLMService().init();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 키가 저장되었습니다'), backgroundColor: Colors.green),
      );
    }
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_interval', _selectedInterval);
    if (_selectedCalendarId != null) {
      await prefs.setString('selected_calendar_id', _selectedCalendarId!);
    }
    
    await prefs.setDouble('window_opacity', _opacity);
    await prefs.setBool('window_always_on_top', _isAlwaysOnTop);
    
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.setOpacity(_opacity);
      await windowManager.setAlwaysOnTop(_isAlwaysOnTop);
    }
  }
  
  Future<void> _savePrompt(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('프롬프트가 저장되었습니다'), backgroundColor: Colors.green),
    );
  }
  
  Future<void> _resetPrompt(String key, String defaultValue, TextEditingController controller) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    controller.text = defaultValue;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('프롬프트가 기본값으로 초기화되었습니다')),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: '일반'),
            Tab(icon: Icon(Icons.smart_toy), text: 'AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralTab(),
          _buildPromptTab(),
        ],
      ),
    );
  }
  
  // =====================================================
  // 일반 탭
  // =====================================================
  Widget _buildGeneralTab() {
    return ListView(
      children: [
        // Google Calendar 섹션
        _buildSectionHeader('Google Calendar'),
        _buildGoogleCalendarTile(),
        
        if (_calendarService.isSignedIn && _calendars.isNotEmpty)
          _buildCalendarSelector(),
        
        const Divider(),
        
        // 알림 설정
        _buildSectionHeader('알림 간격'),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('알림 간격'),
          subtitle: Text('$_selectedInterval분마다 기록 알림'),
          trailing: DropdownButton<int>(
            value: _selectedInterval,
            items: [15, 30, 60, 90, 120].map((interval) {
              return DropdownMenuItem(
                value: interval,
                child: Text('$interval분'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedInterval = value);
                _saveSettings();
              }
            },
          ),
        ),
        
        const Divider(),
        
        // 윈도우 설정 (데스크톱 전용)
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ...[
          _buildSectionHeader('윈도우 설정'),
          ListTile(
            leading: const Icon(Icons.opacity),
            title: const Text('투명도'),
            subtitle: Text('${(_opacity * 100).toInt()}%'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _opacity,
                min: 0.3,
                max: 1.0,
                onChanged: (value) {
                  setState(() => _opacity = value);
                  _saveSettings();
                },
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.push_pin),
            title: const Text('항상 위에 표시'),
            subtitle: const Text('다른 창 위에 고정'),
            value: _isAlwaysOnTop,
            onChanged: (value) {
              setState(() => _isAlwaysOnTop = value);
              _saveSettings();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.rocket_launch),
            title: const Text('시작 시 자동 실행'),
            subtitle: const Text('컴퓨터 시작 시 앱 자동 실행'),
            value: _isLaunchAtStartup,
            onChanged: (value) async {
              setState(() => _isLaunchAtStartup = value);
              if (value) {
                await launchAtStartup.enable();
              } else {
                await launchAtStartup.disable();
              }
            },
          ),
          const Divider(),
        ],
        
        // 카테고리 설정
        _buildSectionHeader('카테고리 관리'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '쉼표(,)로 구분하여 카테고리를 입력하세요:',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  hintText: '예: 회의, 문서작성, 이메일',
                  helperText: '목록에서 제거하면 카테고리가 삭제됩니다.',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _saveCategoriesFromText(_categoryController.text),
                  icon: const Icon(Icons.save),
                  label: const Text('카테고리 저장'),
                ),
              ),
            ],
          ),
        ),
        
        // 앱 업데이트
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) ...[
          _buildSectionHeader('앱 업데이트'),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('업데이트 확인'),
            subtitle: FutureBuilder<String>(
              future: UpdateService().getCurrentVersion(),
              builder: (context, snapshot) {
                return Text('현재 버전: v${snapshot.data ?? "..."}');
              },
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              // 로딩 표시
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('업데이트 확인 중...')),
              );
              
              final updateService = UpdateService();
              await updateService.getCurrentVersion();
              final hasUpdate = await updateService.checkForUpdates();
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              
              if (hasUpdate) {
                updateService.showUpdateDialog(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('최신 버전을 사용 중입니다.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
          ),
        ],
      ],
    );
  }
  
  // =====================================================
  // AI 탭
  // =====================================================
  Widget _buildPromptTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gemini API 키 섹션
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text('Gemini API 키', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'AI 분석 기능을 사용하려면 Gemini API 키가 필요합니다.\n'
                    'Google AI Studio에서 무료로 발급받을 수 있습니다.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      hintText: 'API 키를 입력하세요',
                      prefixIcon: const Icon(Icons.vpn_key),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureApiKey = !_obscureApiKey;
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.save),
                            onPressed: _saveApiKey,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // 프롬프트 변수 안내
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text('프롬프트 변수 안내', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• {{DATE}} - 분석 날짜\n'
                    '• {{PERIOD}} - 분석 기간\n'
                    '• {{STATS}} - 카테고리별 시간 통계\n'
                    '• {{ACTIVITIES}} - 활동 내역',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // 일별 프롬프트
          _buildPromptSection(
            title: '📅 일별 분석 프롬프트',
            controller: _dailyPromptController,
            promptKey: LLMService.dailyPromptKey,
            defaultPrompt: LLMService.defaultDailyPrompt,
          ),
          
          const SizedBox(height: 24),
          
          // 주별 프롬프트
          _buildPromptSection(
            title: '📆 주별 분석 프롬프트',
            controller: _weeklyPromptController,
            promptKey: LLMService.weeklyPromptKey,
            defaultPrompt: LLMService.defaultWeeklyPrompt,
          ),
          
          const SizedBox(height: 24),
          
          // 월별 프롬프트
          _buildPromptSection(
            title: '🗓️ 월별 분석 프롬프트',
            controller: _monthlyPromptController,
            promptKey: LLMService.monthlyPromptKey,
            defaultPrompt: LLMService.defaultMonthlyPrompt,
          ),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }
  
  Widget _buildPromptSection({
    required String title,
    required TextEditingController controller,
    required String promptKey,
    required String defaultPrompt,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: 12,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => _resetPrompt(promptKey, defaultPrompt, controller),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('초기화'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _savePrompt(promptKey, controller.text),
              icon: const Icon(Icons.save, size: 18),
              label: const Text('저장'),
            ),
          ],
        ),
      ],
    );
  }
  
  // =====================================================
  // Helper Widgets
  // =====================================================
  Widget _buildSectionHeader(String title) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }
  
  Widget _buildGoogleCalendarTile() {
    return ListTile(
      leading: const Icon(Icons.account_circle),
      title: Text(
        _calendarService.isSignedIn
            ? '로그인됨: ${_calendarService.currentUser?.email ?? ""}'
            : '로그인하지 않음',
      ),
      trailing: _calendarService.isSignedIn
          ? ElevatedButton(
              onPressed: () async {
                await _calendarService.signOut();
                setState(() {
                  _calendars = [];
                  _selectedCalendarId = null;
                });
              },
              child: const Text('로그아웃'),
            )
          : ElevatedButton(
              onPressed: () async {
                if (!_calendarService.isConfigured) {
                  _showOAuthSetupDialog();
                  return;
                }
                
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 20),
                        Text('구글 로그인 중...'),
                      ],
                    ),
                  ),
                );
                
                final success = await _calendarService.signIn();
                Navigator.pop(context);
                
                if (success) {
                  _loadCalendars();
                  setState(() {});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('로그인 실패')),
                  );
                }
              },
              child: const Text('로그인'),
            ),
    );
  }
  
  Widget _buildCalendarSelector() {
    return ListTile(
      leading: const Icon(Icons.calendar_today),
      title: const Text('캘린더 선택'),
      subtitle: Text(_selectedCalendarId ?? '선택되지 않음'),
      trailing: DropdownButton<String>(
        value: _selectedCalendarId,
        hint: const Text('선택'),
        items: _calendars.map((calendar) {
          return DropdownMenuItem(
            value: calendar.id,
            child: Text(calendar.summary ?? calendar.id ?? ''),
          );
        }).toList(),
        onChanged: (value) {
          setState(() => _selectedCalendarId = value);
          _saveSettings();
        },
      ),
    );
  }
  
  void _showOAuthSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('OAuth 설정 필요'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Google Calendar를 사용하려면 먼저 OAuth 클라이언트 ID를 설정해야 합니다.\n',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('📋 설정 방법:\n'),
              Text(
                '1. GOOGLE_OAUTH_SETUP.md 파일을 열어 단계별 가이드 확인\n\n'
                '2. Google Cloud Console에서 OAuth 클라이언트 ID 생성\n'
                '   - 유형: iOS\n'
                '   - 번들 ID: com.ybsoft.growthClock\n\n'
                '3. lib/services/google_calendar_service.dart 파일에서\n'
                '   _clientId 변수에 발급받은 클라이언트 ID 입력\n\n'
                '4. 앱을 다시 빌드하고 실행',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _saveCategoriesFromText(String text) async {
    List<String> categoryNames = text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    
    if (categoryNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 하나의 카테고리를 입력해주세요')),
      );
      return;
    }

    try {
      List<Category> existingCategories = await _dbService.getAllCategories();
      Map<String, Category> existingMap = {
        for (var c in existingCategories) c.name: c
      };
      
      List<int> idsToDelete = [];
      for (var existing in existingCategories) {
        if (!categoryNames.contains(existing.name)) {
          idsToDelete.add(existing.id);
        }
      }
      
      final colors = [
        '#FF5733', '#33FF57', '#3357FF', '#FF33F5', '#33FFF5', 
        '#F5FF33', '#FF8C33', '#8C33FF', '#FF3333', '#33FF8C'
      ];
      int colorIndex = 0;

      for (String name in categoryNames) {
        Category category;
        if (existingMap.containsKey(name)) {
          category = existingMap[name]!;
        } else {
          category = Category()
            ..name = name
            ..color = colors[colorIndex % colors.length]
            ..iconCodePoint = Icons.label.codePoint
            ..keywords = name;
          colorIndex++;
        }
        await _dbService.saveCategory(category);
      }
      
      if (idsToDelete.isNotEmpty) {
        for (var id in idsToDelete) {
          await _dbService.deleteCategory(id);
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카테고리가 저장되었습니다 (${categoryNames.length}개)')),
        );
        setState(() {});
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 중 오류 발생: $e')),
        );
      }
    }
  }
}
