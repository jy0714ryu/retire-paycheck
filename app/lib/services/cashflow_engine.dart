import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/retirement_input.dart';
import 'tax_constants.dart';

/// 종목별 배당 상세 라인 (월별 현금흐름 breakdown).
class DividendLine {
  final String corpName;

  /// 세전 배당액 = per_share × 보유 수량.
  final int amountGross;

  /// 확정(공시) 배당 여부. false 이면 예측 배당.
  final bool isConfirmed;

  const DividendLine({
    required this.corpName,
    required this.amountGross,
    required this.isConfirmed,
  });
}

/// 한 달치 현금흐름 (세후 통일 — net 이 대표 숫자).
class MonthlyCashflow {
  final DateTime month;
  final int dividendGross;
  final int dividendNet;
  final int pensionGross;
  final int pensionNet;
  final List<DividendLine> lines;

  const MonthlyCashflow({
    required this.month,
    required this.dividendGross,
    required this.dividendNet,
    required this.pensionGross,
    required this.pensionNet,
    required this.lines,
  });

  int get totalNet => dividendNet + pensionNet;
  int get totalGross => dividendGross + pensionGross;
}

/// 임계치 대비 현재값 게이지.
class GaugeStatus {
  final int current;
  final int threshold;

  const GaugeStatus({required this.current, required this.threshold});

  double get ratio => threshold == 0 ? 0 : current / threshold;
}

/// 연간 3종 게이지 (금융소득종합과세·건보 산입·연금 저율 한도).
class YearlyGauges {
  final GaugeStatus financialIncome;
  final GaugeStatus healthInsurance;
  final GaugeStatus pensionLowRate;

  const YearlyGauges({
    required this.financialIncome,
    required this.healthInsurance,
    required this.pensionLowRate,
  });
}

/// 연간 배당 요약 — 특정 연도에 지급되는 배당의 세전·세후 합계와 확정/예측 건수.
class YearlyDividendSummary {
  final int gross;
  final int net;
  final int confirmedCount;
  final int predictedCount;

  const YearlyDividendSummary({
    required this.gross,
    required this.net,
    required this.confirmedCount,
    required this.predictedCount,
  });

  int get eventCount => confirmedCount + predictedCount;
}

/// 앱의 심장 — 세후 통일 월별 현금흐름 합산 + 연간 게이지 3종.
///
/// 세후(net) 통일 규칙:
/// - 배당 net = gross × (1 − 0.154) 원천징수 후 반올림.
/// - 연금 net = 과세분 × (1 − 나이세율) + 비과세분.
class CashflowEngine {
  const CashflowEngine._();

  /// [from] 을 DateTime(y, m, 1) 로 정규화한 뒤 [monthCount] 개월치 현금흐름 생성.
  /// 배당 이벤트가 없는 달도 (배당 0 · 연금 그대로) 로 생성한다.
  static List<MonthlyCashflow> buildMonths({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required RetirementInput input,
    required DateTime from,
    int monthCount = 12,
  }) {
    final sharesByCorp = _sharesByCorp(holdings);

    final pensionGross =
        input.monthlyPensionWithdrawal + input.monthlyOtherWithdrawal;
    // 사적연금 절벽: 연 인출액(과세분)이 1,500만원을 초과하면 저율(3.3~5.5%)이 아니라
    // 전액 16.5% 분리과세 (분리과세 선택 가정, 종합과세 선택 시 달라질 수 있음
    // — 연금나침반과 동일 규칙). 초과분이 아니라 전액에 16.5%를 적용한다.
    final annualPensionTaxable = input.monthlyPensionWithdrawal * 12;
    final pensionRate = annualPensionTaxable > kPensionLowRateLimit
        ? kPensionCliffRate
        : pensionTaxRate(input.currentAge);
    final pensionNet =
        (input.monthlyPensionWithdrawal * (1 - pensionRate)).round() +
            input.monthlyOtherWithdrawal;

    final start = DateTime(from.year, from.month, 1);
    final result = <MonthlyCashflow>[];

    for (var i = 0; i < monthCount; i++) {
      final month = DateTime(start.year, start.month + i, 1);

      final lines = <DividendLine>[];
      var dividendGross = 0;
      for (final e in events) {
        final shares = sharesByCorp[e.corpCode];
        if (shares == null) continue; // 보유하지 않은 종목 이벤트 무시.
        final pay = e.expectedPaymentMonth;
        if (pay == null || pay != month) continue;
        final amount = e.perShare * shares;
        dividendGross += amount;
        lines.add(DividendLine(
          corpName: e.corpName,
          amountGross: amount,
          isConfirmed: e.isConfirmed,
        ));
      }

      final dividendNet = (dividendGross * (1 - kDividendWithholding)).round();

      result.add(MonthlyCashflow(
        month: month,
        dividendGross: dividendGross,
        dividendNet: dividendNet,
        pensionGross: pensionGross,
        pensionNet: pensionNet,
        lines: lines,
      ));
    }

    return result;
  }

  /// [year] 의 1~12월에 지급되는 이벤트 기준으로 연간 게이지 3종 산출.
  static YearlyGauges buildGauges({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required RetirementInput input,
    required int year,
  }) {
    final sharesByCorp = _sharesByCorp(holdings);

    var annualDividendGross = 0;
    for (final e in events) {
      final shares = sharesByCorp[e.corpCode];
      if (shares == null) continue;
      final pay = e.expectedPaymentMonth;
      if (pay == null || pay.year != year) continue;
      annualDividendGross += e.perShare * shares;
    }

    // 금융소득(세전) = 연 배당 gross 합 + 이자소득.
    final financialIncomeTotal = annualDividendGross + input.annualInterestIncome;

    final annualPensionTaxable = input.monthlyPensionWithdrawal * 12;

    // 건보 산입: 금융소득이 1,000만 초과면 전액, 이하면 0.
    // 사적연금 인출은 건보 소득 미산입 (공적연금만 — 2026-07 현행, 최종리뷰 세법 검증).
    final healthFinancialPart =
        financialIncomeTotal > kHealthInsFinancialFloor ? financialIncomeTotal : 0;
    final healthCurrent = healthFinancialPart;

    return YearlyGauges(
      financialIncome: GaugeStatus(
        current: financialIncomeTotal,
        threshold: kFinancialIncomeThreshold,
      ),
      healthInsurance: GaugeStatus(
        current: healthCurrent,
        threshold: kHealthInsuranceIncomeThreshold,
      ),
      pensionLowRate: GaugeStatus(
        current: annualPensionTaxable,
        threshold: kPensionLowRateLimit,
      ),
    );
  }

  /// [year] 에 지급되는 배당(보유 종목 한정)의 세전·세후 합계와 확정/예측 건수 집계.
  /// 배당이 특정 월에 몰려 달력이 비어 보이는 문제를 보완하는 연간 요약 카드용.
  static YearlyDividendSummary yearlyDividendSummary({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required int year,
  }) {
    final sharesByCorp = _sharesByCorp(holdings);

    var gross = 0;
    var confirmedCount = 0;
    var predictedCount = 0;
    for (final e in events) {
      final shares = sharesByCorp[e.corpCode];
      if (shares == null) continue; // 보유하지 않은 종목 이벤트 무시.
      final pay = e.expectedPaymentMonth;
      if (pay == null || pay.year != year) continue;
      gross += e.perShare * shares;
      if (e.isConfirmed) {
        confirmedCount++;
      } else {
        predictedCount++;
      }
    }

    final net = (gross * (1 - kDividendWithholding)).round();
    return YearlyDividendSummary(
      gross: gross,
      net: net,
      confirmedCount: confirmedCount,
      predictedCount: predictedCount,
    );
  }

  static Map<String, int> _sharesByCorp(List<Holding> holdings) {
    final map = <String, int>{};
    for (final h in holdings) {
      map[h.corpCode] = (map[h.corpCode] ?? 0) + h.shares;
    }
    return map;
  }
}
