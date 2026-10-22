// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 은퇴 전환 3-way 비교.
///
/// 임의계속(36개월 후 지역 전환 포함) vs 지역가입 vs 피부양자 편입(자격 충족 시 0원).
/// 월액·36개월 총액을 비교하고 최저 비용 선택지를 추천한다.
library;

import 'comparison_option.dart';
import 'dependent_judge.dart';
import 'models.dart';
import 'params.dart';
import 'regional_calculator.dart';
import 'voluntary_calculator.dart';

/// 3-way 비교 결과.
class ComparisonResult {
  const ComparisonResult({
    required this.voluntaryMonthly,
    required this.voluntary36Total,
    required this.regionalMonthly,
    required this.regional36Total,
    required this.dependentEligible,
    required this.dependentMonthly,
    required this.dependent36Total,
    required this.recommended,
    required this.regional,
    required this.voluntary,
    required this.dependent,
  });

  final int voluntaryMonthly;

  /// 임의계속 36개월 총액(원). 36개월간 임의계속 유지 기준.
  final int voluntary36Total;

  final int regionalMonthly;
  final int regional36Total;

  final bool dependentEligible;
  final int dependentMonthly; // 자격 충족 시 0.
  final int dependent36Total; // 자격 충족 시 0.

  /// 자격·비용을 반영한 추천 선택지.
  final ComparisonOption recommended;

  final RegionalResult regional;
  final VoluntaryResult voluntary;
  final DependentResult dependent;
}

/// 3-way 비교 엔진.
class RetirementComparison {
  RetirementComparison(this.params)
    : _regional = RegionalCalculator(params),
      _voluntary = VoluntaryCalculator(params),
      _judge = DependentJudge(params);

  final HealthParams params;
  final RegionalCalculator _regional;
  final VoluntaryCalculator _voluntary;
  final DependentJudge _judge;

  ComparisonResult compare(HouseholdInput input) {
    final regional = _regional.calculate(
      income: input.income,
      propertyTaxBase: input.propertyTaxBase,
    );
    final voluntary = _voluntary.calculate(
      avgMonthlySalary: input.avgMonthlySalary,
    );
    final dependent = _judge.judge(input);

    final dependentMonthly = dependent.isEligible ? 0 : -1;
    final dependent36 = dependent.isEligible ? 0 : -1;

    // 추천: 자격 충족 시 피부양자(0원) 최우선, 아니면 임의계속 vs 지역 저비용.
    final ComparisonOption recommended;
    if (dependent.isEligible) {
      recommended = ComparisonOption.dependent;
    } else if (voluntary.monthlyTotal <= regional.total) {
      recommended = ComparisonOption.voluntary;
    } else {
      recommended = ComparisonOption.regional;
    }

    return ComparisonResult(
      voluntaryMonthly: voluntary.monthlyTotal,
      voluntary36Total: voluntary.totalOverPeriod,
      regionalMonthly: regional.total,
      regional36Total: regional.total * 36,
      dependentEligible: dependent.isEligible,
      dependentMonthly: dependentMonthly,
      dependent36Total: dependent36,
      recommended: recommended,
      regional: regional,
      voluntary: voluntary,
      dependent: dependent,
    );
  }
}
