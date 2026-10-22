import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/calendar_screen.dart';
import 'screens/gauge_screen.dart';
import 'screens/input_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/quick_start_screen.dart';
import 'services/ad_service.dart';
import 'services/migration.dart';
import 'theme/app_theme.dart';
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
      theme: buildPrivateBankingTheme(),
      home: const HomeShell(),
    );
  }
}

/// 하단 4탭 셸 (v2): 이번 달 / 계획 / 경보 / 내 자산. 기본 탭 = 이번 달.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const int kPlanTab = 1;
  static const int kAssetsTab = 3;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _maybeShowDisclaimer();
  }

  /// 첫 실행 시(미동의) 면책 다이얼로그를 1회 표시하고, 이어서 첫 실행 화면(세 칸 입력)을 띄운다.
  Future<void> _maybeShowDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kDisclaimerAcceptedKey) ?? false) {
      _maybeShowQuickStart(prefs);
      return;
    }
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
            _maybeShowQuickStart(prefs);
          },
        ),
      );
    });
  }

  void _maybeShowQuickStart(SharedPreferences prefs) {
    if (!needsQuickStart(
      storedKeys: prefs.getKeys(),
      done: prefs.getBool(kQuickStartDoneKey) ?? false,
    )) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 뒤로 가기로 닫아도 건너뛰기와 같게 본다 — 매 실행마다 다시 뜨지 않도록.
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (routeContext) => QuickStartScreen(
                onDone: () async {
                  await prefs.setBool(kQuickStartDoneKey, true);
                  if (!routeContext.mounted) return;
                  Navigator.of(routeContext).pop();
                  if (mounted) setState(() => _index = 0);
                },
              ),
            ),
          )
          .then((_) => prefs.setBool(kQuickStartDoneKey, true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const CalendarScreen(),
      PlanScreen(onGoToAssets: () => setState(() => _index = kAssetsTab)),
      const GaugeScreen(),
      InputScreen(onGoToPlan: () => setState(() => _index = kPlanTab)),
    ];
    return Scaffold(
      body: SafeArea(child: tabs[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '이번 달',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: '계획',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: '경보',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '내 자산',
          ),
        ],
      ),
    );
  }
}
