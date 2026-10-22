// ignore_for_file: invalid_use_of_visible_for_testing_member
// 디자인 확인용 화면 렌더 (회귀 테스트 아님 — test/ 밖, 수동 실행):
//   flutter test tool/screenshot_test.dart --update-goldens
// 실제 내장 글꼴과 Material 아이콘을 불러와 1080×2340 PNG 로 tool/goldens/ 에 저장한다.
// 스토어용(세로 ≤ 가로×2): --dart-define=SHOT_H=1920 → tool/goldens/store/
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/main.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/quick_start_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

Future<void> _loadFonts() async {
  Future<void> fam(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await l.load();
  }

  await fam('NotoSerifKR', ['NotoSerifKR-Medium.ttf', 'NotoSerifKR-Bold.ttf']);
  await fam('PlexSansKR', [
    'IBMPlexSansKR-Regular.ttf',
    'IBMPlexSansKR-Medium.ttf',
    'IBMPlexSansKR-SemiBold.ttf'
  ]);
  await fam('PlexMono', ['IBMPlexMono-Regular.ttf', 'IBMPlexMono-Medium.ttf']);
  final icons = File(
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final l = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await l.load();
}

DividendEvent _ev(String code, String name, DateTime record, int per) => DividendEvent(
    corpCode: code, corpName: name, exDate: null, recordDate: record,
    perShare: per, isConfirmed: true);

List<Override> _overrides() => [
      holdingsProvider.overrideWith((ref) => HoldingsNotifier()
        ..add(const Holding(corpCode: '005930', corpName: '삼성전자', shares: 1200))
        ..add(const Holding(corpCode: '458730', corpName: 'TIGER 미국배당다우존스', shares: 3000))),
      retirementInputProvider.overrideWith((ref) => RetirementInputNotifier()
        ..update((s) => s.copyWith(currentAge: 66))),
      accountsProvider.overrideWith((ref) => AccountsNotifier(ref)
        ..updateDefaults('default_pension_savings',
            balance: 240000000, monthlyWithdrawal: 1420000, isWithdrawing: true)
        ..updateDefaults('default_irp',
            balance: 110000000, monthlyWithdrawal: 722000, isWithdrawing: true)
        ..updateDefaults('default_isa', balance: 30000000)),
      dividendEventsProvider.overrideWith((ref) async => DividendFetchResult(
            events: [
              _ev('005930', '삼성전자', DateTime(2026, 6, 30), 361),
              _ev('005930', '삼성전자', DateTime(2026, 9, 30), 361),
              for (var m = 1; m <= 12; m++)
                _ev('458730', 'TIGER 미국배당다우존스', DateTime(2026, m, 28), 70),
            ],
            fetchedAt: DateTime(2026, 10, 22),
            fromCache: false,
          )),
    ];

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(1080, _shotH);
  t.view.devicePixelRatio = 2.625;
}

const double _shotH = int.fromEnvironment('SHOT_H', defaultValue: 2340) + 0.0;
const String _dir = _shotH == 2340 ? 'goldens/' : 'goldens/store/';

void main() {
  setUpAll(_loadFonts);

  testWidgets('screens', (t) async {
    _phone(t);
    SharedPreferences.setMockInitialValues(
        {kDisclaimerAcceptedKey: true, kQuickStartDoneKey: true});
    await t.pumpWidget(ProviderScope(overrides: _overrides(), child: const RetirePaycheckApp()));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('${_dir}1_this_month.png'));
    await t.tap(find.byIcon(Icons.timeline_outlined));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('${_dir}2_plan.png'));
    await t.tap(find.byIcon(Icons.notifications_none_outlined));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('${_dir}3_alerts.png'));
    await t.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('${_dir}4_assets.png'));
  });

  testWidgets('quick start', (t) async {
    _phone(t);
    SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
    await t.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
    await t.pumpAndSettle();
    expect(find.byType(QuickStartScreen), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('${_dir}0_quick_start.png'));
  });
}
