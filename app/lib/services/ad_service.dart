// pension-compass에서 이식 (2026-07-09) — dart-define 키명만 RETIRE_* 로 변경
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob 전면(Interstitial) 광고 서비스.
///
/// 달 넘기기 등 액션마다 호출되지만, 실제 노출은 5회마다 1회 + 직전 광고 후
/// 3분이 지났을 때만 발생한다(v2.3 — 2회마다는 "넘길 때마다 광고"로 느껴진다는 피드백).
/// 첫 4번은 광고 없이 가치를 먼저 경험 — AdMob 방해성 광고 정책·리텐션 보호.
/// 광고가 준비되지 않았거나 로드에 실패해도 사용자 흐름은 절대 막지 않고 조용히 넘어간다.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  /// 5회마다 1회 노출 (5·10·15…번째 호출 — 첫 4번은 면제)
  static const int _showEveryNCalls = 5;

  /// 직전 광고 노출 후 최소 간격 — 빠르게 넘겨도 연달아 뜨지 않게.
  static const Duration _minInterval = Duration(minutes: 3);

  /// 구글 공식 테스트 전면광고 ID (Android)
  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';

  /// 실제 광고 단위 ID (빌드 시 환경변수로 주입, 미지정 시 테스트 ID 사용)
  static const String _prodInterstitialId = String.fromEnvironment(
    'RETIRE_INTERSTITIAL_AD_UNIT_ID',
    defaultValue: _testInterstitialId,
  );

  String get _adUnitId =>
      kDebugMode ? _testInterstitialId : _prodInterstitialId;

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  int _callCount = 0;
  DateTime? _lastShownAt;

  /// 노출 여부 판정(순수 — 테스트용). [callCount] 는 이번 호출을 포함한 누적 횟수.
  @visibleForTesting
  static bool shouldShow({
    required int callCount,
    required DateTime now,
    DateTime? lastShownAt,
  }) {
    if (callCount % _showEveryNCalls != 0) return false;
    return lastShownAt == null || now.difference(lastShownAt) >= _minInterval;
  }

  /// SDK 초기화 + 첫 광고 미리 로드.
  ///
  /// 플랫폼 채널이 없는 테스트 환경(flutter test)에서 호출돼도
  /// MissingPluginException 등은 조용히 흡수하고 앱 흐름을 막지 않는다.
  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      _loadInterstitialAd();
    } catch (e) {
      debugPrint('📢 AdMob 초기화 실패 (테스트 환경 또는 플랫폼 미지원): $e');
    }
  }

  /// 전면 광고 미리 로드 (노출 전 준비)
  void _loadInterstitialAd() {
    if (_isLoading || _interstitialAd != null) return;
    _isLoading = true;

    InterstitialAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('📢 전면 광고 로드 완료');
          _interstitialAd = ad;
          _isLoading = false;
          _setAdCallbacks(ad);
        },
        onAdFailedToLoad: (error) {
          debugPrint('📢 전면 광고 로드 실패: ${error.message}');
          _interstitialAd = null;
          _isLoading = false;
          // 실패 시 5초 후 재시도
          Future.delayed(const Duration(seconds: 5), _loadInterstitialAd);
        },
      ),
    );
  }

  void _setAdCallbacks(InterstitialAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        // 다음 광고 미리 로드
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('📢 전면 광고 표시 실패: ${error.message}');
        ad.dispose();
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );
  }

  /// 액션마다 호출. 5회마다 1회(직전 광고 후 3분 경과 시) 전면 광고를 표시한다.
  /// 광고가 준비되지 않았으면 조용히 skip (UX 차단 금지).
  Future<void> showInterstitialIfEligible() async {
    _callCount++;
    final now = DateTime.now();
    if (!shouldShow(
      callCount: _callCount,
      now: now,
      lastShownAt: _lastShownAt,
    )) {
      return;
    }

    final ad = _interstitialAd;
    if (ad == null) {
      // 준비 안 됐으면 조용히 넘어가고 다음 기회를 위해 로드 시도
      _loadInterstitialAd();
      return;
    }

    try {
      _lastShownAt = now;
      await ad.show();
    } catch (e) {
      debugPrint('📢 전면 광고 표시 중 오류: $e');
      _interstitialAd = null;
      _loadInterstitialAd();
    }
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
