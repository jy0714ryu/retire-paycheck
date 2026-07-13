// 화면3 v2 바인딩 — buildGauges accounts/interestItems 전달 + ISA 절세효과 카드
// + 연금 모드 OFF 참고용 캡션.
// 시드: ISA 계좌 B사 1,000주 · per_share 500 · 2026-04 지급 (ISA 배당 gross 50만).
// ISA 절세효과 = 50만 × 15.4% = 77,000원 → "7만원"(정수 절사).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/account.dart';
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

// v4: 참고용 캡션 게이트는 전역 input.isWithdrawing 이 아니라 계좌별
// Account.isWithdrawing (Task 6) — 아래 두 input 은 게이지 값 계산용으로만
// 남고, 캡션 노출 여부는 _pump 의 [accounts] 로 주입한다.
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
  // v4: 참고용 캡션 판정용 계좌 주입. null 이면 기본 4계좌(전부
  // isWithdrawing=false)만 사용.
  List<Account>? accounts,
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
        if (accounts != null)
          accountsProvider.overrideWith((ref) {
            final n = AccountsNotifier(ref);
            for (final a in accounts) {
              n.add(a);
            }
            return n;
          }),
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

  testWidgets('인출 켠 pension 계좌 없으면 저율과세 게이지에 인출 전 참고용 캡션',
      (WidgetTester tester) async {
    // 기본 4계좌(연금저축·IRP 포함)는 전부 isWithdrawing=false — 오버라이드 불필요.
    await _pump(tester, input: _inputNotWithdrawing);

    expect(find.text('연금 인출 전 (참고용)'), findsOneWidget);
  });

  testWidgets('인출 켠 pension 계좌 있으면 인출 전 참고용 캡션 미노출',
      (WidgetTester tester) async {
    await _pump(
      tester,
      input: _inputWithdrawing,
      accounts: const [
        Account(
          id: 'wp',
          name: '연금인출',
          type: AccountType.pension,
          monthlyWithdrawal: 500000,
          isWithdrawing: true,
        ),
      ],
    );

    expect(find.text('연금 인출 전 (참고용)'), findsNothing);
  });

  testWidgets('연금 계좌 있어도 인출 OFF 면 참고용 캡션 노출 유지',
      (WidgetTester tester) async {
    // 계좌가 존재해도 isWithdrawing=false 면 여전히 참고용 — 계좌 존재 자체가
    // 아니라 인출 개시 여부가 판정 기준임을 검증.
    await _pump(
      tester,
      input: _inputWithdrawing,
      accounts: const [
        Account(
          id: 'wp',
          name: '연금인출',
          type: AccountType.pension,
          monthlyWithdrawal: 500000,
          isWithdrawing: false,
        ),
      ],
    );

    expect(find.text('연금 인출 전 (참고용)'), findsOneWidget);
  });
}
