// v4 입력 탭 — 계좌별 인출 스위치·전역 토글 제거 검증.
// (계좌별 "인출 개시" 스위치 ON 시 그 계좌에만 월 인출 필드가 노출되고,
//  공통 설정의 전역 "연금 인출 중" 토글이 사라졌음을 확인한다.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/screens/input_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('계좌 인출 스위치 OFF→ON 시 월 인출 필드 노출', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // 기본 전부 인출 OFF → "월 인출" 필드 없음.
    expect(find.text('월 인출'), findsNothing);

    // 첫 인출 스위치(ISA) 켜기 → 그 계좌에만 월 인출 노출.
    final firstSwitch = find.byType(Switch).first;
    await tester.ensureVisible(firstSwitch);
    await tester.tap(firstSwitch);
    await tester.pumpAndSettle();
    expect(find.text('월 인출'), findsWidgets);
  });

  testWidgets('전역 "연금 인출 중" 토글이 공통 설정에서 제거됨', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('연금 인출 중'), findsNothing);
  });

  testWidgets('인출 ON + 월 인출>0 시 잔액 소진 캡션 노출', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InputScreen())),
    );
    await tester.pumpAndSettle();

    // ISA 잔액 입력(만원 단위 2400 → 2,400만원 = 24,000,000원).
    final balanceField = find.byKey(const ValueKey('balance_default_isa'));
    await tester.ensureVisible(balanceField);
    await tester.enterText(balanceField, '2400');
    await tester.pumpAndSettle();

    // ISA 인출 스위치 ON.
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

    // 24,000,000 ÷ (1,000,000 × 12) = 2년 → "이 속도면 약 2년분".
    expect(find.text('이 속도면 약 2년분'), findsOneWidget);
  });
}
