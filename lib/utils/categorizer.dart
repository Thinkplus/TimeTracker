import '../models/category.dart';

class Categorizer {
  /// 텍스트 내용과 카테고리 리스트를 받아서 가장 적합한 카테고리명 반환
  /// 매칭되는 키워드가 없으면 기본 카테고리 반환
  static String categorize(String content, List<Category> categories) {
    if (content.isEmpty || categories.isEmpty) {
      return '기타';
    }
    
    final lowerContent = content.toLowerCase();
    
    // 각 카테고리별로 매칭되는 키워드 개수 카운트
    Map<String, int> matchCounts = {};
    
    for (var category in categories) {
      int count = 0;
      for (var keyword in category.keywordList) {
        if (lowerContent.contains(keyword)) {
          count++;
        }
      }
      if (count > 0) {
        matchCounts[category.name] = count;
      }
    }
    
    // 가장 많이 매칭된 카테고리 찾기
    if (matchCounts.isEmpty) {
      return categories.first.name; // 기본값으로 첫 번째 카테고리 반환
    }
    
    var sortedEntries = matchCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedEntries.first.key;
  }
}
