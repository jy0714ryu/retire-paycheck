import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import 'tax_constants.dart';

/// 종목별 배당 상세 라인 (월별 현금흐름 breakdown).
class DividendLine {
  final String corpName;

  /// 세전 배당액 = per_share × 보유 수량.
  final int amountGross;

  /// 세후 배당액 — 일반계좌는 원천징수(15.4%) 후, ISA·연금계좌는 gross 그대로
  /// (스펙 §2: ISA 비과세·연금 과세이연). 계좌 유형별로 이미 계산된 값이다.
  final int amountNet;

  /// 확정(공시) 배당 여부. false 이면 예측 배당.
  final bool isConfirmed;

  /// 이벤트 출처 — 'api' / 'manual'(직접 입력). 라인 상세 "(직접 입력)" 표기용.
  final String source;

  /// 소속 계좌 id — [Holding.accountId] 그대로 전달 (라인 상세·필터용).
  final String accountId;

  /// 계좌 유형 — 세금 분기 결과(general/isa/pension). UI 배지·재투자 구분용.
  final AccountType accountType;

  const DividendLine({
    required this.corpName,
    required this.amountGross,
    required this.amountNet,
    required this.isConfirmed,
    this.source = 'api',
    this.accountId = 'default_general',
    this.accountType = AccountType.general,
  });
}

/// 한 달치 현금흐름 (세후 통일 — net 이 대표 숫자).
class MonthlyCashflow {
  final DateTime month;
  final int dividendGross;
  final int dividendNet;
  final int pensionGross;
  final int pensionNet;

  /// 이자소득 세전 합 — 해당 월에 배정된 이자 항목 합계.
  final int interestGross;

  /// 이자소득 세후 합 = interestGross × (1 − 0.154).
  final int interestNet;

  /// 연금계좌 배당(재투자·과세이연) 세전 합 — 실수령 아님(totalNet 미포함).
  final int reinvestGross;

  /// 실수령 배당 라인(일반·ISA). 연금계좌 배당은 [reinvestLines] 로 분리.
  final List<DividendLine> lines;

  /// 연금계좌 배당 라인 — 과세이연 재투자분. 달력엔 "재투자"로 별도 표기.
  final List<DividendLine> reinvestLines;

  const MonthlyCashflow({
    required this.month,
    required this.dividendGross,
    required this.dividendNet,
    required this.pensionGross,
    required this.pensionNet,
    required this.lines,
    this.interestGross = 0,
    this.interestNet = 0,
    this.reinvestGross = 0,
    this.reinvestLines = const [],
  });

  /// 실수령 합 — 배당(일반+ISA) + 연금 + 이자. 재투자(reinvest)는 미포함(스펙 §2).
  int get totalNet => dividendNet + pensionNet + interestNet;
  int get totalGross => dividendGross + pensionGross + interestGross;
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
/// - 배당 net = gross × (1 − 0.154) 원천징수 후 반올림 (일반계좌만).
///   ISA·연금계좌는 원천징수 없음 (스펙 §2: ISA 비과세·연금 과세이연).
/// - 연금 인출 net = 과세분 × (1 − 나이세율) + 비과세분 (운용기엔 0).
/// - 이자 net = gross × (1 − 0.154).
class CashflowEngine {
  const CashflowEngine._();

  /// [from] 을 DateTime(y, m, 1) 로 정규화한 뒤 [monthCount] 개월치 현금흐름 생성.
  /// 배당 이벤트가 없는 달도 (배당 0 · 연금 그대로) 로 생성한다.
  ///
  /// 계좌 유형별 세금 분기 — 같은 corpCode 가 여러 계좌에 존재할 수 있으므로
  /// holdings 를 직접 순회한다(이벤트→종목 인덱스로 O(n+m) 유지).
  static List<MonthlyCashflow> buildMonths({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required RetirementInput input,
    required DateTime from,
    int monthCount = 12,
    List<Account> accounts = const [],
    List<InterestItem> interestItems = const [],
  }) {
    final eventsByCorp = _indexEvents(events);

    // 연금 인출 모드(운용기 OFF): 인출 입력이 있어도 0 취급 (스펙 §1.3).
    // 인출 소스는 flat 필드가 아니라 계좌 합산(v3) — 과세=pension 계좌, 비과세=isa 계좌.
    final withdrawing = input.isWithdrawing;
    final monthlyTaxable =
        withdrawing ? _monthlyWithdrawalByType(accounts, AccountType.pension) : 0;
    final monthlyTaxFree =
        withdrawing ? _monthlyWithdrawalByType(accounts, AccountType.isa) : 0;
    final pensionGross = monthlyTaxable + monthlyTaxFree;
    // 사적연금 절벽: 연 인출액(과세분)이 1,500만원을 초과하면 저율(3.3~5.5%)이 아니라
    // 전액 16.5% 분리과세 (분리과세 선택 가정). 초과분이 아니라 전액에 적용.
    final annualPensionTaxable = monthlyTaxable * 12;
    final pensionRate = annualPensionTaxable > kPensionLowRateLimit
        ? kPensionCliffRate
        : pensionTaxRate(input.currentAge);
    final pensionNet =
        (monthlyTaxable * (1 - pensionRate)).round() + monthlyTaxFree;

    final start = DateTime(from.year, from.month, 1);
    final result = <MonthlyCashflow>[];

    for (var i = 0; i < monthCount; i++) {
      final month = DateTime(start.year, start.month + i, 1);

      final lines = <DividendLine>[];
      final reinvestLines = <DividendLine>[];
      var dividendGross = 0;
      var dividendNet = 0;
      var reinvestGross = 0;

      for (final h in holdings) {
        final evs = eventsByCorp[h.corpCode];
        if (evs == null) continue; // 이 종목엔 배당 이벤트가 없음.
        final type = _typeOf(h, accounts);
        for (final e in evs) {
          final pay = e.expectedPaymentMonth;
          if (pay == null || pay != month) continue;
          final amount = e.perShare * h.shares;
          final net = type == AccountType.general
              ? (amount * (1 - kDividendWithholding)).round()
              : amount; // ISA·연금 세금 0 (비과세·과세이연 — 스펙 §2).
          final line = DividendLine(
            corpName: e.corpName,
            amountGross: amount,
            amountNet: net,
            isConfirmed: e.isConfirmed,
            source: e.source,
            accountId: h.accountId,
            accountType: type,
          );
          if (type == AccountType.pension) {
            reinvestGross += amount;
            reinvestLines.add(line);
          } else {
            dividendGross += amount;
            dividendNet += net;
            lines.add(line);
          }
        }
      }

      // 이자소득: 지정월 항목은 지정월에 균등 분배, 빈 months 는 월 균등 12분할.
      var interestGross = 0;
      for (final item in interestItems) {
        if (item.months.isEmpty) {
          interestGross += (item.annualAmount / 12).round();
        } else if (item.months.contains(month.month)) {
          interestGross += (item.annualAmount / item.months.length).round();
        }
      }
      final interestNet = (interestGross * (1 - kDividendWithholding)).round();

      result.add(MonthlyCashflow(
        month: month,
        dividendGross: dividendGross,
        dividendNet: dividendNet,
        pensionGross: pensionGross,
        pensionNet: pensionNet,
        interestGross: interestGross,
        interestNet: interestNet,
        reinvestGross: reinvestGross,
        lines: lines,
        reinvestLines: reinvestLines,
      ));
    }

    return result;
  }

  /// [year] 의 1~12월에 지급되는 이벤트 기준으로 연간 게이지 3종 산출.
  ///
  /// 산입 규칙(스펙 §2) — **일반계좌 배당 + 이자소득만** 금융소득에 산입한다.
  /// ISA·연금계좌 배당은 금융소득·건보 게이지 양쪽 모두 미산입(분기 지점 단일화).
  static YearlyGauges buildGauges({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required RetirementInput input,
    required int year,
    List<Account> accounts = const [],
    List<InterestItem> interestItems = const [],
  }) {
    final eventsByCorp = _indexEvents(events);

    // 일반계좌 배당만 산입 (분기 지점 단일화 — 금융소득·건보 공용).
    var generalDividendGross = 0;
    for (final h in holdings) {
      final evs = eventsByCorp[h.corpCode];
      if (evs == null) continue;
      if (_typeOf(h, accounts) != AccountType.general) continue;
      for (final e in evs) {
        final pay = e.expectedPaymentMonth;
        if (pay == null || pay.year != year) continue;
        generalDividendGross += e.perShare * h.shares;
      }
    }

    // 이자소득 — interest_items 로 이관. input.annualInterestIncome 은 더 이상
    // 사용하지 않는다(구 필드는 저장소 보존용).
    final interestAnnual =
        interestItems.fold<int>(0, (s, i) => s + i.annualAmount);

    // 금융소득(세전) = 일반계좌 배당 gross 합 + 이자소득.
    final financialIncomeTotal = generalDividendGross + interestAnnual;

    // 연금 인출 모드 OFF 면 과세대상 인출 0 (절벽 게이지 0).
    // 과세 인출은 flat 필드가 아니라 pension 계좌 monthlyWithdrawal 합산(v3).
    final annualPensionTaxable = input.isWithdrawing
        ? _monthlyWithdrawalByType(accounts, AccountType.pension) * 12
        : 0;

    // 건보 산입: 금융소득이 1,000만 초과면 전액, 이하면 0.
    // 사적연금 인출은 건보 소득 미산입 (공적연금만 — 2026-07 현행).
    final healthCurrent =
        financialIncomeTotal > kHealthInsFinancialFloor ? financialIncomeTotal : 0;

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
  /// 실수령 대상(일반+ISA)만 집계 — 연금계좌 배당(재투자·과세이연)은 제외한다.
  /// net 은 라인별 세후(일반 원천징수·ISA 그대로)의 합.
  static YearlyDividendSummary yearlyDividendSummary({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required int year,
    List<Account> accounts = const [],
  }) {
    final eventsByCorp = _indexEvents(events);

    var gross = 0;
    var net = 0;
    var confirmedCount = 0;
    var predictedCount = 0;
    for (final h in holdings) {
      final evs = eventsByCorp[h.corpCode];
      if (evs == null) continue; // 보유하지 않은 종목 이벤트 무시.
      final type = _typeOf(h, accounts);
      if (type == AccountType.pension) continue; // 재투자 — 실수령 아님.
      for (final e in evs) {
        final pay = e.expectedPaymentMonth;
        if (pay == null || pay.year != year) continue;
        final amount = e.perShare * h.shares;
        gross += amount;
        net += type == AccountType.general
            ? (amount * (1 - kDividendWithholding)).round()
            : amount;
        if (e.isConfirmed) {
          confirmedCount++;
        } else {
          predictedCount++;
        }
      }
    }

    return YearlyDividendSummary(
      gross: gross,
      net: net,
      confirmedCount: confirmedCount,
      predictedCount: predictedCount,
    );
  }

  /// ISA 절세효과 — ISA 계좌 배당 gross × 15.4% (일반계좌였다면 냈을 세금).
  /// 캡션 "(비과세 한도 내 기준)" 는 UI 책임 (스펙 §2).
  static int isaAnnualSavings({
    required List<Holding> holdings,
    required List<DividendEvent> events,
    required List<Account> accounts,
    required int year,
  }) {
    final eventsByCorp = _indexEvents(events);

    var isaGross = 0;
    for (final h in holdings) {
      final evs = eventsByCorp[h.corpCode];
      if (evs == null) continue;
      if (_typeOf(h, accounts) != AccountType.isa) continue;
      for (final e in evs) {
        final pay = e.expectedPaymentMonth;
        if (pay == null || pay.year != year) continue;
        isaGross += e.perShare * h.shares;
      }
    }
    return (isaGross * kDividendWithholding).round();
  }

  /// 지정 유형([type]) 계좌들의 월 인출액([Account.monthlyWithdrawal]) 합산(v3).
  /// 인출 소스가 RetirementInput flat 필드에서 계좌 합산으로 이관됨 —
  /// 과세 연금 인출 = pension 계좌 합, 비과세 인출 = isa 계좌 합.
  static int _monthlyWithdrawalByType(List<Account> accounts, AccountType type) {
    var sum = 0;
    for (final a in accounts) {
      if (a.type == type) sum += a.monthlyWithdrawal;
    }
    return sum;
  }

  /// 종목의 계좌 유형 해석 — 삭제된 계좌 참조는 일반계좌로 폴백(안전망).
  static AccountType _typeOf(Holding h, List<Account> accounts) =>
      (resolveAccount(h.accountId, accounts) ?? kDefaultAccounts.first).type;

  /// 이벤트를 corpCode → 이벤트 목록으로 인덱싱(O(m)). holdings 순회와 결합해
  /// 배당 매칭을 O(n+m) 로 유지한다.
  static Map<String, List<DividendEvent>> _indexEvents(
      List<DividendEvent> events) {
    final map = <String, List<DividendEvent>>{};
    for (final e in events) {
      (map[e.corpCode] ??= <DividendEvent>[]).add(e);
    }
    return map;
  }
}
