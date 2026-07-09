// 화면1 자산 입력 — 렌더 + 연금저축 금액 입력 → provider 상태 반영 검증.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/input_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('입력 화면 렌더 + 연금저축 금액 입력 → provider 상태 반영',
      (WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 4개 카드 헤더 렌더 확인
    expect(find.text('보유 종목'), findsOneWidget);
    expect(find.text('연금 계좌'), findsOneWidget);
    expect(find.text('월 인출 계획'), findsOneWidget);
    expect(find.text('(선택) 연 이자소득'), findsOneWidget);
    // CTA 안내 텍스트
    expect(find.textContaining('연금나침반'), findsOneWidget);

    // 연금저축 잔액(만원 단위 입력) → 원 단위로 provider 반영.
    // 카드1(보유 종목)엔 TextField 가 없으므로 첫 TextField = 연금저축 잔액.
    await tester.enterText(
      find.byType(TextField).first,
      '5000', // 5,000만원 → 50,000,000원
    );
    await tester.pumpAndSettle();

    expect(container.read(retirementInputProvider).pensionSavings, 50000000);
  });
}
