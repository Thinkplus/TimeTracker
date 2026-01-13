import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  // 싱글톤 패턴
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();
  
  // GitHub 저장소 정보
  static const String _owner = 'Thinkplus';  // GitHub 사용자명
  static const String _repo = 'TimeTracker';  // 저장소 이름
  
  static const String _apiUrl = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';
  static const String _skipVersionKey = 'skip_update_version';
  
  String? _currentVersion;
  String? _latestVersion;
  String? _releaseUrl;
  String? _releaseNotes;
  String? _downloadUrl;
  
  /// 현재 앱 버전 가져오기
  Future<String> getCurrentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    
    final packageInfo = await PackageInfo.fromPlatform();
    _currentVersion = packageInfo.version;
    return _currentVersion!;
  }
  
  /// GitHub에서 최신 릴리스 정보 가져오기
  Future<bool> checkForUpdates() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 버전 정보 파싱 (v1.0.0 -> 1.0.0)
        String tagName = data['tag_name'] ?? '';
        _latestVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
        _releaseUrl = data['html_url'];
        _releaseNotes = data['body'] ?? '새로운 기능과 버그 수정이 포함되어 있습니다.';
        
        // 다운로드 URL 파싱 (macOS용 - DMG 우선, 그 다음 ZIP)
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null && assets.isNotEmpty) {
          // 먼저 DMG 파일 찾기
          for (var asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.dmg')) {
              _downloadUrl = asset['browser_download_url'];
              break;
            }
          }
          // DMG가 없으면 ZIP 파일 찾기
          if (_downloadUrl == null) {
            for (var asset in assets) {
              final name = asset['name'] as String? ?? '';
              if (name.endsWith('.zip') || name.contains('macos')) {
                _downloadUrl = asset['browser_download_url'];
                break;
              }
            }
          }
        }
        
        // 다운로드 URL이 없으면 릴리스 페이지 사용
        _downloadUrl ??= _releaseUrl;
        
        return _hasNewVersion();
      }
      
      debugPrint('UpdateService: Failed to check updates. Status: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('UpdateService: Error checking updates: $e');
      return false;
    }
  }
  
  /// 새 버전이 있는지 확인
  bool _hasNewVersion() {
    if (_currentVersion == null || _latestVersion == null) return false;
    return _compareVersions(_latestVersion!, _currentVersion!) > 0;
  }
  
  /// 버전 비교 (v1 > v2: 양수, v1 < v2: 음수, 같음: 0)
  int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map(int.parse).toList();
      final parts2 = v2.split('.').map(int.parse).toList();
      
      for (int i = 0; i < 3; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// 사용자가 이 버전을 건너뛰었는지 확인
  Future<bool> isVersionSkipped() async {
    if (_latestVersion == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final skippedVersion = prefs.getString(_skipVersionKey);
    return skippedVersion == _latestVersion;
  }
  
  /// 이 버전 건너뛰기 저장
  Future<void> skipVersion() async {
    if (_latestVersion == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skipVersionKey, _latestVersion!);
  }
  
  /// 업데이트 다이얼로그 표시
  Future<void> showUpdateDialog(BuildContext context) async {
    if (_latestVersion == null) return;
    
    // 이 버전을 건너뛴 경우 표시하지 않음
    if (await isVersionSkipped()) return;
    
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.system_update, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            const Text('업데이트 가능'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('현재 버전', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('v$_currentVersion', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('최신 버전', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('v$_latestVersion', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('릴리스 노트:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  _releaseNotes ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await skipVersion();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('이 버전 건너뛰기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              if (_downloadUrl != null) {
                final uri = Uri.parse(_downloadUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('다운로드'),
          ),
        ],
      ),
    );
  }
  
  /// 앱 시작 시 자동으로 업데이트 확인
  Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    // 데스크톱 환경에서만 실행
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    
    await getCurrentVersion();
    final hasUpdate = await checkForUpdates();
    
    if (hasUpdate && context.mounted) {
      await showUpdateDialog(context);
    }
  }
  
  // Getter들
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  String? get releaseUrl => _releaseUrl;
  String? get downloadUrl => _downloadUrl;
}
