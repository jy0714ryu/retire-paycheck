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
import 'package:retire_paycheck/health_engine/engine.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/services/health_bridge.dart';
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
        // 번들 비동기 로드 대신 파일에서 미리 읽은 2026 요율 (타이밍 흔들림 방지).
        healthParamsProvider.overrideWith((ref) async => _params),
        holdingsProvider.overrideWith(
          (ref) => HoldingsNotifier()
            ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
        ),
        retirementInputProvider.overrideWith(
          (ref) => RetirementInputNotifier()..update((_) => input),
        ),
        accountsProvider.overrideWith(
          (ref) => AccountsNotifier(ref)
            ..add(
              Account(
                id: 'wp',
                name: '연금인출',
                type: AccountType.pension,
                monthlyWithdrawal: monthlyPensionWithdrawal,
                balance: 100000000,
                isWithdrawing: true,
              ),
            ),
        ),
        dividendEventsProvider.overrideWith(
          (ref) async => DividendFetchResult(
            events: [_eventA],
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

/// 진행바 색 조회 헬퍼 — 카드 타이틀을 앵커로 같은 카드 안의 진행바 색을 읽는다.
Color _barColorForCard(WidgetTester tester, String title) {
  final indicator = find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(Container)),
    matching: find.byType(LinearProgressIndicator),
  );
  final bar = tester.widget<LinearProgressIndicator>(indicator.first);
  return (bar.valueColor as AlwaysStoppedAnimation<Color>).value;
}

late HealthParams _params;

void main() {
  setUpAll(() async {
    _params = await HealthParams.load(const FileParamsSource(), 2026);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('게이지 3종 퍼센트 텍스트 + 참고용 배지', (WidgetTester tester) async {
    await _pumpGauge(tester, input: _input);

    // 금융소득 종합과세: 50만 ÷ 2,000만 (2.5%).
    expect(find.text('금융소득 종합과세'), findsOneWidget);
    expect(find.textContaining('연간 50만원 ÷ 기준 2,000만원 (2.5%)'), findsOneWidget);

    // 사적연금 저율과세 한도: 1,200만 ÷ 1,500만 (80%).
    expect(find.text('사적연금 저율과세 한도'), findsOneWidget);
    expect(
      find.textContaining('연간 1,200만원 ÷ 기준 1,500만원 (80%)'),
      findsOneWidget,
    );

    // 건강보험(피부양자 기본, v2.2 건보료나침반 엔진): 소득 0 ÷ 한도 2,000만 + 계산상 유지.
    expect(find.text('건강보험 피부양자'), findsOneWidget);
    expect(find.text('계산상 유지'), findsOneWidget);
    expect(find.textContaining('연 소득 0만원 ÷ 한도 2,000만원 (0%)'), findsOneWidget);
    expect(find.text('재산 미입력 — 5.4억 이하로 가정'), findsOneWidget);
    expect(find.text('참고용'), findsNothing);

    // 색: 금융(2.5%)·건보(0%)=초록, 사적연금(80%)=노랑.
    expect(_barColorForCard(tester, '금융소득 종합과세'), AppColors.success);
    expect(_barColorForCard(tester, '건강보험 피부양자'), AppColors.success);
    expect(_barColorForCard(tester, '사적연금 저율과세 한도'), AppColors.warning);

    // 임계치 미초과 → 경고 문구 없음.
    expect(find.textContaining('16.5% 과세로 전환'), findsNothing);
  });

  testWidgets('사적연금 ratio 1.6 초과 → 빨강 + 경고 문구', (WidgetTester tester) async {
    await _pumpGauge(
      tester,
      input: _inputOver,
      monthlyPensionWithdrawal: 2000000,
    );

    // 사적연금: 2,400만 ÷ 1,500만 (160%).
    expect(
      find.textContaining('연간 2,400만원 ÷ 기준 1,500만원 (160%)'),
      findsOneWidget,
    );
    // 빨강 진행바.
    expect(_barColorForCard(tester, '사적연금 저율과세 한도'), AppColors.error);
    // 경고 한 줄.
    expect(find.text('1,500만원을 넘으면 전액 16.5% 과세될 수 있어요'), findsOneWidget);
    // v2.3.1 요약 카드: 연금 저율 한도를 넘었으니 "기준을 넘은 항목 1개".
    await tester.scrollUntilVisible(
      find.byKey(const Key('tax_hero_headline')),
      -300,
    );
    expect(find.text('기준을 넘은 항목 1개'), findsOneWidget);
  });

  group('건보료나침반 엔진 카드 (v2.2)', () {
    testWidgets('지역가입자 — 예상 월 건보료(원 단위)와 내역', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(
          healthInsType: HealthInsType.regional,
          publicPensionMonthly: 1500000,
          propertyTaxBase: 300000000,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('regional_total')), findsOneWidget);
      expect(find.textContaining('소득분'), findsOneWidget);
      expect(find.textContaining('재산분'), findsOneWidget);
    });

    testWidgets('피부양자 — 재산 과세표준 9억 초과면 계산상 탈락 가능 + 사유', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(propertyTaxBase: 1000000000),
      );
      await tester.pumpAndSettle();
      expect(find.text('계산상 탈락 가능'), findsOneWidget);
      expect(find.textContaining('9억원을 넘어요'), findsOneWidget);
    });

    testWidgets('피부양자 — 재산 5.4억~9억이면 소득 한도 1,000만원으로 판정', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(
          propertyTaxBase: 700000000,
          publicPensionMonthly: 1000000, // 연 1,200만 > 1,000만
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('5.4억~9억 구간'), findsWidgets);
      expect(find.text('계산상 탈락 가능'), findsOneWidget);
    });

    testWidgets('퇴직 전 월급을 넣으면 퇴직 후 36개월 비교 카드', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(
          healthInsType: HealthInsType.employee,
          lastMonthlySalary: 5000000,
        ),
      );
      await tester.pumpAndSettle();
      final card = find.text('퇴직 후 건보료 비교 (36개월)');
      await tester.scrollUntilVisible(card, 200);
      expect(card, findsOneWidget);
      expect(find.byKey(const Key('retire_compare_cheapest')), findsOneWidget);
      expect(find.textContaining('추천'), findsNothing);
      expect(find.textContaining('재산 미입력 → 지역 재산분 0'), findsOneWidget);
    });

    testWidgets('피부양자 — 사업자등록 없어도 사업·임대 소득 500만원 넘으면 탈락 가능', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(otherAnnualIncome: 7000000),
      );
      await tester.pumpAndSettle();
      expect(find.text('계산상 탈락 가능'), findsOneWidget);
      expect(find.textContaining('500만원을 넘어요'), findsOneWidget);
    });

    testWidgets('지금 피부양자면 퇴직 전 월급이 있어도 퇴직 후 비교는 숨김', (tester) async {
      await _pumpGauge(
        tester,
        input: _input.copyWith(lastMonthlySalary: 5000000),
      );
      await tester.pumpAndSettle();
      expect(find.text('퇴직 후 건보료 비교 (36개월)'), findsNothing);
    });
  });
}
