import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dividend_event.dart';

const String _kCacheBodyKey = 'dividends_cache_body';
const String _kCacheAtKey = 'dividends_cache_at';

/// 신선 캐시 유효기간. 이 기간 이내면 네트워크를 생략하고 캐시를 반환한다.
///
/// 과거 24h 는 서버 배당 갱신(payment_date 추가 등)이 만 하루 동안 앱에 반영되지
/// 않는 스테일 창을 만들었다(앱 재시작도 디스크 캐시라 무효 — 출시 차단 버그).
/// 3h 로 축소해 자동 스테일 상한을 좁힌다. 오프라인/네트워크 실패 시 폴백은 이
/// TTL 을 무시하고 캐시를 계속 사용하므로 오프라인 사용성은 유지된다.
const Duration _kCacheTtl = Duration(hours: 3);

/// 배당 API 조회 결과 — 캐시 여부와 기준 시각을 함께 담는다.
class DividendFetchResult {
  final List<DividendEvent> events;
  final DateTime fetchedAt;
  final bool fromCache;

  const DividendFetchResult({
    required this.events,
    required this.fetchedAt,
    required this.fromCache,
  });
}

/// 배당 이벤트 API 클라이언트.
///
/// 온디바이스 원칙: 요청에 자산 정보(보유 종목·수량 등)를 절대 포함하지 않는다 —
/// 항상 무파라미터(페이징 한도만) 전체 목록 조회.
///
/// 성공 시 응답 본문+시각을 SharedPreferences에 캐시하고, 네트워크 실패/오프라인
/// 시에는 캐시를 TTL 무시하고 반환한다(fromCache=true). 캐시가 [_kCacheTtl](3시간)
/// 이내면 네트워크 호출 자체를 생략한다.
class DividendApi {
  // limit=8000: 국내 ETF 전수 수집(2026-07-30, 951개 ETF·5천여 이벤트) 반영.
  // 서버는 현재 limit 을 무시하고 15개월 범위 전량 반환하나, clamp 도입 대비 상향.
  // RETIRE_DIVIDEND_URL: 웹 체험판 빌드 전용 — 외부 호출이 막힌 곳에서 같은 폴더의
  // 스냅샷 JSON(예: 'dividends.json')을 읽게 한다. 앱 빌드는 기본값(운영 API) 그대로.
  static const String _baseUrl = String.fromEnvironment(
    'RETIRE_DIVIDEND_URL',
    defaultValue:
        'https://api.quant-view.co.kr/dividends?limit=8000&include_predicted=true',
  );

  final http.Client _client;
  SharedPreferences? _prefs;

  DividendApi({http.Client? client, SharedPreferences? prefs})
    : _client = client ?? http.Client(),
      // ignore: prefer_initializing_formals
      _prefs = prefs;

  Future<SharedPreferences> _prefsInstance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// [force] = 당겨서 새로고침 등 사용자 명시 갱신 — 신선 캐시를 무시하고
  /// 네트워크를 우선한다(실패 시 캐시 폴백은 유지).
  Future<DividendFetchResult> fetchAll({bool force = false}) async {
    final prefs = await _prefsInstance();
    final cachedAtMs = prefs.getInt(_kCacheAtKey);
    final cachedBody = prefs.getString(_kCacheBodyKey);

    if (!force && cachedAtMs != null && cachedBody != null) {
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      if (DateTime.now().difference(cachedAt) < _kCacheTtl) {
        try {
          return _parse(cachedBody, cachedAt, fromCache: true);
        } catch (_) {
          // 손상된 신선 캐시 — 무시하고 네트워크 경로로 폴백(24h 마비 방지).
        }
      }
    }

    try {
      final response = await _client.get(Uri.parse(_baseUrl));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'DividendApi: unexpected status ${response.statusCode}',
        );
      }
      final now = DateTime.now();
      // 파싱 성공을 먼저 검증한 뒤에만 캐시에 저장한다(오염 방지).
      final result = _parse(response.body, now, fromCache: false);
      await prefs.setString(_kCacheBodyKey, response.body);
      await prefs.setInt(_kCacheAtKey, now.millisecondsSinceEpoch);
      return result;
    } catch (_) {
      if (cachedBody != null && cachedAtMs != null) {
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
        try {
          return _parse(cachedBody, cachedAt, fromCache: true);
        } catch (_) {
          // 캐시도 손상 — 원 예외를 전파한다.
        }
      }
      rethrow;
    }
  }

  DividendFetchResult _parse(
    String body,
    DateTime fetchedAt, {
    required bool fromCache,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('DividendApi: expected a JSON array');
    }
    final events = decoded
        .map((e) => DividendEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    return DividendFetchResult(
      events: events,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );
  }
}
