import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/calendar_screen.dart';
import 'screens/gauge_screen.dart';
import 'screens/input_screen.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const ProviderScope(child: RetirePaycheckApp()));
}

class RetirePaycheckApp extends StatelessWidget {
  const RetirePaycheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '은퇴월급',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          primary: AppColors.navy,
        ),
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

/// 하단 3탭 셸: 입력 / 달력 / 게이지.
/// 각 탭은 후속 태스크(5·6·7)에서 실제 화면으로 교체될 빈 placeholder.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    InputScreen(),
    CalendarScreen(),
    GaugeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _tabs[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: '입력',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '달력',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: '게이지',
          ),
        ],
      ),
    );
  }
}
