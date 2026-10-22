// 앱 기동 + 4탭 셸(v2) + 첫 실행 면책·세 칸 입력 스모크 테스트
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/main.dart';
import 'package:retire_paycheck/screens/quick_start_screen.dart';
import 'package:retire_paycheck/widgets/disclaimer_dialog.dart';

void main() {
  group('셸 스모크 (면책 이미 동의 상태)', () {
    setUp(() {
      // 입력 탭이 SharedPreferences 를 로드하므로 mock 초기화 필요.
      // 면책은 이미 동의 처리해 다이얼로그가 탭 조작을 막지 않도록 한다.
      SharedPreferences.setMockInitialValues(
          {kDisclaimerAcceptedKey: true, kQuickStartDoneKey: true});
    });

    testWidgets('앱 기동 — 4탭 셸 렌더 + 기본 탭은 이번 달', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      expect(find.text('이번 달'), findsWidgets);
      expect(find.text('계획'), findsWidgets);
      expect(find.text('경보'), findsWidgets);
      expect(find.text('내 자산'), findsWidgets);
      // 기본 탭 = 이번 달 (은퇴월급 헤더)
      expect(find.text('은퇴월급'), findsOneWidget);
      expect(find.byType(DisclaimerDialog), findsNothing);
      expect(find.byType(QuickStartScreen), findsNothing);
    });

    testWidgets('탭 전환 — 경보·내 자산·계획', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.notifications_none_outlined));
      await tester.pumpAndSettle();
      expect(find.text('세금 문턱 경보'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pumpAndSettle();
      expect(find.text('일반계좌'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.timeline_outlined));
      await tester.pumpAndSettle();
      expect(find.text('인출 계획'), findsOneWidget);
      // 잔액이 없으면 내 자산 입력 안내
      expect(find.text('내 자산 입력하기'), findsOneWidget);
    });
  });

  group('첫 실행 세 칸 입력 (v2)', () {
    testWidgets('입력 → 계획 탭에서 전략 비교가 계산된다', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      expect(find.byType(QuickStartScreen), findsOneWidget);
      await tester.enterText(find.byKey(const Key('qs_age')), '66');
      await tester.enterText(find.byKey(const Key('qs_balance')), '35000');
      await tester.enterText(find.byKey(const Key('qs_monthly')), '150');
      await tester.pump();
      await tester.tap(find.byKey(const Key('qs_submit')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickStartScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kQuickStartDoneKey), isTrue);

      await tester.tap(find.byIcon(Icons.timeline_outlined));
      await tester.pumpAndSettle();
      expect(find.text('계산 결과 1위'), findsOneWidget);
    });

    testWidgets('건너뛰기 — 완료 표시만 하고 닫힘', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('건너뛰기'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickStartScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kQuickStartDoneKey), isTrue);
    });

    test('기존 사용자 데이터가 있으면 첫 실행 화면을 건너뛴다', () {
      expect(needsQuickStart(storedKeys: {}, done: false), isTrue);
      expect(needsQuickStart(storedKeys: {'retirement_input'}, done: false), isTrue);
      expect(needsQuickStart(storedKeys: {'holdings'}, done: false), isFalse);
      expect(needsQuickStart(storedKeys: {'default_account_overrides'}, done: false), isFalse);
      expect(needsQuickStart(storedKeys: {}, done: true), isFalse);
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
