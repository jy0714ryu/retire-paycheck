// 화면3 v2 바인딩 — buildGauges accounts/interestItems 전달 + ISA 절세효과 카드
// + 연금 모드 OFF 참고용 캡션.
// 시드: ISA 계좌 B사 1,000주 · per_share 500 · 2026-04 지급 (ISA 배당 gross 50만).
// ISA 절세효과 = 50만 × 15.4% = 77,000원 → "7만원"(정수 절사).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/gauge_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

final _eventIsa = DividendEvent(
  corpCode: 'B',
  corpName: 'ISA주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);

final _eventGeneral = DividendEvent(
  corpCode: 'A',
  corpName: '일반주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);

const _inputWithdrawing = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 500000,
  monthlyOtherWithdrawal: 0,
  annualInterestIncome: 0,
);

const _inputNotWithdrawing = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 500000,
  monthlyOtherWithdrawal: 0,
  annualInterestIncome: 0,
  isWithdrawing: false,
);

Future<void> _pump(
  WidgetTester tester, {
  List<Holding> holdings = const [],
  List<DividendEvent> events = const [],
  RetirementInput input = _inputWithdrawing,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        holdingsProvider.overrideWith((ref) {
          final n = HoldingsNotifier();
          for (final h in holdings) {
            n.add(h);
          }
          return n;
        }),
        retirementInputProvider.overrideWith(
          (ref) => RetirementInputNotifier()..update((_) => input),
        ),
        dividendEventsProvider.overrideWith(
          (ref) async => DividendFetchResult(
            events: events,
            fetchedAt: DateTime(2026, 1, 1),
            fromCache: false,
          ),
        ),
      ],
      child: const MaterialApp(home: GaugeScreen(year: 2026)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ISA 계좌 배당 있으면 절세효과 카드 노출', (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [
        Holding(
          corpCode: 'B',
          corpName: 'ISA주',
          shares: 1000,
          accountId: 'default_isa',
        ),
      ],
      events: [_eventIsa],
    );

    // ISA 배당 gross 50만 × 15.4% = 77,000원 → 만원 단위 절사 "7만원".
    expect(find.textContaining('ISA 덕분에 연 7만원 절세 중'), findsOneWidget);
    expect(find.text('(일반계좌 대비 · 비과세 한도 내 기준)'), findsOneWidget);
  });

  testWidgets('ISA 절세액 1만원 미만이면 카드 미노출 ("0만원" 방지)',
      (WidgetTester tester) async {
    // 10주 × 500원 = gross 5,000원 → 절세 770원 (만원 표시 0) → 미노출.
    await _pump(
      tester,
      holdings: const [
        Holding(
          corpCode: 'B',
          corpName: 'ISA주',
          shares: 10,
          accountId: 'default_isa',
        ),
      ],
      events: [_eventIsa],
    );

    expect(find.textContaining('절세 중'), findsNothing);
  });

  testWidgets('ISA 계좌 없으면 절세효과 카드 미노출', (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [
        Holding(corpCode: 'A', corpName: '일반주', shares: 1000),
      ],
      events: [_eventGeneral],
    );

    expect(find.textContaining('절세 중'), findsNothing);
  });

  testWidgets('연금 모드 OFF 시 저율과세 게이지에 인출 전 참고용 캡션', (WidgetTester tester) async {
    await _pump(tester, input: _inputNotWithdrawing);

    expect(find.text('연금 인출 전 (참고용)'), findsOneWidget);
  });

  testWidgets('연금 모드 ON 시 인출 전 참고용 캡션 미노출', (WidgetTester tester) async {
    await _pump(tester, input: _inputWithdrawing);

    expect(find.text('연금 인출 전 (참고용)'), findsNothing);
  });
}
