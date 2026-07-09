// 화면2 은퇴 월급 달력 — 월 네비게이션 + 세후 메인 카드 합계 텍스트 검증.
// Task 4 시나리오 재사용: A사 1,000주 / per_share 500 / 2025-12 기준일 → 2026-04 지급.
// 나이 60(세율 5.5%), 과세 인출 월 100만, 비과세 월 50만.
// 기대: 4월 실수령(net) = 1,868,000원 → 186만원.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/calendar_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

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

    // 배당 라인: A사 종목명 + 주당×수량 상세.
    expect(find.text('A사'), findsOneWidget);
    expect(find.textContaining('주당 500원 × 1,000주'), findsOneWidget);
    // 확정 배당이므로 "예상" 배지 없음.
    expect(find.text('예상'), findsNothing);
  });

  testWidgets('배당 없는 달 → "이 달 예정 배당 없음" + 연금은 유지',
      (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 3));

    expect(find.text('2026년 3월'), findsOneWidget);
    expect(find.text('이 달 예정 배당 없음'), findsOneWidget);
    // 배당 없는 달 실수령 = 연금 net 144만원.
    expect(find.text('144만원'), findsWidgets);
  });

  testWidgets('하단 고지 텍스트 노출(단정 표기 금지)', (WidgetTester tester) async {
    await _pumpCalendar(tester, initialMonth: DateTime(2026, 4));
    expect(
      find.text('지급월은 예상이며 회사별로 다를 수 있습니다'),
      findsOneWidget,
    );
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
    expect(find.textContaining('연 1,500만원 초과'), findsOneWidget);
  });
}
