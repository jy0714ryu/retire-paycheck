// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 간편(추정) 재산과표 역산.
///
/// 주택 시세 → 공시가격(× 현실화율) → 재산세 과세표준(× 공정시장가액비율).
/// 어디까지나 추정치이며 실제 과세표준과 다를 수 있다("추정" 표기 필수).
library;

import 'params.dart';
import 'rounding.dart';

/// 간편 모드 추정 결과.
class SimplePropertyResult {
  const SimplePropertyResult({
    required this.marketPrice,
    required this.officialPrice,
    required this.taxBase,
    required this.appliedRatio,
    required this.singleHome,
  });

  /// 입력 시세(원).
  final int marketPrice;

  /// 추정 공시가격(원).
  final int officialPrice;

  /// 추정 재산세 과세표준(원).
  final int taxBase;

  /// 적용된 공정시장가액비율.
  final double appliedRatio;

  final bool singleHome;
}

/// 간편 모드 재산과표 추정기.
class SimplePropertyEstimator {
  const SimplePropertyEstimator(this.params);

  final HealthParams params;

  /// 시세 → 추정 과표.
  ///
  /// [singleHome] 이면 1세대 1주택 특례 공정시장가액비율(공시가 구간별)을 적용한다.
  SimplePropertyResult estimate({
    required num marketPrice,
    bool singleHome = false,
  }) {
    final s = params.simpleMode;
    final officialDouble = marketPrice * s.marketToOfficialRatio;
    final official = wonFloor(officialDouble);

    final double ratio;
    if (singleHome) {
      ratio = _singleHomeRatio(official);
    } else {
      ratio = s.fairMarketRatio;
    }

    final taxBase = wonFloor(official * ratio);

    return SimplePropertyResult(
      marketPrice: marketPrice.round(),
      officialPrice: official,
      taxBase: taxBase,
      appliedRatio: ratio,
      singleHome: singleHome,
    );
  }

  double _singleHomeRatio(int officialPrice) {
    for (final band in params.simpleMode.singleHomeBands) {
      final max = band.officialMax;
      if (max == null || officialPrice <= max) {
        return band.ratio;
      }
    }
    // 안전 폴백(도달 불가 — 마지막 구간 officialMax=null).
    return params.simpleMode.fairMarketRatio;
  }
}
