import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart';

class LLMService {
  // 싱글톤 패턴
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();
  
  static const String apiKeyPrefKey = 'gemini_api_key';
  
  GenerativeModel? _model;
  String _apiKey = '';
  
  // 기본 프롬프트 템플릿 (키: pref_key, 값: default_prompt)
  static const String dailyPromptKey = 'prompt_daily';
  static const String weeklyPromptKey = 'prompt_weekly';
  static const String monthlyPromptKey = 'prompt_monthly';
  
  static const String defaultDailyPrompt = '''당신은 생산성 코치입니다. 사용자의 일일 활동을 분석하여 건설적인 피드백을 제공하세요.
**반드시 한국어로 작성하세요.**

날짜: {{DATE}}

오늘 활동:
{{STATS}}

주요 활동 내역:
{{ACTIVITIES}}

다음 형식으로 분석 결과를 **한국어로** 작성해주세요:

## 📊 오늘의 활동 요약
[간단한 요약 1-2문장]

## ✨ 잘한 점
- [구체적인 긍정적인 면 2-3가지]

## 💡 개선 제안
- [실천 가능한 구체적인 개선 방안 2-3가지]

## 🎯 내일을 위한 추천
- [내일 집중하면 좋을 활동이나 목표]

친근하고 격려하는 톤으로 작성하되, 구체적이고 실용적인 조언을 제공하세요.''';

  static const String defaultWeeklyPrompt = '''당신은 생산성 코치입니다. 사용자의 주간 활동을 분석하여 건설적인 피드백을 제공하세요.
**반드시 한국어로 작성하세요.**

기간: {{PERIOD}} (1주일)

주간 활동 통계:
{{STATS}}

주요 활동 내역:
{{ACTIVITIES}}

다음 형식으로 분석 결과를 **한국어로** 작성해주세요:

## 📊 이번 주 활동 요약
[간단한 요약 2-3문장]

## ✨ 이번 주 하이라이트
- [이번 주 가장 잘한 활동이나 성과 2-3가지]

## 📈 시간 활용 분석
- [카테고리별 시간 배분에 대한 분석]
- [효율성에 대한 코멘트]

## 💡 다음 주를 위한 제안
- [실천 가능한 구체적인 개선 방안 2-3가지]

## 🎯 주간 목표 추천
- [다음 주에 집중하면 좋을 활동이나 목표]

친근하고 격려하는 톤으로 작성하되, 구체적이고 실용적인 조언을 제공하세요.''';

  static const String defaultMonthlyPrompt = '''당신은 생산성 코치입니다. 사용자의 월간 활동을 분석하여 종합적인 피드백을 제공하세요.
**반드시 한국어로 작성하세요.**

기간: {{PERIOD}} (1개월)

월간 활동 통계:
{{STATS}}

주요 활동 내역 (일부):
{{ACTIVITIES}}

다음 형식으로 분석 결과를 **한국어로** 작성해주세요:

## 📊 이번 달 활동 요약
[간단한 요약 2-3문장]

## 🏆 이번 달의 성과
- [이번 달 가장 잘한 활동이나 성과 3-4가지]

## 📈 시간 활용 분석
- [카테고리별 시간 배분에 대한 심층 분석]
- [가장 많은 시간을 투자한 영역과 그 의미]
- [시간 활용 효율성에 대한 코멘트]

## 💡 개선이 필요한 영역
- [더 시간을 투자하면 좋을 영역]
- [줄이거나 효율화할 수 있는 부분]

## 🎯 다음 달 목표 제안
- [구체적이고 달성 가능한 월간 목표 2-3가지]
- [습관 형성을 위한 제안]

## 💬 코치의 한마디
[격려와 동기부여가 되는 메시지]

친근하고 격려하는 톤으로 작성하되, 데이터 기반의 구체적이고 실용적인 조언을 제공하세요.''';
  
  /// API 키 초기화 및 모델 생성
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(apiKeyPrefKey) ?? '';
    
    if (_apiKey.isEmpty) {
      print('⚠️ Gemini API 키가 설정되지 않았습니다.');
      print('📋 설정 > AI 탭에서 API 키를 입력해주세요.');
      return;
    }
    
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: _apiKey,
    );
  }
  
  /// API 키 저장 및 모델 재초기화
  static Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(apiKeyPrefKey, apiKey);
  }
  
  /// 저장된 API 키 가져오기
  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(apiKeyPrefKey) ?? '';
  }
  
  bool get isConfigured => _apiKey.isNotEmpty && _model != null;
  
  /// SharedPreferences에서 프롬프트 로드
  Future<String> _getPrompt(String key, String defaultPrompt) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultPrompt;
  }
  
  /// 활동 내용을 분석하여 적절한 카테고리를 추천합니다.
  Future<String?> suggestCategory(String content, List<Category> availableCategories) async {
    print('🤖 [LLM] suggestCategory 호출됨');
    print('   - 입력 내용: "$content"');
    print('   - API 키 설정 여부: $isConfigured');
    
    if (!isConfigured || content.trim().isEmpty || availableCategories.isEmpty) {
      if (!isConfigured) {
        print('   ❌ API 키가 설정되지 않아 LLM 분석을 건너뜁니다.');
      }
      return null;
    }
    
    try {
      print('   📋 사용 가능한 카테고리: ${availableCategories.map((c) => c.name).join(", ")}');
      
      // 카테고리 목록을 문자열로 변환
      final categoryList = availableCategories.map((c) {
        final keywords = c.keywordList.isEmpty ? '' : ' (키워드: ${c.keywordList.join(', ')})';
        return '- ${c.name}$keywords';
      }).join('\n');
      
      final prompt = '''
당신은 활동 기록을 분석하여 적절한 카테고리를 추천하는 AI 어시스턴트입니다.

사용 가능한 카테고리:
$categoryList

활동 내용: "$content"

위 활동 내용을 분석하여 가장 적절한 카테고리 하나를 선택하세요.
카테고리 이름만 정확히 답변하세요. 설명이나 추가 텍스트는 포함하지 마세요.

답변 형식: [카테고리 이름]
''';
      
      print('   🚀 Gemini API 호출 중...');
      final response = await _model!.generateContent([Content.text(prompt)]);
      final suggestion = response.text?.trim();
      
      print('   💡 Gemini 응답: "$suggestion"');
      
      if (suggestion == null || suggestion.isEmpty) {
        print('   ❌ 빈 응답 받음');
        return null;
      }
      
      // 대괄호 제거 및 정리
      String cleanedSuggestion = suggestion
          .replaceAll('[', '')
          .replaceAll(']', '')
          .trim();
      
      print('   🧹 정리된 응답: "$cleanedSuggestion"');
      
      // 반환된 카테고리가 실제로 존재하는지 확인
      final matchedCategory = availableCategories.firstWhere(
        (c) => c.name == cleanedSuggestion,
        orElse: () {
          print('   ⚠️ 일치하는 카테고리를 찾을 수 없음. 첫 번째 카테고리 사용');
          return availableCategories.first;
        },
      );
      
      print('   ✅ 최종 선택된 카테고리: ${matchedCategory.name}');
      return matchedCategory.name;
    } catch (e, stackTrace) {
      print('   ❌ Error suggesting category: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// 활동 내용과 카테고리를 기반으로 캘린더 이벤트 제목을 생성합니다.
  String generateEventTitle(String category) {
    return '[$category]';
  }
  
  /// 일일 활동을 분석하여 인사이트를 제공합니다.
  Future<String?> analyzeDailyActivity({
    required DateTime date,
    required Map<String, int> categoryStats,
    required List<String> activities,
  }) async {
    if (!isConfigured) return null;
    
    try {
      print('🤖 [LLM] 일일 활동 분석 시작');
      
      final statsBuffer = _buildStatsBuffer(categoryStats);
      final activitiesInfo = activities.take(20).join('\n');
      final dateStr = '${date.year}년 ${date.month}월 ${date.day}일';
      
      // 저장된 프롬프트 로드
      String promptTemplate = await _getPrompt(dailyPromptKey, defaultDailyPrompt);
      
      // 플레이스홀더 치환
      final prompt = promptTemplate
          .replaceAll('{{DATE}}', dateStr)
          .replaceAll('{{STATS}}', statsBuffer)
          .replaceAll('{{ACTIVITIES}}', activitiesInfo);
      
      print('   🚀 Gemini API 호출 중...');
      final response = await _model!.generateContent([Content.text(prompt)]);
      final analysis = response.text?.trim();
      
      print('   ✅ 분석 완료');
      return analysis;
    } catch (e, stackTrace) {
      print('   ❌ Error analyzing daily activity: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// 주간 활동을 분석하여 인사이트를 제공합니다.
  Future<String?> analyzeWeeklyActivity({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, int> categoryStats,
    required List<String> activities,
  }) async {
    if (!isConfigured) return null;
    
    try {
      print('🤖 [LLM] 주간 활동 분석 시작');
      
      final statsBuffer = _buildStatsBuffer(categoryStats);
      final activitiesInfo = activities.take(30).join('\n');
      final periodStr = '${startDate.month}/${startDate.day} ~ ${endDate.month}/${endDate.day}';
      
      // 저장된 프롬프트 로드
      String promptTemplate = await _getPrompt(weeklyPromptKey, defaultWeeklyPrompt);
      
      // 플레이스홀더 치환
      final prompt = promptTemplate
          .replaceAll('{{PERIOD}}', periodStr)
          .replaceAll('{{STATS}}', statsBuffer)
          .replaceAll('{{ACTIVITIES}}', activitiesInfo);
      
      print('   🚀 Gemini API 호출 중...');
      final response = await _model!.generateContent([Content.text(prompt)]);
      final analysis = response.text?.trim();
      
      print('   ✅ 분석 완료');
      return analysis;
    } catch (e, stackTrace) {
      print('   ❌ Error analyzing weekly activity: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// 월간 활동을 분석하여 인사이트를 제공합니다.
  Future<String?> analyzeMonthlyActivity({
    required int year,
    required int month,
    required Map<String, int> categoryStats,
    required List<String> activities,
  }) async {
    if (!isConfigured) return null;
    
    try {
      print('🤖 [LLM] 월간 활동 분석 시작');
      
      final statsBuffer = _buildStatsBuffer(categoryStats);
      final activitiesInfo = activities.take(50).join('\n');
      final periodStr = '$year년 $month월';
      
      // 저장된 프롬프트 로드
      String promptTemplate = await _getPrompt(monthlyPromptKey, defaultMonthlyPrompt);
      
      // 플레이스홀더 치환
      final prompt = promptTemplate
          .replaceAll('{{PERIOD}}', periodStr)
          .replaceAll('{{STATS}}', statsBuffer)
          .replaceAll('{{ACTIVITIES}}', activitiesInfo);
      
      print('   🚀 Gemini API 호출 중...');
      final response = await _model!.generateContent([Content.text(prompt)]);
      final analysis = response.text?.trim();
      
      print('   ✅ 분석 완료');
      return analysis;
    } catch (e, stackTrace) {
      print('   ❌ Error analyzing monthly activity: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// 통계 데이터를 문자열로 변환
  String _buildStatsBuffer(Map<String, int> stats) {
    final buffer = StringBuffer();
    int total = stats.values.isEmpty ? 0 : stats.values.reduce((a, b) => a + b);
    buffer.writeln('총 ${total ~/ 60}시간 ${total % 60}분');
    for (var entry in stats.entries) {
      final hours = entry.value ~/ 60;
      final minutes = entry.value % 60;
      buffer.writeln('- ${entry.key}: ${hours}h ${minutes}m');
    }
    return buffer.toString();
  }
}
