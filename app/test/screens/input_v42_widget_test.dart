// v1.4.2 입력 탭 — 종목 삭제 버튼(①)·두 계좌 동일 종목 키 충돌 방지(②)·
// 잔액 소진 캡션 경계값(④) 검증.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/screens/input_screen.dart';

/// SharedPreferences 'holdings' 키에 주입할 JSON 문자열.
String _holdingsJson(List<Map<String, dynamic>> items) => jsonEncode(items);

void main() {
  testWidgets('① 종목 행에 휴지통 삭제 버튼 노출 + 탭으로 삭제', (tester) async {
    SharedPreferences.setMockInitialValues({
      'holdings': _holdingsJson([
        {
          'corp_code': '005930',
          'corp_name': '삼성전자',
          'shares': 10,
          'account_id': 'default_general',
        },
      ]),
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('삼성전자'), findsOneWidget);

    final deleteBtn =
        find.byKey(const ValueKey('deleteHolding_default_general_005930'));
    expect(deleteBtn, findsOneWidget);

    await tester.ensureVisible(deleteBtn);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // 탭 삭제 후 종목이 사라진다.
    expect(find.text('삼성전자'), findsNothing);
  });

  testWidgets('② 같은 종목을 일반+ISA 두 계좌에 보유해도 Duplicate keys 크래시 없음',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'holdings': _holdingsJson([
        {
          'corp_code': '005930',
          'corp_name': '삼성전자',
          'shares': 10,
          'account_id': 'default_general',
        },
        {
          'corp_code': '005930',
          'corp_name': '삼성전자',
          'shares': 5,
          'account_id': 'default_isa',
        },
      ]),
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // 크래시 없이 두 행이 렌더된다(각 계좌 카드에 1개씩).
    expect(tester.takeException(), isNull);
    expect(find.text('삼성전자'), findsNWidgets(2));
    expect(
        find.byKey(const ValueKey('deleteHolding_default_general_005930')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('deleteHolding_default_isa_005930')),
        findsOneWidget);
  });

  testWidgets('④ 잔액 0(미입력) + 인출 ON + 월 인출>0 이면 소진 캡션 숨김',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // 잔액은 입력하지 않고(0) ISA 인출 스위치만 ON.
    final isaSwitch =
        find.byKey(const ValueKey('withdrawSwitch_default_isa'));
    await tester.ensureVisible(isaSwitch);
    await tester.tap(isaSwitch);
    await tester.pumpAndSettle();

    // 월 인출 100만원 입력(만원 단위 100).
    final withdrawalField =
        find.byKey(const ValueKey('withdrawal_default_isa'));
    await tester.ensureVisible(withdrawalField);
    await tester.enterText(withdrawalField, '100');
    await tester.pumpAndSettle();

    // 잔액 0 → totalMonths<1 → 캡션 미노출.
    expect(find.text('이 속도면 약 0개월분'), findsNothing);
  });
}
