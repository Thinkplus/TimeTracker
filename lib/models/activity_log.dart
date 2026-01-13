import 'package:isar/isar.dart';

part 'activity_log.g.dart';

@collection
class ActivityLog {
  Id id = Isar.autoIncrement;
  
  late DateTime timestamp;
  late String content;
  late String category;
  int durationMinutes = 60; // 기본값 60분
  
  // Google Calendar Event ID (선택적)
  String? googleEventId;
  
  bool syncedToCalendar = false;
}
