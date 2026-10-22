// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 지역가입자 보험료 계산.
///
/// 산식: 소득보험료(소득월액 × 정률, 반영률 적용) + 재산보험료(공제 → 등급표 →
/// 점수 × 단가) → 건강보험료 하한·상한 클램프 → 장기요양(건보료 × 요율).
library;

import 'models.dart';
import 'params.dart';
import 'rounding.dart';

/// 지역가입자 계산 결과(산식 분해 포함).
class RegionalResult {
  const RegionalResult({
    required this.reflectedAnnualIncome,
    required this.incomePremium,
    required this.propertyPoints,
    required this.propertyPremium,
    required this.healthPremiumRaw,
    required this.healthPremium,
    required this.ltcPremium,
    required this.total,
    required this.clampedToMin,
    required this.clampedToMax,
  });

  /// 반영률 적용 후 연간 소득(원).
  final int reflectedAnnualIncome;

  /// 소득분 월 보험료(원).
  final int incomePremium;

  /// 재산 부과점수.
  final int propertyPoints;

  /// 재산분 월 보험료(원).
  final int propertyPremium;

  /// 클램프 전 건강보험료(소득분 + 재산분, 원 절사).
  final int healthPremiumRaw;

  /// 하한·상한 적용 후 건강보험료(원).
  final int healthPremium;

  /// 장기요양보험료(원).
  final int ltcPremium;

  /// 월 납부 총액(건강보험료 + 장기요양, 원).
  final int total;

  final bool clampedToMin;
  final bool clampedToMax;
}

/// 지역가입자 보험료 계산기.
class RegionalCalculator {
  const RegionalCalculator(this.params);

  final HealthParams params;

  RegionalResult calculate({
    required IncomeInput income,
    required num propertyTaxBase,
  }) {
    final r = params.incomeReflect;
    final reflectedDouble =
        income.pension * r.pension +
        income.labor * r.labor +
        income.business * r.business +
        income.financial * r.financial +
        income.other * r.other;

    // 소득월액 × 정률.
    final incomePremiumDouble =
        (reflectedDouble / 12.0) * params.regionalIncomeRate;

    // 재산분: 공제 → 등급표 → 점수 × 단가.
    final netProperty = (propertyTaxBase - params.propertyDeduction).round();
    final grade = params.gradeForAmount(netProperty);
    final points = grade?.points ?? 0;
    final propertyPremiumDouble = points * params.propertyPointPrice;

    final healthRaw = wonFloor(incomePremiumDouble + propertyPremiumDouble);

    var health = healthRaw;
    var clampedToMin = false;
    var clampedToMax = false;
    if (health < params.minPremium) {
      health = params.minPremium;
      clampedToMin = true;
    } else if (health > params.maxPremium) {
      health = params.maxPremium;
      clampedToMax = true;
    }

    final ltc = wonFloor(health * params.ltcRateOfHealth);

    return RegionalResult(
      reflectedAnnualIncome: reflectedDouble.round(),
      incomePremium: wonFloor(incomePremiumDouble),
      propertyPoints: points,
      propertyPremium: wonFloor(propertyPremiumDouble),
      healthPremiumRaw: healthRaw,
      healthPremium: health,
      ltcPremium: ltc,
      total: health + ltc,
      clampedToMin: clampedToMin,
      clampedToMax: clampedToMax,
    );
  }
}
