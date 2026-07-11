// v2 입력 탭 바인딩 — 계좌 선택/관리·인출 토글+CTA·이자 리스트.
// (Task 6: 브리프 Step1 스니펫 기반, 라벨은 실제 input_screen.dart 값으로 조정.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/input_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('인출 토글 OFF 시 인출 입력 숨김, ON 시 다시 노출', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('연금 인출 중'), findsOneWidget);
    // 기본 OFF(신규 유저 기본값 RetirementInputNotifier._defaultInput) → 인출 필드 없음.
    expect(find.text('연금저축·IRP 월 인출'), findsNothing);
    expect(find.text('ISA·기타 월 인출'), findsNothing);

    final switchFinder = find.byType(Switch).first;
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(find.text('연금저축·IRP 월 인출'), findsOneWidget);
    expect(find.text('ISA·기타 월 인출'), findsOneWidget);

    // 다시 OFF → 재차 숨김.
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.text('연금저축·IRP 월 인출'), findsNothing);
  });

  testWidgets('연금나침반 CTA 링크 문구 노출', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    final ctaFinder = find.text('어떤 순서로 빼야 세금을 아낄까? → 연금나침반');
    await tester.ensureVisible(ctaFinder);
    expect(ctaFinder, findsOneWidget);
  });

  testWidgets('계좌 관리 — 기본 계좌 3개 렌더 + 계좌 추가 다이얼로그', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final expansionFinder = find.text('계좌 관리');
    expect(expansionFinder, findsOneWidget);
    await tester.ensureVisible(expansionFinder);
    await tester.tap(expansionFinder);
    await tester.pumpAndSettle();

    // 기본 계좌 3개 노출.
    expect(find.text('일반계좌'), findsOneWidget);
    expect(find.text('ISA'), findsWidgets); // 계좌명 'ISA' + 유형 라벨 'ISA' 중복 가능
    expect(find.text('연금계좌'), findsOneWidget);

    // 계좌 추가 다이얼로그 → 이름 입력 + 확인 → provider 반영.
    final addBtn = find.byKey(const ValueKey('addAccountButton'));
    await tester.ensureVisible(addBtn);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('newAccountName')), '연금저축B');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmAddAccount')));
    await tester.pumpAndSettle();

    final accounts = container.read(accountsProvider);
    expect(accounts.length, 1);
    expect(accounts.single.name, '연금저축B');
    expect(accounts.single.type, AccountType.general);
    expect(find.text('연금저축B'), findsOneWidget);
  });

  testWidgets('계좌 관리 — 유저 계좌 삭제 확인 다이얼로그 문구', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(accountsProvider.notifier).add(
          const Account(id: 'user_1', name: '테스트계좌', type: AccountType.isa),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final expansionFinder = find.text('계좌 관리');
    await tester.ensureVisible(expansionFinder);
    await tester.tap(expansionFinder);
    await tester.pumpAndSettle();
    expect(find.text('테스트계좌'), findsOneWidget);

    final deleteBtn = find.byKey(const ValueKey('deleteAccount_user_1'));
    await tester.ensureVisible(deleteBtn);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('소속 종목은 기본 계좌로 이동합니다'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirmDeleteAccount')));
    await tester.pumpAndSettle();

    expect(container.read(accountsProvider), isEmpty);
  });

  testWidgets('이자소득 항목 추가 → 리스트 노출 → 삭제', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('(선택) 연 이자소득'), findsOneWidget);
    final addItemBtn = find.byKey(const ValueKey('addInterestItemButton'));
    await tester.ensureVisible(addItemBtn);
    await tester.tap(addItemBtn);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('interestItemName')), '정기예금');
    await tester.enterText(
        find.byKey(const ValueKey('interestItemAmount')), '1200000');
    await tester.pumpAndSettle();

    // 기본 지급방식 = 월 균등 → 바로 제출 가능.
    final submitBtn1 = find.byKey(const ValueKey('interestItemSubmit'));
    await tester.ensureVisible(submitBtn1);
    await tester.tap(submitBtn1);
    await tester.pumpAndSettle();

    final items = container.read(interestItemsProvider);
    expect(items.length, 1);
    expect(items.single.name, '정기예금');
    expect(items.single.annualAmount, 1200000);
    expect(items.single.months, isEmpty);
    expect(find.text('정기예금'), findsOneWidget);

    // 삭제.
    final deleteItemBtn = find.byKey(const ValueKey('deleteInterestItem_0'));
    await tester.ensureVisible(deleteItemBtn);
    await tester.tap(deleteItemBtn);
    await tester.pumpAndSettle();
    expect(container.read(interestItemsProvider), isEmpty);
  });

  testWidgets('이자소득 항목 — 특정월 선택 시 FilterChip으로 지급월 지정', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final addItemBtn = find.byKey(const ValueKey('addInterestItemButton'));
    await tester.ensureVisible(addItemBtn);
    await tester.tap(addItemBtn);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('interestItemName')), '예금');
    await tester.enterText(
        find.byKey(const ValueKey('interestItemAmount')), '600000');
    final specificMonthToggle = find.text('특정월');
    await tester.ensureVisible(specificMonthToggle);
    await tester.tap(specificMonthToggle);
    await tester.pumpAndSettle();

    // 특정월 미선택 상태 → 제출 버튼 비활성.
    final submitBtn = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('interestItemSubmit')));
    expect(submitBtn.onPressed, isNull);

    final month6Chip = find.byKey(const ValueKey('interestMonth_6'));
    await tester.ensureVisible(month6Chip);
    await tester.tap(month6Chip);
    await tester.pumpAndSettle();

    final submitBtn2 = find.byKey(const ValueKey('interestItemSubmit'));
    await tester.ensureVisible(submitBtn2);
    await tester.tap(submitBtn2);
    await tester.pumpAndSettle();

    final items = container.read(interestItemsProvider);
    expect(items.single.months, [6]);
  });

  testWidgets('종목 추가 시트 — 계좌 유형 선택이 Holding.accountId 에 반영', (tester) async {
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

    await tester.tap(find.text('종목 추가'));
    await tester.pumpAndSettle();

    expect(find.text('계좌 선택'), findsOneWidget);
    // 기본 [일반] 선택 상태에서 [ISA] 로 전환.
    final isaSegment = find.text('ISA').last;
    await tester.ensureVisible(isaSegment);
    await tester.tap(isaSegment);
    await tester.pumpAndSettle();

    await tester.tap(find.text('삼성전자'));
    final sharesField = find.byType(TextField).last;
    await tester.ensureVisible(sharesField);
    await tester.enterText(sharesField, '10');
    await tester.pumpAndSettle();

    final addBtn = find.text('추가');
    await tester.ensureVisible(addBtn);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    final holdings = container.read(holdingsProvider);
    expect(holdings.single.accountId, 'default_isa');
  });
}
