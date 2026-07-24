// 당겨서 새로고침 회귀 잠금 — 신선(<TTL) 캐시가 있고 서버 데이터가 바뀐 상태에서
// 당겨서 새로고침이 실제 네트워크를 재조회하고 화면을 새 서버 데이터로 갱신하는지 검증.
//
// 셋업은 calendar_screen_test 와 동일: A사 1,000주 / 2025-12 기준일 → 2026-04 지급.
// per_share 를 500(캐시) → 1,000(서버) 로 바꿔 서버 변경을 화면 "주당 …원" 라인으로 관찰한다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/calendar_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

const _cachedJson = '''
[{"corp_name":"A사","corp_code":"A","ex_date":null,
  "record_date":"2025-12-31","per_share":500,"is_confirmed":true}]
''';
const _serverJson = '''
[{"corp_name":"A사","corp_code":"A","ex_date":null,
  "record_date":"2025-12-31","per_share":1000,"is_confirmed":true}]
''';

/// 신선(1h) 캐시 = per_share 500, 서버 = per_share 1000 인 상태로 달력을 띄운다.
/// 반환된 카운터 함수로 네트워크 호출 횟수를 관찰한다.
Future<int Function()> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'dividends_cache_body': _cachedJson,
    'dividends_cache_at':
        DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
  });
  final prefs = await SharedPreferences.getInstance();

  var netCalls = 0;
  final mockClient = MockClient((req) async {
    netCalls++;
    return http.Response(_serverJson, 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final api = DividendApi(client: mockClient, prefs: prefs);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dividendApiProvider.overrideWithValue(api),
        holdingsProvider.overrideWith(
          (ref) => HoldingsNotifier()
            ..add(const Holding(corpCode: 'A', corpName: 'A사', shares: 1000)),
        ),
      ],
      child: MaterialApp(home: CalendarScreen(initialMonth: DateTime(2026, 4))),
    ),
  );
  await tester.pumpAndSettle();
  return () => netCalls;
}

void main() {
  testWidgets('당겨서 새로고침(프로그램 트리거) → 신선 캐시 무시하고 새 서버 데이터 표시',
      (tester) async {
    final netCalls = await _pump(tester);

    // 초기: 신선 캐시(주당 500원) → 네트워크 미호출.
    expect(netCalls(), 0);
    final old = find.textContaining('주당 500원');
    await tester.scrollUntilVisible(old, 200);
    expect(old, findsOneWidget);

    // RefreshIndicator.onRefresh 를 결정적으로 트리거.
    final refreshState =
        tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
    unawaited(refreshState.show());
    await tester.pumpAndSettle();

    // 새로고침 후: 네트워크 호출 + 화면이 새 서버 데이터(주당 1,000원)로 갱신.
    expect(netCalls(), greaterThanOrEqualTo(1), reason: '새로고침은 반드시 네트워크 재조회');
    final updated = find.textContaining('주당 1,000원');
    await tester.scrollUntilVisible(updated, 200);
    expect(updated, findsOneWidget, reason: '화면이 새 서버 데이터로 갱신돼야 함');
    expect(find.textContaining('주당 500원'), findsNothing,
        reason: '옛 캐시 데이터는 사라져야 함');
  });

  testWidgets('당겨서 새로고침(드래그 제스처) → 새 서버 데이터 표시', (tester) async {
    final netCalls = await _pump(tester);
    expect(netCalls(), 0);

    // 실제 pull 제스처: 리스트를 아래로 드래그(오버스크롤) → RefreshIndicator 발동.
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(netCalls(), greaterThanOrEqualTo(1), reason: '드래그 새로고침도 네트워크 재조회');
    final updated = find.textContaining('주당 1,000원');
    await tester.scrollUntilVisible(updated, 200);
    expect(updated, findsOneWidget);
  });
}
