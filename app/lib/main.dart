import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/calendar_screen.dart';
import 'screens/gauge_screen.dart';
import 'screens/input_screen.dart';
import 'services/ad_service.dart';
import 'services/migration.dart';
import 'theme/app_colors.dart';
import 'widgets/disclaimer_dialog.dart';

/// 첫 실행 면책 동의 여부 저장 키(SharedPreferences).
const String kDisclaimerAcceptedKey = 'disclaimer_accepted';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // v1→v2 스키마 마이그레이션 — 스토어 로드보다 먼저 완료돼야 한다.
  await runMigrations(await SharedPreferences.getInstance());
  // AdMob SDK 초기화 (플랫폼 채널 부재 환경에서는 조용히 흡수).
  AdService().initialize();
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
  void initState() {
    super.initState();
    _maybeShowDisclaimer();
  }

  /// 첫 실행 시(미동의) 면책 다이얼로그를 1회 표시한다.
  Future<void> _maybeShowDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kDisclaimerAcceptedKey) ?? false) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DisclaimerDialog(
          onAccept: () async {
            await prefs.setBool(kDisclaimerAcceptedKey, true);
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
          },
        ),
      );
    });
  }

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
