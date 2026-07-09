import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

// 공통 픽스처: A사 1,000주 / per_share 500 / 2025-12 기준일 → 2026-04 지급.
// 나이 60(세율 5.5%), 과세 인출 월 100만, 비과세 월 50만, 이자 0.
final _holdingA = const Holding(corpCode: 'A', corpName: 'A사', shares: 1000);
final _eventA = DividendEvent(
  corpCode: 'A',
  corpName: 'A사',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _input = const RetirementInput(
  pensionSavings: 100000000,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 1000000,
  monthlyOtherWithdrawal: 500000,
  annualInterestIncome: 0,
);

void main() {
  test('4월 현금흐름 = 배당 50만 gross/42.3만 net + 연금 150만 gross/144.5만 net', () {
    final months = CashflowEngine.buildMonths(
      holdings: [_holdingA],
      events: [_eventA],
      input: _input,
      from: DateTime(2026, 1),
      monthCount: 12,
    );
    expect(months.length, 12);
    final april = months.firstWhere((m) => m.month == DateTime(2026, 4));

    expect(april.dividendGross, 500000);
    expect(april.dividendNet, 423000); // 500000 × (1−0.154) = 423,000
    expect(april.pensionGross, 1500000);
    expect(april.pensionNet, 1445000); // 1,000,000×0.945 + 500,000
    expect(april.totalGross, 2000000);
    expect(april.totalNet, 1868000);

    // 배당 없는 달도 생성되고 연금은 그대로.
    final march = months.firstWhere((m) => m.month == DateTime(2026, 3));
    expect(march.dividendGross, 0);
    expect(march.dividendNet, 0);
    expect(march.pensionNet, 1445000);
    expect(march.totalNet, 1445000);

    // 종목별 상세 라인.
    expect(april.lines.length, 1);
    expect(april.lines.first.corpName, 'A사');
    expect(april.lines.first.amountGross, 500000);
    expect(april.lines.first.isConfirmed, true);
  });

  test(
      '게이지: 연 배당 50만+이자0 → financial 0.025 / pension 1200만÷1500만=0.8 / '
      '건보 산입 0 (금융 1000만 이하·사적연금 미산입) → 0 ÷ 2000만 = 0.0', () {
    final g = CashflowEngine.buildGauges(
      holdings: [_holdingA],
      events: [_eventA],
      input: _input,
      year: 2026, // 배당 지급은 2026-04
    );
    expect(g.financialIncome.current, 500000);
    expect(g.financialIncome.threshold, 20000000);
    expect(g.financialIncome.ratio, closeTo(0.025, 1e-9));

    expect(g.pensionLowRate.current, 12000000);
    expect(g.pensionLowRate.threshold, 15000000);
    expect(g.pensionLowRate.ratio, closeTo(0.8, 1e-9));

    // 금융소득 500만 ≤ 1,000만 → 건보 산입 0. 사적연금 인출은 건보 미산입.
    expect(g.healthInsurance.current, 0);
    expect(g.healthInsurance.threshold, 20000000);
    expect(g.healthInsurance.ratio, closeTo(0.0, 1e-9));
  });

  test('금융소득 1,000만 초과 시 건보 게이지에 전액 산입', () {
    // per_share·수량을 키워 배당 gross = 10,000,001원 (1,000만 초과).
    final bigHolding = const Holding(corpCode: 'B', corpName: 'B사', shares: 1);
    final bigEvent = DividendEvent(
      corpCode: 'B',
      corpName: 'B사',
      exDate: null,
      recordDate: DateTime(2025, 12, 31),
      perShare: 10000001,
      isConfirmed: true,
    );
    final g = CashflowEngine.buildGauges(
      holdings: [bigHolding],
      events: [bigEvent],
      input: _input,
      year: 2026,
    );
    expect(g.financialIncome.current, 10000001);
    // 건보 = 금융소득 전액(10,000,001)만. 사적연금 인출은 건보 미산입.
    expect(g.healthInsurance.current, 10000001);
  });

  test('예측 배당(is_confirmed=false)도 월별·게이지에 포함되고 lines에 구분 플래그', () {
    final predicted = DividendEvent(
      corpCode: 'A',
      corpName: 'A사',
      exDate: null,
      recordDate: DateTime(2025, 12, 31),
      perShare: 500,
      isConfirmed: false, // 예측 배당
    );
    final months = CashflowEngine.buildMonths(
      holdings: [_holdingA],
      events: [predicted],
      input: _input,
      from: DateTime(2026, 1),
      monthCount: 12,
    );
    final april = months.firstWhere((m) => m.month == DateTime(2026, 4));
    expect(april.dividendGross, 500000); // 예측도 월별 합산에 포함
    expect(april.lines.first.isConfirmed, false); // 구분 플래그

    final g = CashflowEngine.buildGauges(
      holdings: [_holdingA],
      events: [predicted],
      input: _input,
      year: 2026,
    );
    expect(g.financialIncome.current, 500000); // 예측도 게이지에 포함
  });

  group('사적연금 1,500만 절벽 (전액 16.5% 분리과세)', () {
    test('경계값 월 125만(연 1,500만 정확) → 저율 5.5% 유지', () {
      const input = RetirementInput(
        pensionSavings: 100000000,
        irpBalance: 0,
        isaBalance: 0,
        currentAge: 60,
        monthlyPensionWithdrawal: 1250000, // ×12 = 15,000,000 (한도 정확)
        monthlyOtherWithdrawal: 500000,
        annualInterestIncome: 0,
      );
      final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
      );
      // net = 1,250,000×0.945 + 500,000 = 1,181,250 + 500,000
      expect(months.first.pensionNet, 1181250 + 500000);
      // 모든 월 일관.
      for (final m in months) {
        expect(m.pensionNet, 1681250);
      }
    });

    test('월 200만(연 2,400만 초과) → 전액 16.5% 절벽', () {
      const input = RetirementInput(
        pensionSavings: 100000000,
        irpBalance: 0,
        isaBalance: 0,
        currentAge: 60,
        monthlyPensionWithdrawal: 2000000, // ×12 = 24,000,000 (초과)
        monthlyOtherWithdrawal: 500000,
        annualInterestIncome: 0,
      );
      final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
      );
      // net = 2,000,000×0.835 + 500,000 = 1,670,000 + 500,000
      expect(months.first.pensionNet, 1670000 + 500000);
      for (final m in months) {
        expect(m.pensionNet, 2170000);
      }
    });

    test('기존 월 100만(연 1,200만 ≤ 한도) → 저율 불변', () {
      final months = CashflowEngine.buildMonths(
        holdings: [_holdingA],
        events: [_eventA],
        input: _input,
        from: DateTime(2026, 1),
        monthCount: 12,
      );
      expect(months.first.pensionNet, 1445000); // 1,000,000×0.945 + 500,000
    });
  });

}
