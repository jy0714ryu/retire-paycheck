import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/pension_input.dart';
import 'package:retire_paycheck/engine/simulation_result.dart';
import 'package:retire_paycheck/engine/pension_simulator.dart';
import 'package:retire_paycheck/engine/withdrawal_strategies.dart';

void main() {
  group('payoutLimitFor — 연금수령한도 10년 룰', () {
    test('1년차: 평가액 1억 → 1,200만원 (1억/(11-1)×1.2)', () {
      final pools = {WithdrawalSource.pensionDeducted: 100000000};
      expect(PensionSimulator.payoutLimitFor(pools, 1), 12000000);
    });

    test('10년차: 평가액 1억 → 1.2억', () {
      final pools = {WithdrawalSource.pensionDeducted: 100000000};
      expect(PensionSimulator.payoutLimitFor(pools, 10), 120000000);
    });

    test('11년차 이후: 무제한', () {
      final pools = {WithdrawalSource.pensionDeducted: 100000000};
      expect(
        PensionSimulator.payoutLimitFor(pools, 11),
        greaterThan(1000000000000),
      );
    });

    test('ISA 풀은 평가액에서 제외', () {
      final pools = {
        WithdrawalSource.pensionDeducted: 100000000,
        WithdrawalSource.isaPrincipal: 999999999999, // 포함되면 한도 폭증
      };
      expect(PensionSimulator.payoutLimitFor(pools, 1), 12000000);
    });
  });

  group('finalizeYearTax — 연말 세금 확정', () {
    DrawSplit split(int within, [int over = 0]) => DrawSplit()
      ..within = within
      ..over = over;

    test('비과세 소스는 세금 0', () {
      final details = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionNonDeducted: split(10000000)},
        58,
        1,
      );
      expect(details.single.tax, 0);
    });

    test('과세재원 1,500만원 이하 → 저율 5.5% (58세)', () {
      final details = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionDeducted: split(15000000)},
        58,
        1,
      );
      expect(details.single.tax, 825000); // 15,000,000 × 5.5%
    });

    test('절벽: 1,500만원+1원 → 전액 16.5%', () {
      final details = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionDeducted: split(15000001)},
        58,
        1,
      );
      expect(details.single.tax, 2475000); // round(15,000,001 × 16.5%)
    });

    test('절벽은 과세재원 합산으로 판정 (공제분 1,000만 + IRP 600만 = 1,600만)', () {
      final details = PensionSimulator.finalizeYearTax(
        {
          WithdrawalSource.pensionDeducted: split(10000000),
          WithdrawalSource.irpSelf: split(6000000),
        },
        58,
        1,
      );
      final totalTax = details.fold<int>(0, (s, d) => s + d.tax);
      expect(totalTax, 2640000); // 16,000,000 × 16.5%
    });

    test('수령한도 초과분(over)은 16.5%, 한도 내는 저율 유지 (절벽 미발동)', () {
      final details = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionDeducted: split(12000000, 3000000)},
        58,
        1,
      );
      final totalTax = details.fold<int>(0, (s, d) => s + d.tax);
      expect(totalTax, 1155000); // 12M×5.5% + 3M×16.5% = 660,000 + 495,000
    });

    test('나이별 저율: 70세 4.4%, 80세 3.3%', () {
      final at70 = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionDeducted: split(10000000)},
        70,
        1,
      );
      final at80 = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.pensionDeducted: split(10000000)},
        80,
        1,
      );
      expect(at70.single.tax, 440000);
      expect(at80.single.tax, 330000);
    });

    test('퇴직금: 1~10년차 3.5%, 11년차부터 3.0%, 한도 초과 5.0%', () {
      final y5 = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.irpRetirement: split(10000000)},
        60,
        5,
      );
      final y11 = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.irpRetirement: split(10000000)},
        66,
        11,
      );
      final over = PensionSimulator.finalizeYearTax(
        {WithdrawalSource.irpRetirement: split(0, 10000000)},
        60,
        5,
      );
      expect(y5.single.tax, 350000);
      expect(y11.single.tax, 300000);
      expect(over.single.tax, 500000);
    });

    test('퇴직금 인출은 절벽 판정에 미포함', () {
      final details = PensionSimulator.finalizeYearTax(
        {
          WithdrawalSource.pensionDeducted: split(14000000),
          WithdrawalSource.irpRetirement: split(20000000),
        },
        58,
        1,
      );
      final pension = details.firstWhere(
        (d) => d.source == WithdrawalSource.pensionDeducted,
      );
      expect(pension.tax, 770000); // 절벽 미발동 — 14M × 5.5%
    });
  });

  group('kStrategies — 전략 정의', () {
    test('4개 전략, id 유일, pension_first 포함', () {
      expect(kStrategies.length, 4);
      final ids = kStrategies.map((s) => s.id).toSet();
      expect(ids.length, 4);
      expect(ids, contains('pension_first'));
      expect(kStrategies.first.id, 'fill_bracket'); // 동률 시 우선
    });

    test('fill_bracket: 과세재원 스텝은 bracket+payout 캡 준수', () {
      final fb = kStrategies.firstWhere((s) => s.id == 'fill_bracket');
      final first = fb.steps.first;
      expect(first.source, WithdrawalSource.pensionDeducted);
      expect(first.useBracketCap, true);
      expect(first.usePayoutCap, true);
    });

    test('defer_taxable: 과세재원은 70세부터 활성', () {
      final dt = kStrategies.firstWhere((s) => s.id == 'defer_taxable');
      final taxableSteps = dt.steps.where(
        (s) => kBracketSources.contains(s.source),
      );
      expect(taxableSteps.every((s) => s.activeFromAge == 70), true);
    });
  });

  group('PensionSimulator.run — 엔진', () {
    test('복리 성장이 earnings 풀로 편입된다 (비공제분 1억, r=5%, 2년)', () {
      const input = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 0, // 전액 비공제 → 비과세
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 10000000,
        simulationYears: 2,
        expectedReturnRate: 0.05,
      );
      final outcome = PensionSimulator.run(input, taxFreeFirst);
      // 1년차: 10M 인출 → 잔액 90M → 성장 4.5M
      // 2년차: 10M 인출 → 비공제 80M, earnings 4.5M → 성장 4M + 225K
      expect(outcome.totalTax, 0); // earnings 미인출 — 전부 비과세 인출
      expect(outcome.totalWithdrawn, 20000000);
      expect(outcome.finalBalance, 88725000); // 80M + 4.5M + 4.225M
    });

    test('fallback: 과세재원만으로 목표 2,400만 충족 (절벽 감수)', () {
      const input = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 100000000, // 전액 과세재원
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        simulationYears: 1,
        expectedReturnRate: 0,
      );
      final outcome = PensionSimulator.run(input, fillBracket);
      final year1 = outcome.schedule.first;
      expect(year1.totalAmount, 24000000); // 목표 충족
      // 1년차 수령한도 = 1억/10×1.2 = 1,200만 → 한도 내 1,200만은
      // 1,500만 이하라 절벽 미발동(5.5%), 한도 초과 1,200만은 16.5%
      expect(year1.totalTax, 660000 + 1980000);
    });

    test('전략 간 비교: example 입력에서 fill_bracket 세금 < pension_first 세금', () {
      final input = PensionInput.example();
      final smart = PensionSimulator.run(input, fillBracket);
      final naive = PensionSimulator.run(input, pensionFirst);
      expect(smart.totalTax, lessThan(naive.totalTax));
    });

    test('defer_taxable: 70세 전엔 과세재원 인출 없음 (재원 충분 시)', () {
      const input = PensionInput(
        pensionSavings: 200000000,
        pensionSavingsDeducted: 100000000, // 비공제 1억 + 공제 1억
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 12000000,
        simulationYears: 5,
        expectedReturnRate: 0,
      );
      final outcome = PensionSimulator.run(input, deferTaxable);
      for (final year in outcome.schedule) {
        final taxableDrawn = year.withdrawals
            .where((d) => kBracketSources.contains(d.source))
            .fold<int>(0, (s, d) => s + d.amount);
        expect(taxableDrawn, 0, reason: '${year.age}세에 과세재원 인출됨');
      }
    });
  });
}
