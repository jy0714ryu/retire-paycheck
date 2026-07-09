// 앱 기동 + 3탭 셸 스모크 테스트
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:retire_paycheck/main.dart';

void main() {
  testWidgets('앱 기동 — 3탭 셸 렌더 + 입력 탭 표시', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
    await tester.pumpAndSettle();

    // 하단 3탭 라벨이 모두 보인다
    expect(find.text('입력'), findsWidgets);
    expect(find.text('달력'), findsWidgets);
    expect(find.text('게이지'), findsWidgets);

    // 첫 탭(입력) placeholder 표시
    expect(find.text('입력 화면 준비 중'), findsOneWidget);
  });

  testWidgets('탭 전환 — 게이지 탭 선택 시 게이지 화면 표시', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speed_outlined));
    await tester.pumpAndSettle();

    expect(find.text('게이지 화면 준비 중'), findsOneWidget);
  });
}
