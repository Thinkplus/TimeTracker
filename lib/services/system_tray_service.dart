import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SystemTrayService with TrayListener {
  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;
  SystemTrayService._internal();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    // 데스크톱이 아니면 스킵
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return;
    }
    
    try {
      // TrayListener 등록
      trayManager.addListener(this);
      
      // 아이콘 경로 (앱 번들 내 Resources 폴더 참조)
      // tray_manager는 앱 번들 기준 상대 경로를 사용
      String iconPath = Platform.isWindows 
          ? 'assets/images/logo.png'
          : 'assets/images/logo.png';
      
      debugPrint("TrayManager: Setting icon with path: $iconPath");

      // 트레이 아이콘 설정
      await trayManager.setIcon(iconPath);
      
      // 트레이 메뉴 설정
      Menu menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: '창 열기',
          ),
          MenuItem(
            key: 'hide_window',
            label: '창 숨기기',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: '종료',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
      
      // 툴팁 설정
      await trayManager.setToolTip('Growth Clock');
      
      _isInitialized = true;
      debugPrint("TrayManager: Initialization successful");
      
    } catch (e, stackTrace) {
      debugPrint("TrayManager: Initialization failed: $e");
      debugPrint("TrayManager: Stack trace: $stackTrace");
    }
    
    // 자동 시작 설정 초기화 (트레이와 별개로 진행)
    try {
      await _initLaunchAtStartup();
    } catch (e) {
      debugPrint("LaunchAtStartup: Initialization failed: $e");
    }
  }
  
  @override
  void onTrayIconMouseDown() {
    // 트레이 아이콘 클릭 시 창 표시
    windowManager.show();
    windowManager.focus();
  }
  
  @override
  void onTrayIconRightMouseDown() {
    // 우클릭 시 컨텍스트 메뉴 표시
    trayManager.popUpContextMenu();
  }
  
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
        windowManager.focus();
        break;
      case 'hide_window':
        windowManager.hide();
        break;
      case 'exit_app':
        _exitApp();
        break;
    }
  }
  
  Future<void> _exitApp() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _initLaunchAtStartup() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );
      debugPrint("LaunchAtStartup: Setup complete for ${packageInfo.appName}");
    } catch (e) {
      debugPrint("LaunchAtStartup: Setup failed: $e");
    }
  }
  
  void dispose() {
    trayManager.removeListener(this);
  }
}
