// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
/// 연금 자산 입력 데이터 모델
class PensionInput {
  /// 연금저축 잔액 (원)
  final int pensionSavings;

  /// 연금저축 중 세액공제 받은 금액 (원)
  final int pensionSavingsDeducted;

  /// IRP 잔액 (원)
  final int irpBalance;

  /// IRP 중 퇴직금 이전분 (원)
  final int irpRetirementPortion;

  /// ISA 만기 예정액 (원)
  final int isaMaturity;

  /// ISA 수익분 (원) - 비과세 적용
  final int isaProfit;

  /// 현재 나이
  final int currentAge;

  /// 연간 목표 인출액 (원)
  final int targetAnnualWithdrawal;

  /// 시뮬레이션 기간 (년)
  final int simulationYears;

  /// 소득 수준 (세액공제율 결정용)
  final IncomeLevel incomeLevel;

  /// 예상 연평균 운용 수익률 (복리, 예: 0.04 = 4%)
  final double expectedReturnRate;

  /// 국민연금 월 수령액 (원, 선택 입력 — v1.1 소득 크레바스 통합)
  /// null이면 국민연금 미반영, 기존 동작과 100% 동일 (하위호환).
  final int? npsMonthlyAmount;

  /// 국민연금 수급 개시연령 (세, 선택 입력)
  /// null이면 국민연금 미반영, 기존 동작과 100% 동일 (하위호환).
  final int? npsStartAge;

  /// IRP 퇴직금 재원의 원래 퇴직소득세 실효세율 (기본 5%). 연금으로 받으면 70%(11년차부터 60%)만 낸다.
  final double retirementTaxRate;

  /// true(연금나침반 원래 뜻) = [targetAnnualWithdrawal] 은 국민연금을 포함한 연 생활비라
  /// 국민연금만큼 계좌 인출을 줄인다. false(은퇴월급) = 목표가 곧 '계좌에서 꺼낼 돈'이고
  /// 국민연금은 따로 들어오는 돈 — 인출을 줄이지 않고 표에만 보여 준다(v2.3.1 수정).
  final bool npsReducesTarget;

  const PensionInput({
    required this.pensionSavings,
    required this.pensionSavingsDeducted,
    required this.irpBalance,
    required this.irpRetirementPortion,
    required this.isaMaturity,
    this.isaProfit = 0,
    required this.currentAge,
    required this.targetAnnualWithdrawal,
    this.simulationYears = 20,
    this.incomeLevel = IncomeLevel.high,
    this.expectedReturnRate = 0.04,
    this.npsMonthlyAmount,
    this.npsStartAge,
    this.retirementTaxRate = 0.05,
    this.npsReducesTarget = true,
  });

  /// 국민연금 정보가 완전히 입력되었는지 (월수령액·개시연령 둘 다 있어야 활성)
  /// — 하나라도 null이면 크레바스 차감 없이 기존 동작과 동일하게 처리.
  bool get hasNps => npsMonthlyAmount != null && npsStartAge != null;

  /// 연금저축 중 세액공제 안 받은 금액
  int get pensionSavingsNonDeducted => pensionSavings - pensionSavingsDeducted;

  /// IRP 중 자기 납입분
  int get irpSelfContribution => irpBalance - irpRetirementPortion;

  /// ISA 원금
  int get isaPrincipal => isaMaturity - isaProfit;

  /// 총 자산
  int get totalAssets => pensionSavings + irpBalance + isaMaturity;

  /// 유효성 검사
  bool get isValid {
    return pensionSavings >= 0 &&
        pensionSavingsDeducted >= 0 &&
        pensionSavingsDeducted <= pensionSavings &&
        irpBalance >= 0 &&
        irpRetirementPortion >= 0 &&
        irpRetirementPortion <= irpBalance &&
        isaMaturity >= 0 &&
        isaProfit >= 0 &&
        isaProfit <= isaMaturity &&
        currentAge >= 20 &&
        currentAge <= 100 &&
        targetAnnualWithdrawal > 0 &&
        expectedReturnRate >= 0 &&
        expectedReturnRate <= 0.20 &&
        (npsMonthlyAmount == null || npsMonthlyAmount! >= 0) &&
        (npsStartAge == null || (npsStartAge! >= 50 && npsStartAge! <= 100));
  }

  PensionInput copyWith({
    int? pensionSavings,
    int? pensionSavingsDeducted,
    int? irpBalance,
    int? irpRetirementPortion,
    int? isaMaturity,
    int? isaProfit,
    int? currentAge,
    int? targetAnnualWithdrawal,
    int? simulationYears,
    IncomeLevel? incomeLevel,
    double? expectedReturnRate,
    int? npsMonthlyAmount,
    int? npsStartAge,
    double? retirementTaxRate,
    bool? npsReducesTarget,
  }) {
    return PensionInput(
      pensionSavings: pensionSavings ?? this.pensionSavings,
      pensionSavingsDeducted:
          pensionSavingsDeducted ?? this.pensionSavingsDeducted,
      irpBalance: irpBalance ?? this.irpBalance,
      irpRetirementPortion: irpRetirementPortion ?? this.irpRetirementPortion,
      isaMaturity: isaMaturity ?? this.isaMaturity,
      isaProfit: isaProfit ?? this.isaProfit,
      currentAge: currentAge ?? this.currentAge,
      targetAnnualWithdrawal:
          targetAnnualWithdrawal ?? this.targetAnnualWithdrawal,
      simulationYears: simulationYears ?? this.simulationYears,
      incomeLevel: incomeLevel ?? this.incomeLevel,
      expectedReturnRate: expectedReturnRate ?? this.expectedReturnRate,
      npsMonthlyAmount: npsMonthlyAmount ?? this.npsMonthlyAmount,
      npsStartAge: npsStartAge ?? this.npsStartAge,
      retirementTaxRate: retirementTaxRate ?? this.retirementTaxRate,
      npsReducesTarget: npsReducesTarget ?? this.npsReducesTarget,
    );
  }

  /// 기본값 (테스트/예시용)
  factory PensionInput.example() {
    return const PensionInput(
      pensionSavings: 100000000, // 1억
      pensionSavingsDeducted: 80000000, // 8천만원 공제받음
      irpBalance: 50000000, // 5천만원
      irpRetirementPortion: 40000000, // 4천만원 퇴직금
      isaMaturity: 30000000, // 3천만원
      isaProfit: 5000000, // 500만원 수익
      currentAge: 58,
      targetAnnualWithdrawal: 24000000, // 연 2400만원
      simulationYears: 20,
      expectedReturnRate: 0.04,
    );
  }

  /// JSON 직렬화 (시나리오 저장용 — v1.2)
  Map<String, dynamic> toJson() => {
    'pensionSavings': pensionSavings,
    'pensionSavingsDeducted': pensionSavingsDeducted,
    'irpBalance': irpBalance,
    'irpRetirementPortion': irpRetirementPortion,
    'isaMaturity': isaMaturity,
    'isaProfit': isaProfit,
    'currentAge': currentAge,
    'targetAnnualWithdrawal': targetAnnualWithdrawal,
    'simulationYears': simulationYears,
    'incomeLevel': incomeLevel.name,
    'expectedReturnRate': expectedReturnRate,
    'npsMonthlyAmount': npsMonthlyAmount,
    'npsStartAge': npsStartAge,
    'retirementTaxRate': retirementTaxRate,
  };

  factory PensionInput.fromJson(Map<String, dynamic> json) {
    return PensionInput(
      pensionSavings: (json['pensionSavings'] as num?)?.toInt() ?? 0,
      pensionSavingsDeducted:
          (json['pensionSavingsDeducted'] as num?)?.toInt() ?? 0,
      irpBalance: (json['irpBalance'] as num?)?.toInt() ?? 0,
      irpRetirementPortion:
          (json['irpRetirementPortion'] as num?)?.toInt() ?? 0,
      isaMaturity: (json['isaMaturity'] as num?)?.toInt() ?? 0,
      isaProfit: (json['isaProfit'] as num?)?.toInt() ?? 0,
      currentAge: (json['currentAge'] as num?)?.toInt() ?? 55,
      targetAnnualWithdrawal:
          (json['targetAnnualWithdrawal'] as num?)?.toInt() ?? 0,
      simulationYears: (json['simulationYears'] as num?)?.toInt() ?? 20,
      incomeLevel: IncomeLevel.values.firstWhere(
        (e) => e.name == json['incomeLevel'],
        orElse: () => IncomeLevel.high,
      ),
      expectedReturnRate:
          (json['expectedReturnRate'] as num?)?.toDouble() ?? 0.04,
      npsMonthlyAmount: (json['npsMonthlyAmount'] as num?)?.toInt(),
      npsStartAge: (json['npsStartAge'] as num?)?.toInt(),
      retirementTaxRate:
          (json['retirementTaxRate'] as num?)?.toDouble() ?? 0.05,
    );
  }

  /// 빈 입력 (초기값)
  factory PensionInput.empty() {
    return const PensionInput(
      pensionSavings: 0,
      pensionSavingsDeducted: 0,
      irpBalance: 0,
      irpRetirementPortion: 0,
      isaMaturity: 0,
      isaProfit: 0,
      currentAge: 55,
      targetAnnualWithdrawal: 24000000,
      simulationYears: 20,
      expectedReturnRate: 0.04,
    );
  }
}

/// 소득 수준 (세액공제율 결정)
enum IncomeLevel {
  /// 총급여 5,500만원 이하 (16.5% 공제율)
  low,

  /// 총급여 5,500만원 초과 (13.2% 공제율)
  high,
}
