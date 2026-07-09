// 앱 기동 + 3탭 셸 스모크 테스트
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/main.dart';

void main() {
  setUp(() {
    // 입력 탭이 SharedPreferences 를 로드하므로 mock 초기화 필요.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('앱 기동 — 3탭 셸 렌더 + 입력 화면 표시', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
    await tester.pumpAndSettle();

    // 하단 3탭 라벨이 모두 보인다
    expect(find.text('입력'), findsWidgets);
    expect(find.text('달력'), findsWidgets);
    expect(find.text('게이지'), findsWidgets);

    // 첫 탭(입력) — 자산 입력 화면 표시
    expect(find.text('자산 입력'), findsOneWidget);
    expect(find.text('보유 종목'), findsOneWidget);
  });

  testWidgets('탭 전환 — 게이지 탭 선택 시 게이지 화면 표시', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.speed_outlined));
    await tester.pumpAndSettle();

    // 게이지 화면(화면3) AppBar 타이틀.
    expect(find.text('세금 임계치'), findsOneWidget);
  });
}
