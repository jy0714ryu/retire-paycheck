// forceRefreshProvider 증가 → dividendEventsProvider 실제 재실행(force=true 네트워크)
// → combinedEventsProvider(UI 소비 지점) 새 데이터 전파를 ProviderContainer 로 잠근다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

const _cachedJson = '''
[{"corp_name":"올드","corp_code":"OLD","ex_date":null,
  "record_date":"2025-12-31","per_share":500,"is_confirmed":true}]
''';
const _serverJson = '''
[{"corp_name":"뉴","corp_code":"NEW","ex_date":null,
  "record_date":"2025-12-31","per_share":500,"is_confirmed":true}]
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forceRefresh 증가 → combinedEventsProvider 가 새 서버 데이터로 갱신', () async {
    // 신선 캐시(1h) = 올드.
    SharedPreferences.setMockInitialValues({
      'dividends_cache_body': _cachedJson,
      'dividends_cache_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();

    var netCalls = 0;
    final mockClient = MockClient((req) async {
      netCalls++;
      return http.Response(_serverJson, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final api = DividendApi(client: mockClient, prefs: prefs);

    final c = ProviderContainer(
      overrides: [dividendApiProvider.overrideWithValue(api)],
    );
    addTearDown(c.dispose);

    // 화면이 combined 를 watch 하는 상황 재현(구독 유지).
    final sub = c.listen(combinedEventsProvider(2026), (_, _) {},
        fireImmediately: true);
    addTearDown(sub.close);

    // 초기: 신선 캐시 → 올드, 네트워크 미호출.
    final initial = await c.read(combinedEventsProvider(2026).future);
    expect(netCalls, 0);
    expect(initial.single.corpName, '올드');

    // 당겨서 새로고침 로직: 카운터 증가 후 combined.future await.
    c.read(forceRefreshProvider.notifier).state++;
    final refreshed = await c.read(combinedEventsProvider(2026).future);

    // dividendEventsProvider 가 force=true 로 실제 재실행 → 네트워크 → 새 데이터.
    expect(netCalls, 1, reason: 'force 카운터 증가는 실제 네트워크 재조회를 유발해야 함');
    expect(refreshed.single.corpName, '뉴', reason: 'UI provider 가 새 데이터로 갱신');

    // 두 번째 새로고침(카운터 1→2)도 다시 네트워크 재조회(스턱 아님).
    c.read(forceRefreshProvider.notifier).state++;
    await c.read(combinedEventsProvider(2026).future);
    expect(netCalls, 2, reason: '연속 새로고침도 매번 네트워크 재조회');
  });
}
