// 화면1 자산 입력 — 렌더 + 연금저축 금액 입력 → provider 상태 반영 검증.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/input_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

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
    // 자동 저장 안내(대장님 피드백: 저장 UX 불안 해소)
    expect(find.textContaining('자동으로 저장됩니다'), findsOneWidget);

    // 연금저축 잔액(만원 단위 입력) → 원 단위로 provider 반영.
    // 카드1(보유 종목)엔 TextField 가 없으므로 첫 TextField = 연금저축 잔액.
    await tester.enterText(
      find.byType(TextField).first,
      '5000', // 5,000만원 → 50,000,000원
    );
    await tester.pumpAndSettle();

    expect(container.read(retirementInputProvider).pensionSavings, 50000000);
  });

  // 회귀: 배당 provider 가 비동기로 뒤늦게 resolve 되어도, 종목추가 시트가
  // 이를 watch 하여 목록을 렌더해야 한다. (버그: ref.read 스냅샷을 잡아
  // AsyncLoading 상태의 빈 목록으로 굳어 "불러오지 못했습니다" 가 항상 떴다.)
  testWidgets('종목 추가 시트 — 배당 provider 지연 resolve 후 목록 렌더',
      (WidgetTester tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 실제 앱처럼 비동기로 지연 resolve — 시트 open 시점엔 로딩 상태.
          dividendEventsProvider.overrideWith(
            (ref) => Future<DividendFetchResult>.delayed(
              const Duration(milliseconds: 50),
              () => result,
            ),
          ),
        ],
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 종목 추가 시트 열기 (이 시점 provider 는 아직 로딩).
    await tester.tap(find.text('종목 추가'));
    await tester.pump(); // 시트 등장
    // 로딩 스피너가 먼저 뜨고 에러 문구는 없어야 한다.
    expect(find.text('배당 종목 목록을 아직 불러오지 못했습니다.\n잠시 후 다시 시도하세요.'),
        findsNothing);

    // provider resolve 후 시트가 rebuild 되어 종목이 나타나야 한다.
    await tester.pumpAndSettle();
    expect(find.text('삼성전자'), findsOneWidget);
    expect(find.text('배당 종목 목록을 아직 불러오지 못했습니다.\n잠시 후 다시 시도하세요.'),
        findsNothing);
  });

  // 직접 입력(배당 API 미커버 종목 폴백): 시트 하단 "직접 입력" → 폼 전환 →
  // 종목명·수량·연간 배당금 입력 + 지급월 선택 → 추가 → 리스트 노출 + 배지 + provider 반영.
  testWidgets('종목 추가 시트 — 직접 입력 폼으로 종목 추가 → 리스트 노출',
      (WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      dividendEventsProvider.overrideWith(
        (ref) async => DividendFetchResult(
          events: const [],
          fetchedAt: DateTime(2026, 1, 1),
          fromCache: false,
        ),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: InputScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 시트 열기 → 직접 입력 폼 전환.
    await tester.tap(find.text('종목 추가'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('manualEntryButton')));
    await tester.tap(find.byKey(const ValueKey('manualEntryButton')));
    await tester.pumpAndSettle();
    expect(find.text('종목명'), findsOneWidget);

    // 폼 입력: 종목명 / 수량 / 주당 연간 배당금. 지급월 기본 4월 + 10월 추가 선택.
    await tester.enterText(
        find.byKey(const ValueKey('manualName')), '커버리지밖ETF');
    await tester.enterText(find.byKey(const ValueKey('manualShares')), '100');
    await tester.enterText(
        find.byKey(const ValueKey('manualAnnual')), '12000');
    await tester.ensureVisible(find.byKey(const ValueKey('manualMonth_10')));
    await tester.tap(find.byKey(const ValueKey('manualMonth_10')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('manualSubmit')));
    await tester.tap(find.byKey(const ValueKey('manualSubmit')));
    await tester.pumpAndSettle();

    // 시트 닫힘 + 보유 종목 리스트에 노출("직접 입력" 배지 포함).
    expect(find.text('커버리지밖ETF'), findsOneWidget);
    expect(find.text('100주'), findsOneWidget);
    expect(find.text('직접 입력'), findsOneWidget); // 리스트 미니 배지

    // provider 상태 — manual 필드가 채워진 Holding 저장.
    final holdings = container.read(holdingsProvider);
    expect(holdings.length, 1);
    final h = holdings.single;
    expect(h.isManual, isTrue);
    expect(h.corpCode, startsWith('manual_'));
    expect(h.manualPerShareAnnual, 12000);
    expect(h.manualPaymentMonths, [4, 10]);
  });
}
