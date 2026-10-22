// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 계산 엔진 입력 모델.
///
/// 순수 Dart. 모든 금액은 **연 단위 원(KRW)** (소득) 또는 **원**(재산과표·보수월액).
library;

/// 현재 건강보험 자격.
enum HealthStatus {
  /// 직장가입자.
  employee,

  /// 지역가입자.
  regional,

  /// 피부양자.
  dependent,

  /// 임의계속가입자.
  voluntary,
}

/// 소득 5종(모두 **연 단위 원**).
///
/// 사업소득 [businessRegistered] 여부는 피부양자 사업소득 요건 판정에 쓰인다.
class IncomeInput {
  const IncomeInput({
    this.pension = 0,
    this.financial = 0,
    this.business = 0,
    this.labor = 0,
    this.other = 0,
    this.businessRegistered = false,
  });

  /// 공적연금소득(국민·공무원연금 등).
  final num pension;

  /// 금융소득(이자·배당).
  final num financial;

  /// 사업소득.
  final num business;

  /// 근로소득.
  final num labor;

  /// 기타소득.
  final num other;

  /// 사업자 등록 여부.
  final bool businessRegistered;

  /// 피부양자 소득 요건에 쓰이는 합산소득(반영률 미적용, 실제 금액 전부 합산).
  ///
  /// 사업소득도 합산소득에 포함된다(사업소득 요건과 별개로 소득 한도에도 반영).
  num get totalIncome => pension + financial + business + labor + other;

  IncomeInput copyWith({
    num? pension,
    num? financial,
    num? business,
    num? labor,
    num? other,
    bool? businessRegistered,
  }) =>
      IncomeInput(
        pension: pension ?? this.pension,
        financial: financial ?? this.financial,
        business: business ?? this.business,
        labor: labor ?? this.labor,
        other: other ?? this.other,
        businessRegistered: businessRegistered ?? this.businessRegistered,
      );
}

/// 한 사람(본인/배우자)의 소득·재산 스냅샷 (피부양자 동반탈락 판정용).
class PersonInput {
  const PersonInput({
    this.income = const IncomeInput(),
    this.propertyTaxBase = 0,
  });

  final IncomeInput income;

  /// 재산과세표준(원).
  final num propertyTaxBase;
}

/// 세대(본인 + 선택적 배우자) 종합 입력.
class HouseholdInput {
  const HouseholdInput({
    required this.income,
    this.propertyTaxBase = 0,
    this.currentStatus = HealthStatus.employee,
    this.spouse,
    this.avgMonthlySalary = 0,
  });

  /// 본인 소득.
  final IncomeInput income;

  /// 본인 재산과세표준(원).
  final num propertyTaxBase;

  /// 현재 자격.
  final HealthStatus currentStatus;

  /// 배우자(피부양자 동반탈락 판정용). 없으면 null.
  final PersonInput? spouse;

  /// 퇴직 전 12개월 평균 보수월액(세전, 원) — 임의계속 산정용.
  final num avgMonthlySalary;

  /// 본인 스냅샷.
  PersonInput get self =>
      PersonInput(income: income, propertyTaxBase: propertyTaxBase);
}
