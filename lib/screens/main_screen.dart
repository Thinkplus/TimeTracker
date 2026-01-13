import 'package:flutter/material.dart';
import 'calendar_home_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import '../services/update_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  
  // GlobalKey for CalendarHomeScreen
  final GlobalKey<CalendarHomeScreenState> _calendarKey = GlobalKey<CalendarHomeScreenState>();
  
  late final List<Widget> _screens;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _screens = [
      CalendarHomeScreen(key: _calendarKey),
      const ReportsScreen(),
      const SettingsScreen(),
    ];
    
    // 앱 시작 후 업데이트 확인 (약간의 딜레이 후)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          UpdateService().checkAndShowUpdateDialog(context);
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱이 다시 활성화되면 UI만 갱신 (창 표시는 MyApp에서 처리)
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  icon: Icons.event_note_outlined,
                  activeIcon: Icons.event_note,
                  label: 'Log',
                  index: 0,
                ),
                _buildNavItem(
                  icon: Icons.insert_chart_outlined,
                  activeIcon: Icons.insert_chart,
                  label: 'Report',
                  index: 1,
                ),
                _buildNavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Settings',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddActivityDialog,
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
        child: const Icon(Icons.add, size: 28, color: Colors.white),
      ),
    );
  }
  
  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _currentIndex == index;
    final color = isActive ? Theme.of(context).primaryColor : Colors.grey.shade400;
    
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: color,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showAddActivityDialog() {
    // Switch to activity tab if not already there
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
    
    // Call the public showInputDialog method
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calendarKey.currentState?.showInputDialog();
    });
  }
}
