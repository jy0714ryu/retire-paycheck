import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retire_paycheck/screens/settings_screen.dart';
import 'package:retire_paycheck/services/ad_consent.dart';
import 'package:retire_paycheck/widgets/settings_button.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('톱니 → 설정 화면: 엑셀·공유·메일·리뷰·정보 항목', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [SettingsButton()])),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settingsButton')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    for (final t in [
      '엑셀로 내보내기',
      '앱 공유하기',
      '개발자에게 메일',
      '리뷰 남기기',
      '개인정보처리방침',
      '이용 전 확인사항',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text(kSupportEmail), findsOneWidget);
    // 동의가 필요 없는 지역(한국) 기본 상태 — 광고 개인정보 메뉴는 숨김.
    expect(find.text('광고 개인정보 선택'), findsNothing);
  });

  testWidgets('광고 동의가 필요한 사용자에게만 설정에 \'광고 개인정보 선택\' 표시', (tester) async {
    final original = AdConsent.instance;
    final consent = AdConsent(supported: false);
    AdConsent.instance = consent;
    addTearDown(() => AdConsent.instance = original);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('광고 개인정보 선택'), findsNothing);

    consent.privacyOptionsRequired.value = true;
    await tester.pump();
    await tester.scrollUntilVisible(find.text('광고 개인정보 선택'), 200);
    expect(find.text('광고 개인정보 선택'), findsOneWidget);
  });

  test('앱 공유 문구에 스토어 링크 포함·개인 자산 정보 없음', () {
    expect(kAppShareText, contains(kStoreUrl));
    expect(kAppShareText, isNot(contains('만원')));
  });
}
