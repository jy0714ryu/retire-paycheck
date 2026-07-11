// 화면2 v2 바인딩 — 최종 합산 고정·계좌 필터 칩·재투자 아코디언.
// 시드: 일반계좌 A사 1,000주 + ISA B사 1,000주, 둘 다 per_share 500 · 2026-04 지급.
// 4월 실수령(all) = 일반 net 423,000 + ISA net 500,000 = 923,000 → 92만원.
// ISA 필터로 바꿔도 상단 합산 카드(92만원)는 불변 + 상세에서 일반주(A사) 사라짐.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/interest_item.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/calendar_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

final _eventGeneral = DividendEvent(
  corpCode: 'A',
  corpName: '일반주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _eventIsa = DividendEvent(
  corpCode: 'B',
  corpName: 'ISA주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _eventPension = DividendEvent(
  corpCode: 'C',
  corpName: '연금주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);

const _input = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 0,
  monthlyOtherWithdrawal: 0,
  annualInterestIncome: 0,
  isWithdrawing: false,
);

Future<void> _pump(
  WidgetTester tester, {
  List<Holding> holdings = const [],
  List<DividendEvent> events = const [],
  List<InterestItem> interestItems = const [],
  RetirementInput input = _input,
  DateTime? initialMonth,
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
        interestItemsProvider.overrideWith((ref) {
          final n = InterestItemsNotifier();
          for (final i in interestItems) {
            n.add(i);
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
      child: MaterialApp(home: CalendarScreen(initialMonth: initialMonth)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('필터를 ISA 로 바꿔도 상단 합산 카드는 불변 + 상세에서 일반주 사라짐',
      (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [
        Holding(corpCode: 'A', corpName: '일반주', shares: 1000),
        Holding(
          corpCode: 'B',
          corpName: 'ISA주',
          shares: 1000,
          accountId: 'default_isa',
        ),
      ],
      events: [_eventGeneral, _eventIsa],
      initialMonth: DateTime(2026, 4),
    );

    // 전체(all) 상단 합산 카드 = 92만원(일반 42.3만 + ISA 50만).
    expect(find.text('92만원'), findsOneWidget);
    // 상세: 전체 모드에선 일반주·ISA주 둘 다 노출(스크롤로 뷰포트에 올림).
    final general = find.text('일반주');
    await tester.scrollUntilVisible(general, 200);
    expect(general, findsOneWidget);
    expect(find.text('ISA주'), findsOneWidget);

    // 상단으로 복귀(월 네비게이션) → 카드·칩 모두 뷰포트에(offset≈0).
    await tester.scrollUntilVisible(find.text('2026년 4월'), -300);
    // ISA 칩 탭(추가 스크롤 없이 — ensureVisible 은 카드를 밀어내므로 금지).
    await tester.tap(find.widgetWithText(ChoiceChip, 'ISA'));
    await tester.pumpAndSettle();

    // 상단 합산 카드 불변(92만원 그대로 — 필터와 무관).
    expect(find.text('92만원'), findsOneWidget);

    // 상세로 스크롤 → ISA주만 남고 일반주는 사라짐.
    final isaLine = find.text('ISA주');
    await tester.scrollUntilVisible(isaLine, 200);
    expect(isaLine, findsOneWidget);
    expect(find.text('일반주'), findsNothing);
  });

  testWidgets('연금계좌 배당 → 재투자 아코디언(기본 접힘) + 펼치면 과세이연 캡션',
      (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [
        Holding(
          corpCode: 'C',
          corpName: '연금주',
          shares: 1000,
          accountId: 'default_pension',
        ),
      ],
      events: [_eventPension],
      initialMonth: DateTime(2026, 4),
    );

    // 재투자 세전 = 500 × 1,000 = 500,000원. 접힌 제목 노출.
    final title = find.text('계좌 내 재투자 +500,000원');
    await tester.scrollUntilVisible(title, 200);
    expect(title, findsOneWidget);
    // 기본 접힘 → 캡션 미노출.
    expect(
      find.textContaining('인출 전까지 계좌 안에서 재투자'),
      findsNothing,
    );

    // 펼치면 과세이연 캡션 노출.
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('인출 전까지 계좌 안에서 재투자'),
      findsOneWidget,
    );
  });

  testWidgets('이자소득 존재 시 상단 카드 서브라인에 이자 병기',
      (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [
        Holding(corpCode: 'A', corpName: '일반주', shares: 1000),
      ],
      events: [_eventGeneral],
      interestItems: const [
        InterestItem(id: 'i1', name: '정기예금', annualAmount: 1200000),
      ],
      initialMonth: DateTime(2026, 4),
    );

    // 이자 월 균등 = 100,000 → 이자 10만 병기.
    expect(
      find.textContaining('+ 이자 10만'),
      findsOneWidget,
    );
  });
}
