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
      SharedPreferences.setMockInitialValues({
        kDisclaimerAcceptedKey: true,
        kQuickStartDoneKey: true,
      });
    });

    testWidgets('앱 기동 — 4탭 셸 렌더 + 기본 탭은 이번 달', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      expect(find.text('이번 달'), findsWidgets);
      expect(find.text('계획'), findsWidgets);
      expect(find.text('세금'), findsWidgets);
      expect(find.text('내 자산'), findsWidgets);
      // 기본 탭 = 이번 달 (은퇴월급 헤더)
      expect(find.text('은퇴월급'), findsOneWidget);
      expect(find.byType(DisclaimerDialog), findsNothing);
      expect(find.byType(QuickStartScreen), findsNothing);
    });

    testWidgets('탭 전환 — 세금·내 자산·계획', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();
      expect(find.text('세금 문턱'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pumpAndSettle();
      expect(find.text('일반계좌'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.timeline_outlined));
      await tester.pumpAndSettle();
      expect(find.text('인출 계획'), findsOneWidget);
      // 잔액이 없으면 내 자산 입력 안내
      expect(find.text('내 자산 입력하기'), findsOneWidget);
    });

    testWidgets('뒤로 가기 — 입력 중엔 키보드만, 다른 탭은 첫 탭, 첫 탭은 두 번 눌러 종료 안내', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pumpAndSettle();

      // 입력칸에 커서 → 뒤로 가기는 키보드만 내리고 탭 유지.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      EditableText? focusedText() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>();
      expect(focusedText(), isNotNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('일반계좌'), findsOneWidget);
      expect(focusedText(), isNull);

      // 다음 뒤로 가기 → 첫 탭(이번 달).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('은퇴월급'), findsOneWidget);

      // 첫 탭에서 뒤로 가기 → 종료하지 않고 안내.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('한 번 더 누르면 종료돼요'), findsOneWidget);
    });

    testWidgets('내 자산 → "어떤 순서로 빼야…" 안내는 계획 탭으로 이동 (연금나침반 외부 링크 없음)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pumpAndSettle();
      expect(find.textContaining('연금나침반'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('go_to_plan')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('go_to_plan')));
      await tester.pumpAndSettle();
      expect(find.text('인출 계획'), findsOneWidget);
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
      expect(find.byKey(const Key('plan_share')), findsOneWidget);

      // v2.2: 연도별 표(기본 접힘) — 펼치면 나이별 줄.
      final yearly = find.byKey(const Key('plan_yearly_tile'));
      await tester.scrollUntilVisible(
        yearly,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(yearly);
      await tester.pumpAndSettle();
      expect(find.text('66세'), findsOneWidget);
      await tester.tap(yearly);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('plan_unknown_note')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

      // v2.1: 공제 안 받은 원금을 모름으로 두면 "기본 가정" 표시 → '없음' 답하면 사라진다.
      expect(find.byKey(const Key('plan_unknown_note')), findsOneWidget);
      expect(find.text('기본 가정에서 세금이 가장 적게 계산된 인출 순서'), findsOneWidget);
      final tile = find.byKey(const Key('plan_accuracy_tile'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final q = find.byKey(const Key('plan_q_nonDeducted'));
      await tester.scrollUntilVisible(
        q,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.descendant(of: q, matching: find.text('없음')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_unknown_note')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('세금이 가장 적게 계산된 인출 순서'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('세금이 가장 적게 계산된 인출 순서'), findsOneWidget);
    });

    testWidgets('계획 탭 국민연금 "모르면 추정하기" → 값이 칸에 채워진다', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('qs_age')), '58');
      await tester.enterText(find.byKey(const Key('qs_balance')), '35000');
      await tester.enterText(find.byKey(const Key('qs_monthly')), '150');
      await tester.pump();
      await tester.tap(find.byKey(const Key('qs_submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.timeline_outlined));
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('plan_nps_estimate'));
      await tester.scrollUntilVisible(
        btn,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(btn);
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nps_income')), '300');
      await tester.enterText(find.byKey(const Key('nps_years')), '30');
      await tester.enterText(find.byKey(const Key('nps_birth')), '1968');
      await tester.pump();
      expect(find.byKey(const Key('nps_result')), findsOneWidget);
      expect(find.textContaining('64세부터'), findsOneWidget); // 1965~68년생 64세
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const Key('nps_apply')));
      await tester.pumpAndSettle();

      final nps = tester.widget<TextField>(find.byKey(const Key('plan_nps')));
      expect(int.parse(nps.controller!.text), greaterThan(0));
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

    testWidgets('뒤로 가기로 닫아도 다시 뜨지 않는다', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({kDisclaimerAcceptedKey: true});
      await tester.pumpWidget(const ProviderScope(child: RetirePaycheckApp()));
      await tester.pumpAndSettle();
      expect(find.byType(QuickStartScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuickStartScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kQuickStartDoneKey), isTrue);
    });

    test('기존 사용자 데이터가 있으면 첫 실행 화면을 건너뛴다', () {
      expect(needsQuickStart(storedKeys: {}, done: false), isTrue);
      expect(
        needsQuickStart(storedKeys: {'retirement_input'}, done: false),
        isTrue,
      );
      expect(needsQuickStart(storedKeys: {'holdings'}, done: false), isFalse);
      expect(
        needsQuickStart(storedKeys: {'default_account_overrides'}, done: false),
        isFalse,
      );
      expect(needsQuickStart(storedKeys: {}, done: true), isFalse);
    });
  });

  group('첫 실행 면책 다이얼로그', () {
    testWidgets('미동의 상태 → 다이얼로그 표시 후 확인 시 닫히고 플래그 저장', (
      WidgetTester tester,
    ) async {
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
