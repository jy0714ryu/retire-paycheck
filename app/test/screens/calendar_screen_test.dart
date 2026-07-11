// 화면2 은퇴 월급 달력 — 월 네비게이션 + 세후 메인 카드 합계 텍스트 검증.
// Task 4 시나리오 재사용: A사 1,000주 / per_share 500 / 2025-12 기준일 → 2026-04 지급.
// 나이 60(세율 5.5%), 과세 인출 월 100만, 비과세 월 50만.
// 기대: 4월 실수령(net) = 1,868,000원 → 186만원.
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

// v3: 인출 소스는 계좌 합산 — 과세 월 100만(pension) + 비과세 월 50만(isa).
List<Override> _withdrawAccountsOverride() => [
      accountsProvider.overrideWith(
        (ref) => AccountsNotifier(ref)
          ..add(const Account(
              id: 'wp',
              name: '연금인출',
              type: AccountType.pension,
              monthlyWithdrawal: 1000000))
          ..add(const Account(
              id: 'wi',
              name: 'ISA인출',
              type: AccountType.isa,
              monthlyWithdrawal: 500000)),
      ),
    ];

Future<void> _pumpCalendar(WidgetTester tester, {DateTime? initialMonth}) async {
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
        dividendEventsProvider.overrideWith((ref) async => DividendFetchResult(
              events: [_eventA],
              fetchedAt: DateTime(2026, 1, 1),
              fromCache: false,
            )),
      ],
      child: MaterialApp(home: CalendarScreen(initialMonth: initialMonth)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // override 된 notifier 의 생성자 _load 가 읽을 mock prefs(빈 값 → 시드 유지).
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('4월로 네비게이션 → 세후 메인 카드 실수령 186만원 표시',
      (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    // 초기 표시 월(2026년 7월).
    expect(find.text('2026년 7월'), findsOneWidget);

    // ◀ 3회 → 2026년 4월.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('2026년 4월'), findsOneWidget);

    // 메인 카드: 실수령(net) 1,868,000 → 186만원.
    expect(find.text('186만원'), findsOneWidget);
    // 서브: 세전 200만원 = 세전 배당 50만 + 세전 연금 150만 (세전끼리 합 일치).
    expect(
      find.textContaining('세전 200만원 · 배당 50만 + 연금 150만'),
      findsOneWidget,
    );

    // 배당 라인: A사 종목명 + 주당×수량 상세(막대 차트 아래 — 스크롤로 뷰포트에 올림).
    final aSa = find.text('A사');
    await tester.scrollUntilVisible(aSa, 200);
    expect(aSa, findsOneWidget);
    expect(find.textContaining('주당 500원 × 1,000주'), findsOneWidget);
    // 확정 배당이므로 "예상" 배지 없음.
    expect(find.text('예상'), findsNothing);
  });

  testWidgets('배당 없는 달 → "이 달 예정 배당 없음" + 연금은 유지',
      (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 3));

    expect(find.text('2026년 3월'), findsOneWidget);
    final empty = find.text('이 달 예정 배당 없음');
    await tester.scrollUntilVisible(empty, 200);
    expect(empty, findsOneWidget);
    // 배당 없는 달 실수령 = 연금 net 144만원.
    expect(find.text('144만원'), findsWidgets);
  });

  testWidgets('하단 고지 텍스트 노출(단정 표기 금지)', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 4));
    // 지연 렌더 ListView 하단 항목 — 스크롤로 뷰포트에 올린 뒤 검증.
    final notice = find.text('지급월은 예상이며 회사별로 다를 수 있습니다');
    await tester.scrollUntilVisible(notice, 200);
    expect(notice, findsOneWidget);
  });

  testWidgets('연간 배당 요약 카드 — 올해 예상 배당·세후·건수 노출',
      (WidgetTester tester) async {
    // 3월(배당 없는 달)이라도 연간 요약은 2026-04 지급분(50만)을 집계.
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 3));
    expect(find.textContaining('올해 예상 배당'), findsOneWidget);
    // gross 50만 → 세후 42.3만. 만원 반올림 표기.
    expect(find.textContaining('총 50만원'), findsOneWidget);
    expect(find.textContaining('세후 42만원'), findsOneWidget);
    expect(find.textContaining('확정 1건'), findsOneWidget);
    expect(find.textContaining('예측 0건'), findsOneWidget);
  });

  testWidgets('연간 미니 막대 차트 — 12개월 막대 + 제목 렌더',
      (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    final title = find.text('올해 월별 흐름');
    await tester.scrollUntilVisible(title, 100);
    expect(title, findsOneWidget);
    expect(find.text('(세후 기준)'), findsOneWidget);

    // 1~12월 막대 12개 렌더.
    for (var m = 1; m <= 12; m++) {
      expect(find.byKey(ValueKey('yearlyBar_$m')), findsOneWidget);
    }
  });

  testWidgets('4월 막대 탭 → 2026년 4월로 이동(광고 트리거 없음)',
      (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));
    expect(find.text('2026년 7월'), findsOneWidget);

    final bar4 = find.byKey(const ValueKey('yearlyBar_4'));
    await tester.scrollUntilVisible(bar4, 100);
    await tester.tap(bar4);
    await tester.pumpAndSettle();

    // 상단 월 네비게이션으로 스크롤해 이동 결과 확인.
    final aprNav = find.text('2026년 4월');
    await tester.scrollUntilVisible(aprNav, -100);
    expect(aprNav, findsOneWidget);
  });

  testWidgets('현재 표시 월 막대 하이라이트(그린)', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 7));

    final fill7 = find.byKey(const ValueKey('yearlyBarFill_7'));
    await tester.scrollUntilVisible(fill7, 100);
    final container = tester.widget<Container>(fill7);
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, AppColors.green);
  });

  testWidgets('연 1,500만 초과 인출 → 연금 타일에 16.5% 절벽 캡션',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          holdingsProvider.overrideWith(
            (ref) => HoldingsNotifier()
              ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
          ),
          retirementInputProvider.overrideWith(
            (ref) => RetirementInputNotifier()
              ..update((_) => const RetirementInput(
                    pensionSavings: 100000000,
                    irpBalance: 0,
                    isaBalance: 0,
                    currentAge: 60,
                    monthlyPensionWithdrawal: 2000000, // ×12 = 2,400만 초과
                    monthlyOtherWithdrawal: 500000,
                    annualInterestIncome: 0,
                  )),
          ),
          dividendEventsProvider.overrideWith((ref) async => DividendFetchResult(
                events: [_eventA],
                fetchedAt: DateTime(2026, 1, 1),
                fromCache: false,
              )),
        ],
        child: const MaterialApp(home: CalendarScreen(initialMonth: null)),
      ),
    );
    await tester.pumpAndSettle();
    final caption = find.textContaining('연 1,500만원 초과');
    await tester.scrollUntilVisible(caption, 200);
    expect(caption, findsOneWidget);
  });

  testWidgets('수동 입력 종목 — combinedEventsProvider merge 로 달력 라인 노출 (직접 입력 표기)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          holdingsProvider.overrideWith(
            (ref) => HoldingsNotifier()
              ..add(const Holding(
                corpCode: 'manual_1',
                corpName: '수동ETF',
                shares: 100,
                manualPerShareAnnual: 12000,
                manualPaymentMonths: [7],
              )),
          ),
          retirementInputProvider.overrideWith(
            (ref) => RetirementInputNotifier()..update((_) => _input),
          ),
          // API 이벤트는 비어 있음 — 수동 합성 이벤트만으로 라인이 떠야 한다.
          dividendEventsProvider.overrideWith((ref) async => DividendFetchResult(
                events: const [],
                fetchedAt: DateTime(2026, 1, 1),
                fromCache: false,
              )),
        ],
        child: MaterialApp(home: CalendarScreen(initialMonth: DateTime(2026, 7))),
      ),
    );
    await tester.pumpAndSettle();

    // 7월 라인: 수동ETF, 주당 12,000원 × 100주 (직접 입력) + "예상" 배지(isConfirmed=false).
    final name = find.text('수동ETF');
    await tester.scrollUntilVisible(name, 200);
    expect(name, findsOneWidget);
    expect(
      find.textContaining('주당 12,000원 × 100주 (직접 입력)'),
      findsOneWidget,
    );
    expect(find.text('예상'), findsOneWidget);
  });
}
