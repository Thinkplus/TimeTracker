import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/activity_log.dart';
import '../models/category.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();
  
  Isar? _isar;
  
  Future<Isar> get isar async {
    if (_isar != null) return _isar!;
    _isar = await _initDB();
    return _isar!;
  }
  
  Future<Isar> _initDB() async {
    final dir = await getApplicationDocumentsDirectory();
    return await Isar.open(
      [ActivityLogSchema, CategorySchema],
      directory: dir.path,
    );
  }
  
  // ========== Activity Log CRUD ==========
  
  Future<void> saveActivityLog(ActivityLog log) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.activityLogs.put(log);
    });
  }
  
  Future<List<ActivityLog>> getAllActivityLogs() async {
    final db = await isar;
    return await db.activityLogs.where().sortByTimestampDesc().findAll();
  }
  
  Future<List<ActivityLog>> getActivityLogsByDateRange(DateTime start, DateTime end) async {
    final db = await isar;
    return await db.activityLogs
        .filter()
        .timestampBetween(start, end)
        .sortByTimestampDesc()
        .findAll();
  }
  
  // 특정 시간대의 기록 가져오기 (정확한 시작 시간)
  Future<ActivityLog?> getActivityLogByTimeSlot(DateTime startTime) async {
    final db = await isar;
    return await db.activityLogs
        .filter()
        .timestampEqualTo(startTime)
        .findFirst();
  }
  
  // 시간 범위 내의 기록 가져오기 (유연한 검색)
  Future<ActivityLog?> getActivityLogInTimeRange(DateTime startTime, DateTime endTime) async {
    final db = await isar;
    final logs = await db.activityLogs
        .filter()
        .timestampBetween(startTime, endTime, includeUpper: false)
        .findAll();
    
    // 가장 최근 기록 반환
    if (logs.isEmpty) return null;
    return logs.first;
  }
  
  Future<void> deleteActivityLog(int id) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.activityLogs.delete(id);
    });
  }
  
  // ========== Category CRUD ==========
  
  Future<void> saveCategory(Category category) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.categorys.put(category);
    });
  }
  
  Future<List<Category>> getAllCategories() async {
    final db = await isar;
    final categories = await db.categorys.where().findAll();
    
    // 이름으로 중복 제거 (이름이 같으면 첫 번째 것만 유지)
    final seen = <String>{};
    final uniqueCategories = <Category>[];
    
    for (var category in categories) {
      if (!seen.contains(category.name)) {
        seen.add(category.name);
        uniqueCategories.add(category);
      }
    }
    
    return uniqueCategories;
  }
  
  // 중복된 카테고리 제거
  Future<void> cleanupDuplicateCategories() async {
    final db = await isar;
    final allCategories = await db.categorys.where().findAll();
    
    final seen = <String, Category>{};
    final duplicates = <int>[];
    
    for (var category in allCategories) {
      if (seen.containsKey(category.name)) {
        // 중복 발견 - 삭제 대상에 추가
        duplicates.add(category.id);
      } else {
        // 첫 번째 항목 - 유지
        seen[category.name] = category;
      }
    }
    
    if (duplicates.isNotEmpty) {
      await db.writeTxn(() async {
        await db.categorys.deleteAll(duplicates);
      });
      print('Removed ${duplicates.length} duplicate categories');
    }
  }
  
  Future<Category?> getCategoryByName(String name) async {
    final db = await isar;
    return await db.categorys.filter().nameEqualTo(name).findFirst();
  }
  
  Future<void> deleteCategory(int id) async {
    final db = await isar;
    await db.writeTxn(() async {
      await db.categorys.delete(id);
    });
  }
  
  // ========== 초기 카테고리 생성 ==========
  
  Future<void> createDefaultCategories() async {
    final categories = await getAllCategories();
    if (categories.isNotEmpty) return; // 이미 카테고리가 있으면 생성하지 않음
    
    final defaults = [
      Category()
        ..name = '업무'
        ..keywords = '회의,미팅,작업,개발,코딩,프로젝트,업무,일'
        ..color = '#2196F3'
        ..iconCodePoint = 0xe3af, // work
      
      Category()
        ..name = '개인'
        ..keywords = '공부,학습,운동,취미,독서,영화,게임'
        ..color = '#4CAF50'
        ..iconCodePoint = 0xe7fd, // person
      
      Category()
        ..name = '휴식'
        ..keywords = '휴식,쉬는시간,점심,저녁,식사,커피'
        ..color = '#FF9800'
        ..iconCodePoint = 0xe30c, // coffee
    ];
    
    final db = await isar;
    await db.writeTxn(() async {
      for (var category in defaults) {
        await db.categorys.put(category);
      }
    });
  }
  
  // ========== 통계 쿼리 ==========
  
  Future<Map<String, int>> getCategoryStats(DateTime start, DateTime end) async {
    final logs = await getActivityLogsByDateRange(start, end);
    final stats = <String, int>{};
    
    for (var log in logs) {
      stats[log.category] = (stats[log.category] ?? 0) + log.durationMinutes;
    }
    
    return stats;
  }
}
