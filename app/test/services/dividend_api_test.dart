import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/services/dividend_api.dart';

const _sampleJson = '''
[
  {"corp_name": "폴레드", "corp_code": "01565364", "ex_date": "2026-07-09",
   "record_date": "2026-07-10", "per_share": 200, "is_confirmed": true,
   "source": "disclosure", "disclosed_at": "20260625"}
]
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('정상 응답 → 파싱 + 캐시 저장', () async {
    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      return http.Response(_sampleJson, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final prefs = await SharedPreferences.getInstance();

    final api = DividendApi(client: mockClient, prefs: prefs);
    final result = await api.fetchAll();

    expect(callCount, 1);
    expect(result.fromCache, false);
    expect(result.events.length, 1);
    expect(result.events.first.corpName, '폴레드');
    expect(result.events.first.perShare, 200);

    // 캐시 저장 확인
    expect(prefs.getString('dividends_cache_body'), isNotNull);
    expect(prefs.getInt('dividends_cache_at'), isNotNull);
  });

  test('네트워크 예외 → 캐시 폴백(fromCache=true)', () async {
    SharedPreferences.setMockInitialValues({
      'dividends_cache_body': _sampleJson,
      // 24h 이전 타임스탬프 — 네트워크 재시도를 유도하되 실패 시 폴백해야 함
      'dividends_cache_at': DateTime.now()
          .subtract(const Duration(hours: 48))
          .millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();

    final mockClient = MockClient((request) async {
      throw Exception('network down');
    });

    final api = DividendApi(client: mockClient, prefs: prefs);
    final result = await api.fetchAll();

    expect(result.fromCache, true);
    expect(result.events.length, 1);
    expect(result.events.first.corpName, '폴레드');
  });

  test('캐시 24h 이내 → 네트워크 미호출(호출 카운터 0)', () async {
    SharedPreferences.setMockInitialValues({
      'dividends_cache_body': _sampleJson,
      'dividends_cache_at': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();

    var callCount = 0;
    final mockClient = MockClient((request) async {
      callCount++;
      return http.Response(_sampleJson, 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    final api = DividendApi(client: mockClient, prefs: prefs);
    final result = await api.fetchAll();

    expect(callCount, 0);
    expect(result.fromCache, true);
    expect(result.events.length, 1);
  });
}
