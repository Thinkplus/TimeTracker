import 'package:isar/isar.dart';

part 'category.g.dart';

@collection
class Category {
  Id id = Isar.autoIncrement;
  
  @Index(unique: true)
  late String name;
  
  // 카테고리를 자동으로 인식하기 위한 키워드 리스트 (쉼표로 구분된 문자열)
  String keywords = '';
  
  // 카테고리 색상 (Hex 코드)
  String color = '#4CAF50';
  
  // 카테고리 아이콘 (Material Icons codePoint)
  int iconCodePoint = 0xe3af; // work icon
  
  DateTime createdAt = DateTime.now();
  
  // 키워드 리스트로 변환
  List<String> get keywordList {
    if (keywords.isEmpty) return [];
    return keywords.split(',').map((k) => k.trim().toLowerCase()).toList();
  }
  
  // 키워드 설정
  void setKeywords(List<String> list) {
    keywords = list.join(',');
  }
}
