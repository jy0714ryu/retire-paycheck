// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 피부양자 자격 판정.
///
/// 3중 요건(소득·재산·사업소득) + 재산 구간별 소득 한도 + 배우자 동반탈락.
/// "탈락까지 여유 금액"을 역산해 게이지에 쓸 수 있게 반환한다.
library;

import 'models.dart';
import 'params.dart';

/// 판정 사유 코드.
class DependentReason {
  /// 소득 한도(저구간 2,000만) 초과.
  static const incomeOverLimit = 'INCOME_OVER_LIMIT';

  /// 재산 중구간 소득 한도(1,000만) 초과.
  static const incomeOverMidLimit = 'INCOME_OVER_MID_LIMIT';

  /// 재산 9억 초과 → 무조건 탈락.
  static const propertyOverLimit = 'PROPERTY_OVER_LIMIT';

  /// 사업자 등록 + 사업소득 발생.
  static const businessRegistered = 'BUSINESS_REGISTERED';

  /// 사업자 미등록 + 사업소득 한도(500만) 초과.
  static const businessUnregistered = 'BUSINESS_UNREGISTERED';

  /// 배우자 소득 요건 초과 → 본인 동반탈락.
  static const spouseJointFail = 'SPOUSE_JOINT_FAIL';
}

/// 재산 구간.
enum PropertyBand {
  /// 5.4억 이하 — 소득 한도 2,000만.
  low,

  /// 5.4억 초과 9억 이하 — 소득 한도 1,000만.
  mid,

  /// 9억 초과 — 무조건 탈락.
  over,
}

/// 피부양자 판정 결과.
class DependentResult {
  const DependentResult({
    required this.isEligible,
    required this.failReasons,
    required this.band,
    required this.applicableIncomeLimit,
    required this.totalIncome,
    required this.incomeMargin,
    required this.propertyMarginToNextBand,
    required this.spouseJointFail,
  });

  /// 피부양자 유지 가능 여부.
  final bool isEligible;

  /// 탈락 사유 코드(빈 리스트면 유지).
  final List<String> failReasons;

  final PropertyBand band;

  /// 현재 재산 구간에 적용되는 소득 한도(원). over 구간이면 -1(해당 없음).
  final int applicableIncomeLimit;

  /// 본인 합산소득(원).
  final int totalIncome;

  /// 소득 여유 = 한도 − 현재소득(원). 음수면 초과. over 구간이면 -1.
  final int incomeMargin;

  /// 재산 여유 = 다음 구간 경계까지 남은 금액(원). over 구간이면 0.
  final int propertyMarginToNextBand;

  /// 배우자 동반탈락 발생 여부.
  final bool spouseJointFail;
}

/// 피부양자 판정기.
class DependentJudge {
  const DependentJudge(this.params);

  final HealthParams params;

  DependentParams get _d => params.dependent;

  /// 재산과표 → 구간.
  PropertyBand bandFor(num propertyTaxBase) {
    if (propertyTaxBase <= _d.propertyLimitLow) return PropertyBand.low;
    if (propertyTaxBase <= _d.propertyLimitHigh) return PropertyBand.mid;
    return PropertyBand.over;
  }

  /// 구간별 적용 소득 한도(원). over 구간은 -1.
  int applicableIncomeLimit(PropertyBand band) {
    switch (band) {
      case PropertyBand.low:
        return _d.incomeLimit;
      case PropertyBand.mid:
        return _d.midIncomeLimit;
      case PropertyBand.over:
        return -1;
    }
  }

  /// 한 사람이 소득 요건(재산 구간 반영)을 통과하는지.
  bool _passesIncomeRequirement(PersonInput person) {
    final band = bandFor(person.propertyTaxBase);
    if (band == PropertyBand.over) return false;
    return person.income.totalIncome <= applicableIncomeLimit(band);
  }

  DependentResult judge(HouseholdInput input) {
    final reasons = <String>[];
    final band = bandFor(input.propertyTaxBase);
    final limit = applicableIncomeLimit(band);
    final totalIncome = input.income.totalIncome.round();

    // 1) 재산 요건.
    if (band == PropertyBand.over) {
      reasons.add(DependentReason.propertyOverLimit);
    }

    // 2) 소득 요건(재산 구간별 한도).
    if (band != PropertyBand.over && totalIncome > limit) {
      reasons.add(band == PropertyBand.mid
          ? DependentReason.incomeOverMidLimit
          : DependentReason.incomeOverLimit);
    }

    // 3) 사업소득 요건.
    final biz = input.income.business;
    if (input.income.businessRegistered) {
      if (biz > _d.bizRegisteredLimit) {
        reasons.add(DependentReason.businessRegistered);
      }
    } else if (biz > _d.bizUnregisteredLimit) {
      reasons.add(DependentReason.businessUnregistered);
    }

    // 4) 배우자 동반탈락(부부 모두 피부양자일 때, 배우자 소득 요건 초과 시 본인도 탈락).
    var spouseJointFail = false;
    final spouse = input.spouse;
    if (spouse != null && !_passesIncomeRequirement(spouse)) {
      spouseJointFail = true;
      reasons.add(DependentReason.spouseJointFail);
    }

    // 여유 금액 역산.
    final incomeMargin = band == PropertyBand.over ? -1 : limit - totalIncome;
    final propertyMargin = _propertyMargin(band, input.propertyTaxBase);

    return DependentResult(
      isEligible: reasons.isEmpty,
      failReasons: List.unmodifiable(reasons),
      band: band,
      applicableIncomeLimit: limit,
      totalIncome: totalIncome,
      incomeMargin: incomeMargin,
      propertyMarginToNextBand: propertyMargin,
      spouseJointFail: spouseJointFail,
    );
  }

  int _propertyMargin(PropertyBand band, num propertyTaxBase) {
    switch (band) {
      case PropertyBand.low:
        return (_d.propertyLimitLow - propertyTaxBase).round();
      case PropertyBand.mid:
        return (_d.propertyLimitHigh - propertyTaxBase).round();
      case PropertyBand.over:
        return 0;
    }
  }
}
