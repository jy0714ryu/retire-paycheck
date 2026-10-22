import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../health_engine/engine.dart';
import '../models/retirement_input.dart';
import 'tax_constants.dart';

/// 건보 제도 파라미터 연도 (번들 JSON). 해마다 앱 업데이트로 갱신한다.
const int kHealthParamsYear = 2026;

class _BundleParamsSource implements ParamsSource {
  const _BundleParamsSource();

  @override
  Future<String> loadRaw(int year) =>
      rootBundle.loadString('assets/health_params/params_$year.json');
}

/// 건보료나침반 엔진 파라미터 — 번들만 쓴다(원격 갱신 없음, v2.2).
final healthParamsProvider = FutureProvider<HealthParams>(
  (ref) => HealthParams.load(const _BundleParamsSource(), kHealthParamsYear),
);

/// 은퇴월급 입력 → 건보 엔진 세대 입력.
///
/// - 공적연금: 월액 × 12
/// - 금융소득: 일반계좌 배당 + 이자 합계. 1,000만원 이하는 건보 소득에서 빠진다(0).
/// - 그 밖의 연 소득: 사업자등록이 있으면 사업소득, 없으면 기타소득으로 본다.
/// 배우자는 입력받지 않는다(v2.3 후보) — 화면에서 동반 탈락 주의 문구로 안내.
HouseholdInput householdFrom(
  RetirementInput input, {
  required int financialIncomeAnnual,
}) {
  final financial = financialIncomeAnnual > kHealthInsFinancialFloor
      ? financialIncomeAnnual
      : 0;
  return HouseholdInput(
    income: IncomeInput(
      pension: input.publicPensionMonthly * 12,
      financial: financial,
      business: input.businessRegistered ? input.otherAnnualIncome : 0,
      other: input.businessRegistered ? 0 : input.otherAnnualIncome,
      businessRegistered: input.businessRegistered,
    ),
    propertyTaxBase: input.propertyTaxBase,
    currentStatus: switch (input.healthInsType) {
      HealthInsType.dependent => HealthStatus.dependent,
      HealthInsType.employee => HealthStatus.employee,
      HealthInsType.regional => HealthStatus.regional,
    },
    avgMonthlySalary: input.lastMonthlySalary,
  );
}
