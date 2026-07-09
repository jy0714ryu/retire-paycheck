// 앱 기동 + 3탭 셸 + 첫 실행 면책 다이얼로그 스모크 테스트
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/main.dart';
import 'package:retire_paycheck/widgets/disclaimer_dialog.dart';

void main() {
  group('셸 스모크 (면책 이미 동의 상태)', () {
    setUp(() {
      // 입력 탭이 SharedPreferences 를 로드하므로 mock 초기화 필요.
      // 면책은 이미 동의 처리해 다이얼로그가 탭 조작을 막지 않도록 한다.
      SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
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

      // 면책 이미 동의 → 다이얼로그 미표시
      expect(find.byType(DisclaimerDialog), findsNothing);
    });

    testWidgets('탭 전환 — 게이지 탭 선택 시 게이지 화면 표시',
        (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.speed_outlined));
      await tester.pumpAndSettle();

      // 게이지 화면(화면3) AppBar 타이틀.
      expect(find.text('세금 임계치'), findsOneWidget);
    });
  });

  group('첫 실행 면책 다이얼로그', () {
    testWidgets('미동의 상태 → 다이얼로그 표시 후 확인 시 닫히고 플래그 저장',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      // 첫 프레임 이후 면책 다이얼로그가 뜬다.
      expect(find.byType(DisclaimerDialog), findsOneWidget);
      expect(find.text('이용 전 확인사항'), findsOneWidget);

      // "확인했습니다" 탭 → 닫힘 + 플래그 저장.
      await tester.tap(find.text('확인했습니다'));
      await tester.pumpAndSettle();

      expect(find.byType(DisclaimerDialog), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kDisclaimerAcceptedKey), isTrue);
    });
  });
}
