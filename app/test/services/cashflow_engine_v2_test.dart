import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/interest_item.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

// 실제 DividendEvent 시그니처에 맞춘 헬퍼 — 지급월은 explicitPaymentMonth 로 확정
// (합성/수동 이벤트와 동일 경로). record/exDate 는 불필요하므로 null.
DividendEvent ev(String code, String name, int perShare, DateTime pay) =>
    DividendEvent(
        corpCode: code,
        corpName: name,
        exDate: null,
        recordDate: null,
        perShare: perShare,
        isConfirmed: true,
        explicitPaymentMonth: pay,
        source: 'api');

const input0 = RetirementInput(
    pensionSavings: 0,
    irpBalance: 0,
    isaBalance: 0,
    currentAge: 60,
    monthlyPensionWithdrawal: 0,
    monthlyOtherWithdrawal: 0,
    isWithdrawing: false);

void main() {
  final apr = DateTime(2026, 4, 1);
  final events = [
    ev('c1', '일반주', 10000, apr),
    ev('c2', 'ISA주', 10000, apr),
    ev('c3', '연금주', 10000, apr)
  ];
  final holdings = [
    const Holding(corpCode: 'c1', corpName: '일반주', shares: 1),
    const Holding(
        corpCode: 'c2', corpName: 'ISA주', shares: 1, accountId: 'default_isa'),
    const Holding(
        corpCode: 'c3',
        corpName: '연금주',
        shares: 1,
        accountId: 'default_pension'),
  ];

  test('유형 분기 — 일반 15.4%·ISA 0%·연금은 재투자 분리', () {
    final months = CashflowEngine.buildMonths(
        holdings: holdings,
        events: events,
        input: input0,
        from: apr,
        monthCount: 1);
    final m = months.first;
    // 실수령 배당 = 일반(8460) + ISA(10000). 연금주는 미포함.
    expect(m.dividendGross, 20000);
    expect(m.dividendNet, 8460 + 10000);
    expect(m.reinvestGross, 10000);
    expect(m.reinvestLines.single.corpName, '연금주');
    expect(m.lines.length, 2);
    expect(m.lines.firstWhere((l) => l.corpName == '일반주').amountNet, 8460);
    expect(m.lines.firstWhere((l) => l.corpName == 'ISA주').accountType,
        AccountType.isa);
  });

  test('이자소득 — 특정월·월 균등 반영, totalNet 합산', () {
    final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: input0,
        from: DateTime(2026, 1, 1),
        monthCount: 12,
        interestItems: const [
          InterestItem(
              id: 'i1', name: '예금', annualAmount: 1200000, months: [6]),
          InterestItem(id: 'i2', name: '파킹', annualAmount: 120000),
        ]);
    // 6월 = 예금 전액 + 파킹 1/12. net = gross × (1-0.154).
    final june = months[5];
    expect(june.interestGross, 1200000 + 10000);
    expect(june.interestNet, ((1200000 + 10000) * 0.846).round());
    expect(months[0].interestGross, 10000);
    expect(june.totalNet, june.dividendNet + june.pensionNet + june.interestNet);
  });

  test('연금 모드 OFF — 인출 입력이 있어도 연금 0', () {
    final off = RetirementInput(
        pensionSavings: 0,
        irpBalance: 0,
        isaBalance: 0,
        currentAge: 60,
        monthlyPensionWithdrawal: 1000000,
        monthlyOtherWithdrawal: 0,
        isWithdrawing: false);
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: off,
            from: apr,
            monthCount: 1)
        .first;
    expect(m.pensionGross, 0);
    expect(m.pensionNet, 0);
  });

  test('게이지 — 일반계좌 배당+이자만 산입 (금융소득·건보 동일 분기)', () {
    // 일반 1,500만 + ISA 900만 + 이자 600만: 산입은 일반+이자 = 2,100만.
    final bigHoldings = [
      const Holding(corpCode: 'c1', corpName: '일반주', shares: 1500),
      const Holding(
          corpCode: 'c2',
          corpName: 'ISA주',
          shares: 900,
          accountId: 'default_isa'),
    ];
    final g = CashflowEngine.buildGauges(
        holdings: bigHoldings,
        events: events,
        input: input0,
        year: 2026,
        interestItems: const [
          InterestItem(id: 'i', name: '예', annualAmount: 6000000)
        ]);
    expect(g.financialIncome.current, 15000000 + 6000000);
    // 1,000만 초과 → 건보도 전액 산입, ISA 는 여기도 미산입.
    expect(g.healthInsurance.current, 21000000);
  });

  test('연금 모드 OFF — 절벽 게이지 0', () {
    final off = RetirementInput(
        pensionSavings: 0,
        irpBalance: 0,
        isaBalance: 0,
        currentAge: 60,
        monthlyPensionWithdrawal: 2000000,
        monthlyOtherWithdrawal: 0,
        isWithdrawing: false);
    final g = CashflowEngine.buildGauges(
        holdings: const [], events: const [], input: off, year: 2026);
    expect(g.pensionLowRate.current, 0);
  });

  test('ISA 절세효과 = ISA 배당 gross × 15.4%', () {
    final saved = CashflowEngine.isaAnnualSavings(
        holdings: holdings, events: events, accounts: const [], year: 2026);
    expect(saved, (10000 * 0.154).round());
  });
}
