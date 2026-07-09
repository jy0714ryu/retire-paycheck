// pension-compass에서 이식 (2026-07-09) — dart-define 키명만 RETIRE_* 로 변경
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 달력·게이지 화면 하단에 상시 배치되는 적응형 배너 광고.
///
/// 로드 실패·예외(플랫폼 채널 부재 등 테스트 환경 포함) 시
/// [SizedBox.shrink] 로 폴백해 레이아웃을 절대 깨뜨리지 않는다.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  static const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';

  static const String _prodBannerId = String.fromEnvironment(
    'RETIRE_BANNER_AD_UNIT_ID',
    defaultValue: _testBannerId,
  );

  String get _adUnitId => kDebugMode ? _testBannerId : _prodBannerId;

  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  Future<void> _loadBannerAd() async {
    try {
      final ad = BannerAd(
        adUnitId: _adUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loadedAd) {
            if (!mounted) {
              loadedAd.dispose();
              return;
            }
            setState(() {
              _bannerAd = loadedAd as BannerAd;
              _isLoaded = true;
            });
          },
          onAdFailedToLoad: (loadedAd, error) {
            debugPrint('📢 배너 광고 로드 실패: ${error.message}');
            loadedAd.dispose();
          },
        ),
      );
      await ad.load();
    } catch (e) {
      // 플랫폼 채널 부재(테스트 환경) 등 — 조용히 SizedBox.shrink() 유지
      debugPrint('📢 배너 광고 로드 중 예외 (테스트 환경 또는 플랫폼 미지원): $e');
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: AdSize.banner.height.toDouble(),
      width: AdSize.banner.width.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
