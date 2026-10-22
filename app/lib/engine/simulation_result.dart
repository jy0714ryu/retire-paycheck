// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
/// 시뮬레이션 결과 모델
class SimulationResult {
  /// 연도별 인출 스케줄
  final List<YearlyWithdrawal> schedule;

  /// 총 세금 (최적화 방식)
  final int totalTaxOptimal;

  /// 총 세금 (기존 방식)
  final int totalTaxBaseline;

  /// 최적 인출 순서
  final List<WithdrawalSource> optimalSequence;

  /// 토너먼트 전체 결과 (전략 비교용)
  final List<StrategyOutcome> outcomes;

  /// 우승 전략 id / 표시명
  final String optimalStrategyId;
  final String optimalStrategyName;

  /// 기존 방식(baseline) 연도별 스케줄 — 차트 실데이터용
  final List<YearlyWithdrawal> baselineSchedule;

  const SimulationResult({
    required this.schedule,
    required this.totalTaxOptimal,
    required this.totalTaxBaseline,
    required this.optimalSequence,
    this.outcomes = const [],
    this.optimalStrategyId = '',
    this.optimalStrategyName = '',
    this.baselineSchedule = const [],
  });

  /// 절감 금액 — 우승 판정은 taxBurden(잠재세 포함) 기준이라 이론상
  /// totalTaxOptimal이 baseline보다 클 수 있어 음수 방지 clamp 적용.
  int get savings => (totalTaxBaseline - totalTaxOptimal).clamp(0, 1 << 60);

  /// 절감률 (%)
  double get savingsRate {
    if (totalTaxBaseline == 0) return 0;
    return (savings / totalTaxBaseline) * 100;
  }

  /// 시뮬레이션 기간 (년)
  int get years => schedule.length;

  /// 연도별 누적 세금 (최적화)
  List<int> get cumulativeTaxOptimal {
    final result = <int>[];
    int cumulative = 0;
    for (final year in schedule) {
      cumulative += year.totalTax;
      result.add(cumulative);
    }
    return result;
  }

  /// 연도별 누적 세금 (기존 방식) — baselineSchedule 기반 실데이터
  List<int> get cumulativeTaxBaseline {
    final result = <int>[];
    int cumulative = 0;
    for (final year in baselineSchedule) {
      cumulative += year.totalTax;
      result.add(cumulative);
    }
    return result;
  }
}

/// 연도별 인출 내역
class YearlyWithdrawal {
  /// 연차 (1부터 시작)
  final int year;

  /// 해당 연도 나이
  final int age;

  /// 인출 상세 내역
  final List<WithdrawalDetail> withdrawals;

  /// 그 해 국민연금 수령액 (연액, 원) — 국민연금 미입력이거나 개시 전이면 0
  /// (v1.1 소득 크레바스 — 연금계좌 인출과 별개 현금흐름, 세금 계산엔 미반영).
  final int npsAnnualAmount;

  const YearlyWithdrawal({
    required this.year,
    required this.age,
    required this.withdrawals,
    this.npsAnnualAmount = 0,
  });

  /// 해당 연도 총 인출액
  int get totalAmount => withdrawals.fold(0, (sum, w) => sum + w.amount);

  /// 해당 연도 총 세금
  int get totalTax => withdrawals.fold(0, (sum, w) => sum + w.tax);
}

/// 개별 인출 상세
class WithdrawalDetail {
  /// 인출 출처
  final WithdrawalSource source;

  /// 인출 금액 (원)
  final int amount;

  /// 세금 (원)
  final int tax;

  /// 적용 세율 (%)
  final double taxRate;

  const WithdrawalDetail({
    required this.source,
    required this.amount,
    required this.tax,
    required this.taxRate,
  });
}

/// 인출 출처 (자금 풀)
enum WithdrawalSource {
  /// ISA 수익분 (비과세)
  isaProfit('ISA 수익분', '비과세'),

  /// ISA 원금 (비과세)
  isaPrincipal('ISA 원금', '비과세'),

  /// 연금저축 비공제분 (비과세)
  pensionNonDeducted('연금저축 (비공제분)', '비과세'),

  /// 연금저축 공제분 (3.3~5.5%)
  pensionDeducted('연금저축 (공제분)', '연금소득세'),

  /// 운용수익 (시뮬레이션 중 발생한 복리 수익 — 과세재원, 3.3~5.5%)
  earnings('운용수익', '연금소득세'),

  /// IRP 자기납입분 (3.3~5.5%)
  irpSelf('IRP (자기납입분)', '연금소득세'),

  /// IRP 퇴직금분 (퇴직소득세 70%)
  irpRetirement('IRP (퇴직금)', '퇴직소득세 30% 감면');

  final String displayName;
  final String taxType;

  const WithdrawalSource(this.displayName, this.taxType);
}

/// 단일 전략 시뮬레이션 결과 (토너먼트 참가자)
class StrategyOutcome {
  final String strategyId;
  final String strategyName;
  final List<YearlyWithdrawal> schedule;
  final int totalTax;
  final int totalWithdrawn;
  final int finalBalance;
  final int latentTax; // 기말 잔액에 대한 잠재 세금 (근사)

  const StrategyOutcome({
    required this.strategyId,
    required this.strategyName,
    required this.schedule,
    required this.totalTax,
    required this.totalWithdrawn,
    required this.finalBalance,
    required this.latentTax,
  });

  /// 우승 판정 지표: 낸 세금 + 잠재 세금 (낮을수록 우승)
  int get taxBurden => totalTax + latentTax;

  /// 순자산 (참고): 순수령액 + 기말잔액 - 잠재세
  int get netWealth => totalWithdrawn - totalTax + finalBalance - latentTax;
}
