// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
import 'pension_input.dart';

/// 세금 계산 서비스
class TaxCalculator {
  TaxCalculator._();

  /// 연금소득세 계산 (분리과세)
  /// 
  /// 나이별 세율:
  /// - 55~69세: 5.5%
  /// - 70~79세: 4.4%
  /// - 80세 이상: 3.3%
  static int calculatePensionTax(int amount, int age) {
    if (amount <= 0) return 0;
    
    final rate = getPensionTaxRate(age);
    return (amount * rate).round();
  }

  /// 나이별 연금소득세율
  static double getPensionTaxRate(int age) {
    if (age >= 80) return 0.033;
    if (age >= 70) return 0.044;
    return 0.055; // 55~69세
  }

  /// ISA 만기 후 연금저축 이전 세액공제 계산
  /// 
  /// 조건: 만기 후 60일 내 이전
  /// 혜택: 이전액의 10% 세액공제 (최대 300만원)
  static IsaTransferResult calculateIsaTransferCredit(
    int transferAmount,
    IncomeLevel incomeLevel,
  ) {
    // 세액공제 기준액 (이전액의 10%, 최대 300만원)
    final creditBase = (transferAmount * 0.1).clamp(0, 3000000).toInt();
    
    // 공제율 (소득 수준에 따라)
    final rate = incomeLevel == IncomeLevel.high ? 0.132 : 0.165;
    
    // 실제 환급액
    final taxCredit = (creditBase * rate).round();
    
    return IsaTransferResult(
      transferAmount: transferAmount,
      creditBase: creditBase,
      taxCredit: taxCredit,
      rate: rate,
    );
  }

  /// 퇴직소득세 계산 (간이 계산)
  /// 
  /// 연금 수령 시 30% 감면 적용
  static int calculateRetirementTax(
    int retirementAmount,
    int yearsOfService, {
    bool isPension = true,
  }) {
    if (retirementAmount <= 0) return 0;
    
    // 근속연수 공제
    final deduction = _calculateServiceDeduction(yearsOfService);
    
    // 과세표준
    final taxable = (retirementAmount - deduction).clamp(0, double.infinity).toInt();
    if (taxable <= 0) return 0;
    
    // 환산급여
    final converted = (taxable * 12) ~/ yearsOfService;
    
    // 세금 계산 (퇴직소득 세율표 적용)
    final annualTax = _applyRetirementTaxBracket(converted);
    final tax = (annualTax * yearsOfService) ~/ 12;
    
    // 연금 수령 시 30% 감면
    if (isPension) {
      return (tax * 0.7).round();
    }
    
    return tax;
  }

  /// 근속연수 공제 계산
  static int _calculateServiceDeduction(int years) {
    if (years <= 5) {
      return 1000000 * years;
    } else if (years <= 10) {
      return 5000000 + 2000000 * (years - 5);
    } else if (years <= 20) {
      return 15000000 + 2500000 * (years - 10);
    } else {
      return 40000000 + 3000000 * (years - 20);
    }
  }

  /// 퇴직소득 세율표 적용
  static int _applyRetirementTaxBracket(int converted) {
    // 간이 세율표 (2026년 기준)
    if (converted <= 14000000) {
      return (converted * 0.06).round();
    } else if (converted <= 50000000) {
      return 840000 + ((converted - 14000000) * 0.15).round();
    } else if (converted <= 88000000) {
      return 6240000 + ((converted - 50000000) * 0.24).round();
    } else if (converted <= 150000000) {
      return 15360000 + ((converted - 88000000) * 0.35).round();
    } else if (converted <= 300000000) {
      return 37060000 + ((converted - 150000000) * 0.38).round();
    } else if (converted <= 500000000) {
      return 94060000 + ((converted - 300000000) * 0.40).round();
    } else if (converted <= 1000000000) {
      return 174060000 + ((converted - 500000000) * 0.42).round();
    } else {
      return 384060000 + ((converted - 1000000000) * 0.45).round();
    }
  }

  /// 기타소득세 계산 (55세 미만 중도 해지)
  static int calculateOtherIncomeTax(int amount) {
    return (amount * 0.165).round(); // 16.5%
  }

  /// 종합소득세 vs 분리과세 비교
  /// 
  /// 연간 연금소득 1,500만원 초과 시 선택 가능
  static TaxComparisonResult compareTaxation(
    int pensionIncome,
    int otherIncome,
    int age,
  ) {
    final separateTax = calculatePensionTax(pensionIncome, age);
    
    // 종합과세 시 (다른 소득과 합산)
    final totalIncome = pensionIncome + otherIncome;
    final comprehensiveTax = _calculateComprehensiveTax(totalIncome);
    
    return TaxComparisonResult(
      separateTax: separateTax,
      comprehensiveTax: comprehensiveTax,
      recommendation: separateTax <= comprehensiveTax 
          ? TaxationType.separate 
          : TaxationType.comprehensive,
    );
  }

  /// 종합소득세 계산 (간이)
  static int _calculateComprehensiveTax(int totalIncome) {
    // 기본공제 등 생략, 간이 계산
    final taxable = totalIncome;
    
    if (taxable <= 14000000) {
      return (taxable * 0.06).round();
    } else if (taxable <= 50000000) {
      return 840000 + ((taxable - 14000000) * 0.15).round();
    } else if (taxable <= 88000000) {
      return 6240000 + ((taxable - 50000000) * 0.24).round();
    } else if (taxable <= 150000000) {
      return 15360000 + ((taxable - 88000000) * 0.35).round();
    } else {
      return 37060000 + ((taxable - 150000000) * 0.38).round();
    }
  }
}

/// ISA 이전 세액공제 결과
class IsaTransferResult {
  final int transferAmount;
  final int creditBase;
  final int taxCredit;
  final double rate;

  const IsaTransferResult({
    required this.transferAmount,
    required this.creditBase,
    required this.taxCredit,
    required this.rate,
  });
}

/// 세금 비교 결과
class TaxComparisonResult {
  final int separateTax;
  final int comprehensiveTax;
  final TaxationType recommendation;

  const TaxComparisonResult({
    required this.separateTax,
    required this.comprehensiveTax,
    required this.recommendation,
  });

  int get difference => (separateTax - comprehensiveTax).abs();
}

/// 과세 방식
enum TaxationType {
  /// 분리과세
  separate,
  /// 종합과세
  comprehensive,
}
