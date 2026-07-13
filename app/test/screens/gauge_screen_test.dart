// 화면3 세금 임계치 게이지 — 색 규칙·퍼센트 텍스트·참고용 배지·경고 문구 검증.
// Task 4 게이지 시나리오 재사용:
//   A사 1,000주 / per_share 500 / 2025-12 기준일 → 2026-04 지급 (연 배당 gross 50만).
//   나이 60, 과세 인출 월 100만(연 1,200만), 비과세 월 50만, 이자 0.
// 기대 게이지:
//   금융소득 = 50만 ÷ 2,000만 = 2.5%   (초록, <80%)
//   사적연금 = 1,200만 ÷ 1,500만 = 80%  (노랑, 0.8~1.0)
//   건보     = 금융 1,000만 이하 → 산입 0 (사적연금 미산입) = 0 ÷ 2,000만 = 0% (초록)
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
import 'package:retire_paycheck/theme/app_colors.dart';

final _eventA = DividendEvent(
  corpCode: 'A',
  corpName: 'A사',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);

const _input = RetirementInput(
  pensionSavings: 100000000,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 1000000, // 연 1,200만 (저율 한도 1,500만의 80%)
  monthlyOtherWithdrawal: 500000,
  annualInterestIncome: 0,
);

// 과세 인출 월 200만 → 연 2,400만 → 사적연금 ratio 1.6 (빨강·경고).
const _inputOver = RetirementInput(
  pensionSavings: 100000000,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 2000000,
  monthlyOtherWithdrawal: 500000,
  annualInterestIncome: 0,
);

Future<void> _pumpGauge(
  WidgetTester tester, {
  required RetirementInput input,
  // v4: 인출 게이트는 계좌별 isWithdrawing — 과세 인출은 인출을 켠 pension
  // 계좌 monthlyWithdrawal 로 주입.
  int monthlyPensionWithdrawal = 1000000,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        holdingsProvider.overrideWith(
          (ref) => HoldingsNotifier()
            ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
        ),
        retirementInputProvider.overrideWith(
          (ref) => RetirementInputNotifier()..update((_) => input),
        ),
        accountsProvider.overrideWith(
          (ref) => AccountsNotifier(ref)
            ..add(Account(
                id: 'wp',
                name: '연금인출',
                type: AccountType.pension,
                monthlyWithdrawal: monthlyPensionWithdrawal,
                isWithdrawing: true)),
        ),
        dividendEventsProvider.overrideWith((ref) async => DividendFetchResult(
              events: [_eventA],
              fetchedAt: DateTime(2026, 1, 1),
              fromCache: false,
            )),
      ],
      child: const MaterialApp(home: GaugeScreen(year: 2026)),
    ),
  );
  await tester.pumpAndSettle();
}

/// 진행바 색 조회 헬퍼 — 카드 타이틀을 앵커로 같은 카드 안의 진행바 색을 읽는다.
Color _barColorForCard(WidgetTester tester, String title) {
  final indicator = find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(Container),
    ),
    matching: find.byType(LinearProgressIndicator),
  );
  final bar = tester.widget<LinearProgressIndicator>(indicator.first);
  return (bar.valueColor as AlwaysStoppedAnimation<Color>).value;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('게이지 3종 퍼센트 텍스트 + 참고용 배지', (WidgetTester tester) async {
    await _pumpGauge(tester, input: _input);

    // 금융소득 종합과세: 50만 ÷ 2,000만 (2.5%).
    expect(find.text('금융소득 종합과세'), findsOneWidget);
    expect(
      find.textContaining('연간 50만원 ÷ 기준 2,000만원 (2.5%)'),
      findsOneWidget,
    );

    // 사적연금 저율과세 한도: 1,200만 ÷ 1,500만 (80%).
    expect(find.text('사적연금 저율과세 한도'), findsOneWidget);
    expect(
      find.textContaining('연간 1,200만원 ÷ 기준 1,500만원 (80%)'),
      findsOneWidget,
    );

    // 건강보험: 산입 0 → 0 ÷ 2,000만 (0%) + 참고용 배지 + 디스클레이머 상시.
    expect(find.text('건강보험 피부양자 소득'), findsOneWidget);
    expect(
      find.textContaining('연간 0만원 ÷ 기준 2,000만원 (0%)'),
      findsOneWidget,
    );
    expect(find.text('참고용'), findsOneWidget);
    expect(
      find.text('공적연금·기타 소득 합산에 따라 달라질 수 있으며, 사적연금 인출은 포함되지 않습니다 (기준: 2026-07 현행)'),
      findsOneWidget,
    );

    // 색: 금융(2.5%)·건보(0%)=초록, 사적연금(80%)=노랑.
    expect(_barColorForCard(tester, '금융소득 종합과세'), AppColors.success);
    expect(_barColorForCard(tester, '건강보험 피부양자 소득'), AppColors.success);
    expect(_barColorForCard(tester, '사적연금 저율과세 한도'), AppColors.warning);

    // 임계치 미초과 → 경고 문구 없음.
    expect(find.textContaining('16.5% 과세로 전환'), findsNothing);
  });

  testWidgets('사적연금 ratio 1.6 초과 → 빨강 + 경고 문구', (WidgetTester tester) async {
    await _pumpGauge(tester,
        input: _inputOver, monthlyPensionWithdrawal: 2000000);

    // 사적연금: 2,400만 ÷ 1,500만 (160%).
    expect(
      find.textContaining('연간 2,400만원 ÷ 기준 1,500만원 (160%)'),
      findsOneWidget,
    );
    // 빨강 진행바.
    expect(_barColorForCard(tester, '사적연금 저율과세 한도'), AppColors.error);
    // 경고 한 줄.
    expect(
      find.text('1,500만원을 넘으면 초과분이 아니라 전액이 16.5% 과세로 전환될 수 있습니다'),
      findsOneWidget,
    );
  });
}
