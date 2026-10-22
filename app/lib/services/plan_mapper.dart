import '../engine/pension_input.dart';
import '../models/account.dart';
import '../models/retirement_input.dart';

/// 계획 탭 설정값 — 화면에서 바꾸는 가정들.
class PlanAssumptions {
  const PlanAssumptions({
    this.years = 25,
    this.returnRate = 0.04,
    this.annualTargetOverride,
    this.npsMonthly,
    this.npsStartAge,
  });

  final int years;
  final double returnRate;

  /// 연간 인출 목표(원). null 이면 내 자산의 월 인출액 합 × 12.
  final int? annualTargetOverride;
  final int? npsMonthly;
  final int? npsStartAge;

  PlanAssumptions copyWith({
    int? years,
    double? returnRate,
    int? annualTargetOverride,
    bool clearAnnualTarget = false,
    int? npsMonthly,
    int? npsStartAge,
    bool clearNps = false,
  }) => PlanAssumptions(
    years: years ?? this.years,
    returnRate: returnRate ?? this.returnRate,
    annualTargetOverride: clearAnnualTarget
        ? null
        : (annualTargetOverride ?? this.annualTargetOverride),
    npsMonthly: clearNps ? null : (npsMonthly ?? this.npsMonthly),
    npsStartAge: clearNps ? null : (npsStartAge ?? this.npsStartAge),
  );
}

/// 내 자산 → 계획 계산용 잔액 묶음.
class PlanBalances {
  const PlanBalances({
    required this.pensionSavings,
    required this.irp,
    required this.isa,
    required this.monthlyWithdrawal,
  });

  final int pensionSavings;
  final int irp;
  final int isa;

  /// 연금·ISA 계좌 월 인출액 합 (일반계좌는 인출 개념 없음).
  final int monthlyWithdrawal;

  int get total => pensionSavings + irp + isa;
}

/// 계좌 목록을 계획 입력으로 묶는다 (순수 함수).
///
/// - 기본 IRP 계좌만 IRP 로, 그 밖의 연금 유형 계좌(연금저축·사용자 추가 연금계좌)는 연금저축으로 본다.
/// - ISA 유형은 모두 ISA. 일반계좌는 연금 인출 계산 대상이 아니므로 제외.
/// - 월 인출액은 인출 개시(isWithdrawing) 계좌만 합산 — 이번 달 탭(cashflow_engine)과 같은 기준.
PlanBalances planBalancesFrom(List<Account> accounts) {
  var pension = 0, irp = 0, isa = 0, monthly = 0;
  for (final a in accounts) {
    switch (a.type) {
      case AccountType.pension:
        if (a.id == 'default_irp') {
          irp += a.balance;
        } else {
          pension += a.balance;
        }
        if (a.isWithdrawing) monthly += a.monthlyWithdrawal;
      case AccountType.isa:
        isa += a.balance;
        if (a.isWithdrawing) monthly += a.monthlyWithdrawal;
      case AccountType.general:
        break;
    }
  }
  return PlanBalances(
    pensionSavings: pension,
    irp: irp,
    isa: isa,
    monthlyWithdrawal: monthly,
  );
}

/// 계획 계산 입력. 계산할 수 없으면(잔액 0·인출 목표 0·나이 범위 밖) null.
///
/// [extras] 의 정확도 입력이 null(모름)이면 보수적으로 가정한다 — 연금저축 전액 세액공제분,
/// IRP 퇴직금 이전분 0, ISA 수익 0 (세금이 크게 나오는 쪽). 국민연금은 계획 탭에 따로 넣지 않았으면
/// 내 자산의 공적연금 월액을 쓴다(개시 = 65세, 이미 지났으면 지금).
PensionInput? buildPlanInput({
  required List<Account> accounts,
  required int currentAge,
  required PlanAssumptions assumptions,
  RetirementInput? extras,
}) {
  final b = planBalancesFrom(accounts);
  if (b.total <= 0) return null;
  final target = assumptions.annualTargetOverride ?? b.monthlyWithdrawal * 12;
  if (target <= 0) return null;
  var npsMonthly = assumptions.npsMonthly;
  var npsStartAge = assumptions.npsStartAge;
  if (npsMonthly == null && (extras?.publicPensionMonthly ?? 0) > 0) {
    npsMonthly = extras!.publicPensionMonthly;
    npsStartAge = currentAge >= 65 ? currentAge : 65;
  }
  final hasNps = (npsMonthly ?? 0) > 0 && npsStartAge != null;
  int clampTo(int? v, int max) => (v ?? 0).clamp(0, max);
  final nonDeducted = clampTo(extras?.pensionNonDeducted, b.pensionSavings);
  final input = PensionInput(
    pensionSavings: b.pensionSavings,
    pensionSavingsDeducted: b.pensionSavings - nonDeducted,
    irpBalance: b.irp,
    irpRetirementPortion: clampTo(extras?.irpRetirement, b.irp),
    isaMaturity: b.isa,
    isaProfit: clampTo(extras?.isaProfit, b.isa),
    currentAge: currentAge,
    targetAnnualWithdrawal: target,
    simulationYears: assumptions.years,
    expectedReturnRate: assumptions.returnRate,
    npsMonthlyAmount: hasNps ? npsMonthly : null,
    npsStartAge: hasNps ? npsStartAge : null,
    retirementTaxRate: ((extras?.retirementTaxRatePct ?? 5) / 100).clamp(
      0.0,
      0.45,
    ),
  );
  return input.isValid ? input : null;
}

/// 잔액이 있는데 '모름'으로 남은 정확도 입력 이름들 — 있으면 결과를 "기본 가정 비교"로 표시.
List<String> planUnknowns(List<Account> accounts, RetirementInput input) {
  final b = planBalancesFrom(accounts);
  return [
    if (b.pensionSavings > 0 && input.pensionNonDeducted == null)
      '세액공제 안 받은 원금',
    if (b.irp > 0 && input.irpRetirement == null) 'IRP 퇴직금',
    if (b.isa > 0 && input.isaProfit == null) 'ISA 수익',
  ];
}
