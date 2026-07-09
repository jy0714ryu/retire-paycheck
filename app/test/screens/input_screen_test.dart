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
}
