// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
/// 국민연금 간이 추정 서비스
///
/// ⚠️ 간이 근사 산식이다. 국민연금공단 실제 지급액은 가입기간 중 매년 재평가된
/// 소득(재평가율 적용)·소득대체율 변경 경과조치(2025-12-31 이전/이후 가입기간 분리
/// 계산) 등을 정밀 반영하므로 공단 공식 조회값과 차이가 날 수 있다.
/// 근거: docs/TAX_RULES.md §7 국민연금 (v1.1 Task 1)
library;

/// A값 — 연금 수급 개시 직전 3년간 전체 가입자 평균소득월액 평균 (원/월)
/// 보건복지부 고시, 2026년 적용
const int npsAValue = 3193511;

/// 비례상수 (소득대체율 43% 환산, 파생값·미공식확인 — TAX_RULES.md §7.2 참조)
/// 1.2 × (43/40) 근사. 2025-12-31 이전/이후 가입기간 분리 계산은 미반영(단일 상수로 근사).
const double npsProportionalConstant = 1.290;

/// 소득대체율 (40년 가입 기준, 2026-01-01 이후 가입기간)
/// 국민연금법 개정 (2025-03 국회통과, 2026-01-01 시행). 산식에는 비례상수에 이미 반영되어
/// 직접 사용되지 않음 — 상수 요약 대조용으로 보존.
const double npsIncomeReplacementRate = 0.43;

/// 기본연금액 100% 산정 기준 가입기간 (년) — 20년 만근 시 계수 1.0
const int npsFullCreditYears = 20;

/// 20년 기준 가입기간 1년(12개월)당 가감산율 (연 5%, 20년 초과 가산·20년 미만 감액 동일 비율)
const double npsYearBonusRate = 0.05;

/// 기준소득월액 하한액 (원/월) — 보건복지부 고시, 2026-07~2027-06 적용
const int npsIncomeFloor = 410000;

/// 기준소득월액 상한액 (원/월) — 보건복지부 고시, 2026-07~2027-06 적용
const int npsIncomeCeiling = 6590000;

/// 조기노령연금 감액률 (연 6%, 최대 5년 조기 → 최대 30% 감액, 영구 적용)
const double earlyPensionReductionRatePerYear = 0.06;

/// 조기노령연금 최대 조기연수
const int earlyPensionMaxYears = 5;

/// 연기연금 증액률 (연 7.2%, 최대 5년 연기 → 최대 36% 증액, 영구 적용)
const double deferredPensionIncreaseRatePerYear = 0.072;

/// 연기연금 최대 연기연수
const int deferredPensionMaxYears = 5;

/// 노령연금 수급 최소 가입기간 (10년 = 120개월) — 미만 시 수급 불가(반환일시금 대상)
const int npsMinEnrollmentMonths = 120;

/// 수령 방식
enum NpsReceiptType {
  /// 조기노령연금 (최대 5년 조기, 연 6% 감액)
  early,

  /// 정상 수급개시연령
  normal,

  /// 연기연금 (최대 5년 연기, 연 7.2% 증액)
  deferred,
}

/// 수급 자격 상태
enum NpsEligibility {
  /// 가입기간 10년 이상 — 노령연금 수급 가능
  eligible,

  /// 가입기간 10년 미만 — 노령연금 수급 불가
  ineligibleShortEnrollment,
}

/// 국민연금 간이 추정 입력값
class NpsEstimateInput {
  /// 월소득 (원) — B값(가입기간 중 평균소득월액) 근사치로 사용.
  /// 기준소득월액 상한·하한으로 클램프되어 계산에 반영된다.
  final int monthlyIncome;

  /// 총 가입기간 (개월)
  final int enrollmentMonths;

  /// 출생연도 — 수급개시연령 판정용
  final int birthYear;

  /// 수령 방식 (조기/정상/연기)
  final NpsReceiptType receiptType;

  /// 조기/연기 연수 (0~5). receiptType == normal 이면 무시하고 0으로 처리한다.
  final int offsetYears;

  const NpsEstimateInput({
    required this.monthlyIncome,
    required this.enrollmentMonths,
    required this.birthYear,
    required this.receiptType,
    this.offsetYears = 0,
  });
}

/// 국민연금 간이 추정 결과
class NpsEstimateResult {
  /// 간이 추정 여부 — 항상 true. 공단 실측값 직접 입력과 구분하는 용도
  /// (exec-plan ① "정확값 우회로" 넛지 버튼이 이 플래그를 참조).
  final bool isEstimate = true;

  /// 수급 자격 상태
  final NpsEligibility eligibility;

  /// 월 예상수령액 (원) — 수급 불가 시 0
  final int monthlyPensionAmount;

  /// 표준 수급개시연령 (출생연도 기준, 조기/연기 미반영)
  final int normalStartAge;

  /// 실제 수급개시연령 (조기/연기 반영)
  final int actualStartAge;

  /// 적용된 감액/증액률 (조기=음수, 연기=양수, 정상=0)
  final double adjustmentRate;

  /// 클램프 적용된 조기/연기 연수 (0~5)
  final int appliedOffsetYears;

  /// 클램프 적용된 월소득 (기준소득월액 상한·하한 반영, 원)
  final int clampedMonthlyIncome;

  const NpsEstimateResult({
    required this.eligibility,
    required this.monthlyPensionAmount,
    required this.normalStartAge,
    required this.actualStartAge,
    required this.adjustmentRate,
    required this.appliedOffsetYears,
    required this.clampedMonthlyIncome,
  });

  /// 수급 가능 여부 (편의 게터)
  bool get isEligible => eligibility == NpsEligibility.eligible;
}

/// 국민연금 간이 추정 계산기
class NpsEstimator {
  NpsEstimator._();

  /// 출생연도별 표준 수급개시연령 (TAX_RULES.md §7.3)
  static int normalStartAgeFor(int birthYear) {
    if (birthYear <= 1952) return 60;
    if (birthYear <= 1956) return 61;
    if (birthYear <= 1960) return 62;
    if (birthYear <= 1964) return 63;
    if (birthYear <= 1968) return 64;
    return 65; // 1969년 이후
  }

  /// 국민연금 간이 추정 실행
  ///
  /// 산식 (TAX_RULES.md §7.1):
  /// 기본연금액(연액) = 비례상수 × (A값 + B값) × [1 + 0.05 × (가입월수 - 240) / 12]
  /// (20년 초과 가산·20년 미만 감액이 동일 비율이라 단일 식으로 통합)
  ///
  /// ★ 산식 결과는 **연액(원/년)** — 월액은 ÷12로 변환한다.
  /// 검증: B=A(평균소득자)·40년 가입 시 연액 = 1.29×2A×2 = 5.16A,
  /// 월액 = 5.16A/12 = 0.43A → 소득대체율 43% 정의와 정확히 일치.
  static NpsEstimateResult estimate(NpsEstimateInput input) {
    final normalStartAge = normalStartAgeFor(input.birthYear);
    final clampedIncome = input.monthlyIncome
        .clamp(npsIncomeFloor, npsIncomeCeiling)
        .toInt();

    if (input.enrollmentMonths < npsMinEnrollmentMonths) {
      return NpsEstimateResult(
        eligibility: NpsEligibility.ineligibleShortEnrollment,
        monthlyPensionAmount: 0,
        normalStartAge: normalStartAge,
        actualStartAge: normalStartAge,
        adjustmentRate: 0,
        appliedOffsetYears: 0,
        clampedMonthlyIncome: clampedIncome,
      );
    }

    // 가입기간 20년(240개월) 기준 ±5%/년 계수
    final coefficient =
        1 +
        npsYearBonusRate *
            (input.enrollmentMonths - npsFullCreditYears * 12) /
            12;
    // 기본연금액은 연액(원/년) — ÷12로 월액 변환
    final basicAnnualAmount =
        npsProportionalConstant * (npsAValue + clampedIncome) * coefficient;
    final basicMonthly = (basicAnnualAmount / 12).round();

    var appliedOffsetYears = 0;
    var adjustmentRate = 0.0;
    var actualStartAge = normalStartAge;

    if (input.receiptType == NpsReceiptType.early) {
      appliedOffsetYears = input.offsetYears
          .clamp(0, earlyPensionMaxYears)
          .toInt();
      adjustmentRate = -(earlyPensionReductionRatePerYear * appliedOffsetYears);
      actualStartAge = normalStartAge - appliedOffsetYears;
    } else if (input.receiptType == NpsReceiptType.deferred) {
      appliedOffsetYears = input.offsetYears
          .clamp(0, deferredPensionMaxYears)
          .toInt();
      adjustmentRate = deferredPensionIncreaseRatePerYear * appliedOffsetYears;
      actualStartAge = normalStartAge + appliedOffsetYears;
    }

    final monthlyPensionAmount = (basicMonthly * (1 + adjustmentRate)).round();

    return NpsEstimateResult(
      eligibility: NpsEligibility.eligible,
      monthlyPensionAmount: monthlyPensionAmount,
      normalStartAge: normalStartAge,
      actualStartAge: actualStartAge,
      adjustmentRate: adjustmentRate,
      appliedOffsetYears: appliedOffsetYears,
      clampedMonthlyIncome: clampedIncome,
    );
  }
}
