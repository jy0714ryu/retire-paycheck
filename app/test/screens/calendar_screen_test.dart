// 화면2 은퇴 월급 달력 — 월 네비게이션 + 세후 메인 카드 합계 텍스트 검증.
// Task 4 시나리오 재사용: A사 1,000주 / per_share 500 / 2025-12 기준일 → 2026-04 지급.
// 나이 60(세율 5.5%), 과세 인출 월 100만, 비과세 월 50만.
// 기대: 4월 실수령(net) = 1,868,000원 → 186.8만원(만원 단위 소수 한 자리 표시).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/calendar_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';
import 'package:retire_paycheck/theme/app_colors.dart';

/// 금액 문구 찾기 — 일반 텍스트 "186.8만원" 과 v2 메인 카드의 분리 표기 "186.8 만원"(RichText) 모두 인식.
Finder findWon(String man) => find.byWidgetPredicate((w) {
  if (w is Text) {
    if (w.data == '$man만원') return true;
    final span = w.textSpan?.toPlainText();
    return span == '$man 만원' || span == '$man만원';
  }
  return false;
});

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
  monthlyPensionWithdrawal: 1000000,
  monthlyOtherWithdrawal: 500000,
  annualInterestIncome: 0,
);

// v4: 인출 게이트는 계좌별 isWithdrawing — 과세 월 100만(pension ON) +
// 비과세 월 50만(isa ON). 인출을 켠 계좌만 엔진에 산입된다.
List<Override> _withdrawAccountsOverride() => [
  accountsProvider.overrideWith(
    (ref) => AccountsNotifier(ref)
      ..add(
        const Account(
          id: 'wp',
          name: '연금인출',
          type: AccountType.pension,
          monthlyWithdrawal: 1000000,
          balance: 100000000,
          isWithdrawing: true,
        ),
      )
      ..add(
        const Account(
          id: 'wi',
          name: 'ISA인출',
          type: AccountType.isa,
          monthlyWithdrawal: 500000,
          balance: 100000000,
          isWithdrawing: true,
        ),
      ),
  ),
];

Future<void> _pumpCalendar(
  WidgetTester tester, {
  DateTime? initialMonth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // StateNotifier 를 시드값으로 주입(async prefs 로드에 비의존 — 결정적).
        holdingsProvider.overrideWith(
          (ref) => HoldingsNotifier()
            ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
        ),
        retirementInputProvider.overrideWith(
          (ref) => RetirementInputNotifier()..update((_) => _input),
        ),
        ..._withdrawAccountsOverride(),
        dividendEventsProvider.overrideWith(
          (ref) async => DividendFetchResult(
            events: [_eventA],
            fetchedAt: DateTime(2026, 1, 1),
            fromCache: false,
          ),
        ),
      ],
      child: MaterialApp(home: CalendarScreen(initialMonth: initialMonth)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // override 된 notifier 의 생성자 _load 가 읽을 mock prefs(빈 값 → 시드 유지).
    // 기존 회귀는 '총계' 보기 기준 (구 키 false → 총계, v2.3).
    SharedPreferences.setMockInitialValues({'calendar_view': false});
  });

  testWidgets('4월로 네비게이션 → 세후 메인 카드 실수령 186.8만원 표시', (
    WidgetTester tester,
  ) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    // 초기 표시 월(2026년 7월).
    expect(find.text('2026년 7월'), findsOneWidget);

    // ◀ 3회 → 2026년 4월.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('2026년 4월'), findsOneWidget);

    // 메인 카드: 실수령(net) 1,868,000 → 186.8만원.
    expect(findWon('186.8'), findsOneWidget);
    // 내역(v2.3.1): 배당금 통장 입금분 42.3만 + 연금 통장 입금분 144.5만 = 186.8만.
    expect(find.text('배당금 (모든 계좌)'), findsOneWidget);
    expect(find.text('42.3만'), findsOneWidget);
    expect(find.text('144.5만'), findsOneWidget);
    // 연금계좌·ISA 배당이 없는 달은 통장 입금 = 총계.
    expect(find.text('이 중 통장 입금'), findsOneWidget);
    expect(find.text('186.8만'), findsOneWidget);
    // 카드 제목은 '이번 달'이 아니라 표시 월.
    expect(find.text('4월 총계 (세후)'), findsOneWidget);

    // 배당 라인: A사 종목명 + 주당×수량 상세(막대 차트 아래 — 스크롤로 뷰포트에 올림).
    final aSa = find.text('A사');
    await tester.scrollUntilVisible(aSa, 200);
    expect(aSa, findsOneWidget);
    expect(find.textContaining('주당 500원 × 1,000주'), findsOneWidget);
    // 확정 배당이므로 "예상" 배지 없음.
    expect(find.text('예상'), findsNothing);
  });

  testWidgets('배당 없는 달 → 총계엔 연금 타일만, 배당금 보기엔 "이 달 예정 배당 없음"', (
    WidgetTester tester,
  ) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 3));

    expect(find.text('2026년 3월'), findsOneWidget);
    final pension = find.text('연금 인출');
    await tester.scrollUntilVisible(pension, 200);
    expect(pension, findsOneWidget);
    expect(find.text('이 달 들어오는 돈 없음'), findsNothing);
    // 배당 없는 달 실수령 = 연금 net 945,000(과세)+500,000(ISA비과세) = 1,445,000 → 144.5만원.
    expect(findWon('144.5'), findsWidgets);

    await tester.scrollUntilVisible(find.text('배당금'), -300);
    await tester.tap(find.text('배당금'));
    await tester.pumpAndSettle();
    final empty = find.text('이 달 예정 배당 없음');
    await tester.scrollUntilVisible(empty, 200);
    expect(empty, findsOneWidget);
  });

  testWidgets('하단 고지 텍스트 노출(단정 표기 금지)', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 4));
    // 지연 렌더 ListView 하단 항목 — 스크롤로 뷰포트에 올린 뒤 검증.
    final notice = find.text('지급월은 예상이며 회사별로 다를 수 있어요');
    await tester.scrollUntilVisible(notice, 200);
    expect(notice, findsOneWidget);
  });

  testWidgets('배당금 보기 — 차트 머리에 연간 합계 한 줄 + 세전·건수 캡션(v2.3, 옛 요약 카드 통합)', (
    WidgetTester tester,
  ) async {
    // 3월(배당 없는 달)이라도 연간 합계는 2026-04 지급분(50만)을 집계.
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 3));
    await tester.tap(find.text('배당금'));
    await tester.pumpAndSettle();
    final total = find.byKey(const ValueKey('yearlyTotal'));
    await tester.scrollUntilVisible(total, 100);
    expect(tester.widget<Text>(total).data, '2026년 배당 50만원');
    expect(tester.widget<Text>(total).maxLines, 1);
    expect(find.textContaining('세전 · 확정 1건 · 예상 0건'), findsOneWidget);
  });

  testWidgets('연간 미니 막대 차트 — 12개월 막대 + 제목 렌더', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    final title = find.byKey(const ValueKey('yearlyTotal'));
    await tester.scrollUntilVisible(title, 100);
    expect(tester.widget<Text>(title).data, startsWith('2026년 총계 '));
    expect(find.textContaining('세후 · 막대를 누르면'), findsOneWidget);
    // v2.3.1 막대 위 금액(만원 정수): 7월 = 연금 144.5만 → "145".
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('yearlyBarLabel_7'))).data,
      '145만',
    );

    // 1~12월 막대 12개 렌더.
    for (var m = 1; m <= 12; m++) {
      expect(find.byKey(ValueKey('yearlyBar_$m')), findsOneWidget);
    }
  });

  testWidgets('4월 막대 탭 → 아래 달 카드가 4월로 이동(광고 트리거 없음)', (
    WidgetTester tester,
  ) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));
    expect(find.text('2026년 7월'), findsOneWidget);

    final bar4 = find.byKey(const ValueKey('yearlyBar_4'));
    await tester.scrollUntilVisible(bar4, 100);
    // v2.3.1: 막대 차트는 화면 위쪽(보기 선택 바로 아래)에 있다.
    await tester.ensureVisible(bar4);
    await tester.pumpAndSettle();
    await tester.tap(bar4);
    await tester.pumpAndSettle();

    // v2.3.1: 막대 탭 = 달만 이동(시트 없음). 바로 아래 달 카드가 4월로 바뀐다.
    expect(find.byKey(const ValueKey('monthSheet')), findsNothing);
    final aprNav = find.text('2026년 4월');
    await tester.scrollUntilVisible(aprNav, 100);
    expect(aprNav, findsOneWidget);
    expect(find.text('4월 총계 (세후)'), findsOneWidget);
  });

  testWidgets('현재 표시 월 막대 하이라이트(그린)', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    final fill7 = find.byKey(const ValueKey('yearlyBarFill_7'));
    await tester.scrollUntilVisible(fill7, 100);
    final container = tester.widget<Container>(fill7);
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, AppColors.green);
  });

  testWidgets('연 1,500만 초과 인출 → 연금 타일에 16.5% 절벽 캡션', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          holdingsProvider.overrideWith(
            (ref) => HoldingsNotifier()
              ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
          ),
          retirementInputProvider.overrideWith(
            (ref) => RetirementInputNotifier()
              ..update(
                (_) => const RetirementInput(
                  pensionSavings: 100000000,
                  irpBalance: 0,
                  isaBalance: 0,
                  currentAge: 60,
                  monthlyPensionWithdrawal: 0,
                  monthlyOtherWithdrawal: 0,
                  annualInterestIncome: 0,
                ),
              ),
          ),
          // v4: 절벽 판정 소스는 인출을 켠 pension 계좌 monthlyWithdrawal
          // 합산 × 12 (엔진 buildGauges 와 동일 기준) — 계좌 오버라이드로 주입.
          accountsProvider.overrideWith(
            (ref) => AccountsNotifier(ref)
              ..add(
                const Account(
                  id: 'wp',
                  name: '연금인출',
                  type: AccountType.pension,
                  monthlyWithdrawal: 2000000,
                  balance: 100000000,
                  isWithdrawing: true,
                ),
              ), // ×12 = 2,400만 초과
          ),
          dividendEventsProvider.overrideWith(
            (ref) async => DividendFetchResult(
              events: [_eventA],
              fetchedAt: DateTime(2026, 1, 1),
              fromCache: false,
            ),
          ),
        ],
        child: const MaterialApp(home: CalendarScreen(initialMonth: null)),
      ),
    );
    await tester.pumpAndSettle();
    final caption = find.textContaining('연 1,500만원 초과');
    await tester.scrollUntilVisible(caption, 200);
    expect(caption, findsOneWidget);
  });

  testWidgets('수동 입력 종목 — combinedEventsProvider merge 로 달력 라인 노출 (직접 입력 표기)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          holdingsProvider.overrideWith(
            (ref) => HoldingsNotifier()
              ..add(
                const Holding(
                  corpCode: 'manual_1',
                  corpName: '수동ETF',
                  shares: 100,
                  manualPerShareAnnual: 12000,
                  manualPaymentMonths: [7],
                ),
              ),
          ),
          retirementInputProvider.overrideWith(
            (ref) => RetirementInputNotifier()..update((_) => _input),
          ),
          // API 이벤트는 비어 있음 — 수동 합성 이벤트만으로 라인이 떠야 한다.
          dividendEventsProvider.overrideWith(
            (ref) async => DividendFetchResult(
              events: const [],
              fetchedAt: DateTime(2026, 1, 1),
              fromCache: false,
            ),
          ),
        ],
        child: MaterialApp(
          home: CalendarScreen(initialMonth: DateTime(2026, 7)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 7월 라인: 수동ETF, 주당 12,000원 × 100주 (직접 입력) + "예상" 배지(isConfirmed=false).
    final name = find.text('수동ETF');
    await tester.scrollUntilVisible(name, 200);
    expect(name, findsOneWidget);
    expect(find.textContaining('주당 12,000원 × 100주 (직접 입력)'), findsOneWidget);
    expect(find.text('예상'), findsOneWidget);
  });

  testWidgets('v2.3.1 세 탭 숫자가 맞물림 — 총계 통장 입금 = 배당금 탭 통장 입금 + 연금 탭', (
    WidgetTester tester,
  ) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 4));
    // 총계 큰 숫자 186.8 = 42.3 + 144.5.
    expect(findWon('186.8'), findsOneWidget);

    await tester.tap(find.text('배당금'));
    await tester.pumpAndSettle();
    // 배당금 세전 50만 = 통장 입금 42.3 + 배당소득세 7.7.
    expect(findWon('50'), findsWidgets);
    expect(find.text('통장 입금 (일반계좌, 세후)'), findsOneWidget);
    expect(find.text('42.3만'), findsOneWidget);
    expect(find.text('7.7만'), findsOneWidget);

    await tester.tap(find.text('연금'));
    await tester.pumpAndSettle();
    expect(find.text('4월 연금 통장 입금 (세후)'), findsOneWidget);
    expect(findWon('144.5'), findsOneWidget);
  });
}
