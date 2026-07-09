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

  test('손상된 신선 캐시(24h 이내) + 정상 네트워크 → 네트워크 결과 반환(24h 마비 방지)',
      () async {
    SharedPreferences.setMockInitialValues({
      // 파싱 불가능한 body(JSON 객체) 가 신선(<24h) 캐시에 들어있는 상황.
      'dividends_cache_body': '{"error":"x"}',
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

    // 손상 캐시를 무시하고 네트워크로 폴백 → 정상 결과.
    expect(callCount, 1);
    expect(result.fromCache, false);
    expect(result.events.length, 1);
    expect(result.events.first.corpName, '폴레드');
  });

  test('200 + JSON 객체(파싱 불가) 응답 → 캐시 오염 없음(기존 유효 캐시 유지)',
      () async {
    final staleAtMs = DateTime.now()
        .subtract(const Duration(hours: 48))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      // 기존 유효 캐시(만료 → 네트워크 재시도 유도).
      'dividends_cache_body': _sampleJson,
      'dividends_cache_at': staleAtMs,
    });
    final prefs = await SharedPreferences.getInstance();

    final mockClient = MockClient((request) async {
      // 200 이지만 배열이 아닌 JSON 객체 → 파싱 실패해야 함.
      return http.Response('{"error":"maintenance"}', 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    final api = DividendApi(client: mockClient, prefs: prefs);
    final result = await api.fetchAll();

    // 네트워크 파싱 실패 → 기존 유효 캐시로 폴백.
    expect(result.fromCache, true);
    expect(result.events.length, 1);
    expect(result.events.first.corpName, '폴레드');

    // 오염 방지: 캐시 body 는 여전히 원래 유효 JSON, 타임스탬프도 미갱신.
    expect(prefs.getString('dividends_cache_body'), _sampleJson);
    expect(prefs.getInt('dividends_cache_at'), staleAtMs);
  });
}
