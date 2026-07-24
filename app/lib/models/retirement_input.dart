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

  /// 전역 인출 개시 연-월(예: 2030-03). null 이면 "현재월부터 즉시 인출"
  /// (기존 동작 완전 보존 — 마이그레이션·기존 사용자 무변화). 항상 해당 월의
  /// 1일로 정규화된 값을 담는다(생성부·[fromJson] 책임). 엔진은 이 월 **이전**
  /// 달의 모든 인출을 0 으로 게이팅한다.
  final DateTime? withdrawalStartMonth;

  const RetirementInput({
    required this.pensionSavings,
    required this.irpBalance,
    required this.isaBalance,
    required this.currentAge,
    required this.monthlyPensionWithdrawal,
    required this.monthlyOtherWithdrawal,
    this.annualInterestIncome = 0,
    this.isWithdrawing = true,
    this.withdrawalStartMonth,
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

  /// [withdrawalStartMonth] 는 null 을 명시적으로 지정할 수 있어야 하므로
  /// (기본값 = "설정 안 함(지금부터)"으로 되돌리기) sentinel 패턴을 쓴다.
  /// [clearWithdrawalStartMonth] = true 면 null 로 초기화한다.
  RetirementInput copyWith({
    int? pensionSavings,
    int? irpBalance,
    int? isaBalance,
    int? currentAge,
    int? monthlyPensionWithdrawal,
    int? monthlyOtherWithdrawal,
    int? annualInterestIncome,
    bool? isWithdrawing,
    DateTime? withdrawalStartMonth,
    bool clearWithdrawalStartMonth = false,
  }) {
    final nextStart = clearWithdrawalStartMonth
        ? null
        : (withdrawalStartMonth ?? this.withdrawalStartMonth);
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
      withdrawalStartMonth:
          nextStart == null ? null : DateTime(nextStart.year, nextStart.month),
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
        // null 이면 키를 내보내지 않아 기존 저장분과 완전 호환(마이그레이션 불필요).
        if (withdrawalStartMonth != null)
          'withdrawal_start_month':
              '${withdrawalStartMonth!.year.toString().padLeft(4, '0')}-'
                  '${withdrawalStartMonth!.month.toString().padLeft(2, '0')}',
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
      // 'YYYY-MM' (또는 'YYYY-MM-DD') 문자열 → 연-월 정규화. 키 없음/null 이면 null.
      withdrawalStartMonth: _parseYearMonth(json['withdrawal_start_month']),
    );
  }

  /// 'YYYY-MM' 또는 'YYYY-MM-DD' 를 해당 월 1일 DateTime 으로 파싱. 실패 시 null.
  static DateTime? _parseYearMonth(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length < 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month);
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
          isWithdrawing == other.isWithdrawing &&
          withdrawalStartMonth == other.withdrawalStartMonth;

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
        withdrawalStartMonth,
      );
}
