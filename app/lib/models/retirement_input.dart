/// 은퇴 자산·인출 계획 입력값 — 화면1(자산 입력)에서 수집.
///
/// 금액은 전부 int 원 단위.
class RetirementInput {
  final int pensionSavings; // 연금저축 잔액
  final int irpBalance; // IRP 잔액
  final int isaBalance; // ISA 잔액
  final int currentAge;
  final int monthlyPensionWithdrawal; // 연금저축·IRP분 (과세대상 보수 가정)
  final int monthlyOtherWithdrawal; // ISA·기타분 (비과세 취급)
  final int annualInterestIncome; // 선택 입력, 기본 0

  /// 연금 인출 모드 — false(운용기)면 인출 입력을 숨기고 인출 0 취급 (스펙 §1.3).
  final bool isWithdrawing;

  const RetirementInput({
    required this.pensionSavings,
    required this.irpBalance,
    required this.isaBalance,
    required this.currentAge,
    required this.monthlyPensionWithdrawal,
    required this.monthlyOtherWithdrawal,
    this.annualInterestIncome = 0,
    this.isWithdrawing = true,
  });

  /// 음수 금지, 나이 20~100 범위만 유효.
  bool get isValid {
    if (pensionSavings < 0 ||
        irpBalance < 0 ||
        isaBalance < 0 ||
        monthlyPensionWithdrawal < 0 ||
        monthlyOtherWithdrawal < 0 ||
        annualInterestIncome < 0) {
      return false;
    }
    if (currentAge < 20 || currentAge > 100) {
      return false;
    }
    return true;
  }

  RetirementInput copyWith({
    int? pensionSavings,
    int? irpBalance,
    int? isaBalance,
    int? currentAge,
    int? monthlyPensionWithdrawal,
    int? monthlyOtherWithdrawal,
    int? annualInterestIncome,
    bool? isWithdrawing,
  }) {
    return RetirementInput(
      pensionSavings: pensionSavings ?? this.pensionSavings,
      irpBalance: irpBalance ?? this.irpBalance,
      isaBalance: isaBalance ?? this.isaBalance,
      currentAge: currentAge ?? this.currentAge,
      monthlyPensionWithdrawal:
          monthlyPensionWithdrawal ?? this.monthlyPensionWithdrawal,
      monthlyOtherWithdrawal:
          monthlyOtherWithdrawal ?? this.monthlyOtherWithdrawal,
      annualInterestIncome: annualInterestIncome ?? this.annualInterestIncome,
      isWithdrawing: isWithdrawing ?? this.isWithdrawing,
    );
  }

  Map<String, dynamic> toJson() => {
        'pension_savings': pensionSavings,
        'irp_balance': irpBalance,
        'isa_balance': isaBalance,
        'current_age': currentAge,
        'monthly_pension_withdrawal': monthlyPensionWithdrawal,
        'monthly_other_withdrawal': monthlyOtherWithdrawal,
        'annual_interest_income': annualInterestIncome,
        'is_withdrawing': isWithdrawing,
      };

  factory RetirementInput.fromJson(Map<String, dynamic> json) {
    return RetirementInput(
      pensionSavings: (json['pension_savings'] as num?)?.toInt() ?? 0,
      irpBalance: (json['irp_balance'] as num?)?.toInt() ?? 0,
      isaBalance: (json['isa_balance'] as num?)?.toInt() ?? 0,
      currentAge: (json['current_age'] as num?)?.toInt() ?? 0,
      monthlyPensionWithdrawal:
          (json['monthly_pension_withdrawal'] as num?)?.toInt() ?? 0,
      monthlyOtherWithdrawal:
          (json['monthly_other_withdrawal'] as num?)?.toInt() ?? 0,
      annualInterestIncome:
          (json['annual_interest_income'] as num?)?.toInt() ?? 0,
      // 명시 키 우선, 없으면(v1 저장분) 인출액>0 여부로 판정(스펙 §1.3 마이그레이션).
      isWithdrawing: json['is_withdrawing'] as bool? ??
          (((json['monthly_pension_withdrawal'] as num?)?.toInt() ?? 0) > 0 ||
              ((json['monthly_other_withdrawal'] as num?)?.toInt() ?? 0) >
                  0),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetirementInput &&
          runtimeType == other.runtimeType &&
          pensionSavings == other.pensionSavings &&
          irpBalance == other.irpBalance &&
          isaBalance == other.isaBalance &&
          currentAge == other.currentAge &&
          monthlyPensionWithdrawal == other.monthlyPensionWithdrawal &&
          monthlyOtherWithdrawal == other.monthlyOtherWithdrawal &&
          annualInterestIncome == other.annualInterestIncome &&
          isWithdrawing == other.isWithdrawing;

  @override
  int get hashCode => Object.hash(
        pensionSavings,
        irpBalance,
        isaBalance,
        currentAge,
        monthlyPensionWithdrawal,
        monthlyOtherWithdrawal,
        annualInterestIncome,
        isWithdrawing,
      );
}
