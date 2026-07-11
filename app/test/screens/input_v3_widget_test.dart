// v3 입력 탭 — 계좌 중심 IA. 계좌 카드 렌더·인출 필드 조건부 노출·
// 종목 추가 시 소속 계좌 자동 고정(시트에 계좌 선택 없음)을 검증한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/input_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';
import 'package:retire_paycheck/widgets/input_widgets.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('계좌 카드 4개 기본 렌더 + 일반계좌엔 잔액 필드 없음', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // 기본 계좌 4개 헤더 렌더(연금저축·IRP 분리).
    expect(find.text('일반계좌'), findsOneWidget);
    expect(find.text('ISA'), findsWidgets); // 계좌명 'ISA' + 유형 배지 'ISA'
    expect(find.text('연금저축'), findsOneWidget);
    expect(find.text('IRP'), findsOneWidget);

    // 잔액 필드는 ISA·연금저축·IRP 만(일반계좌 제외) → 총 3개.
    // 인출 토글 OFF(기본)이므로 월 인출 필드는 없다.
    expect(find.byType(AmountInputField), findsNWidgets(3));
  });

  testWidgets('인출 토글 ON 시 ISA·연금 계좌 카드에 월 인출 필드 노출', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // OFF(기본) → 월 인출 필드 없음.
    expect(find.text('월 인출'), findsNothing);

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // ON → 잔액 있는 3계좌(ISA·연금저축·IRP)에 월 인출 노출.
    expect(find.text('월 인출'), findsNWidgets(3));

    // 다시 OFF → 재차 숨김.
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('월 인출'), findsNothing);
  });

  testWidgets('ISA 카드에서 종목 추가 → 시트에 계좌 선택 없음 → accountId=default_isa',
      (tester) async {
    final result = DividendFetchResult(
      events: [
        const DividendEvent(
          corpCode: '005930',
          corpName: '삼성전자',
          exDate: null,
          recordDate: null,
          perShare: 361,
          isConfirmed: true,
        ),
      ],
      fetchedAt: DateTime(2026, 1, 1),
      fromCache: false,
    );
    final container = ProviderContainer(overrides: [
      dividendEventsProvider.overrideWith((ref) async => result),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // ISA 카드의 "+ 종목 추가" 만 정확히 탭(계좌별 키).
    final isaAdd = find.byKey(const ValueKey('addHolding_default_isa'));
    await tester.ensureVisible(isaAdd);
    await tester.tap(isaAdd);
    await tester.pumpAndSettle();

    // 시트에 계좌 선택 UI 가 없어야 한다(소속은 호출 계좌로 고정).
    expect(find.text('계좌 선택'), findsNothing);

    // 종목 선택 → 수량 입력 → 추가.
    await tester.tap(find.text('삼성전자'));
    final sharesField = find.byType(TextField).last;
    await tester.ensureVisible(sharesField);
    await tester.enterText(sharesField, '10');
    await tester.pumpAndSettle();

    final addBtn = find.widgetWithText(ElevatedButton, '추가');
    await tester.ensureVisible(addBtn);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    final holdings = container.read(holdingsProvider);
    expect(holdings.single.accountId, 'default_isa');
  });
}
