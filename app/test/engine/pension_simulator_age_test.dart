import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/pension_input.dart';
import 'package:retire_paycheck/engine/simulation_result.dart';
import 'package:retire_paycheck/engine/pension_simulator.dart';
import 'package:retire_paycheck/engine/result_narrative.dart';
import 'package:retire_paycheck/engine/withdrawal_strategies.dart';

/// v1.1.1 감사 I1 — 55세 미만 인출 클램프 (55세 전 = 적립기, 인출 0).
///
/// 세법상 55세 미만은 연금수령이 불가(연금외수령 16.5%)한데, 기존 엔진은
/// currentAge부터 즉시 5.5% 연금수령으로 인출을 시작하는 버그가 있었다.
void main() {
  const input45 = PensionInput(
    pensionSavings: 100000000,
    pensionSavingsDeducted: 0, // 전액 비공제 → 세금 0으로 금액 검증 단순화
    irpBalance: 0,
    irpRetirementPortion: 0,
    isaMaturity: 0,
    currentAge: 45,
    targetAnnualWithdrawal: 12000000,
    simulationYears: 15, // 45~59세: 적립 10년 + 인출 5년
    expectedReturnRate: 0,
  );

  group('55세 미만 적립기 — 인출·세금 0', () {
    test('age<55 행은 인출 0, 55세부터 목표 인출 시작', () {
      final outcome = PensionSimulator.run(input45, taxFreeFirst);

      for (final row in outcome.schedule) {
        if (row.age < kPensionWithdrawalMinAge) {
          expect(row.totalAmount, 0, reason: '${row.age}세(적립기)에 인출 발생');
          expect(row.totalTax, 0);
        }
      }
      final firstActive = outcome.schedule
          .firstWhere((r) => r.age >= kPensionWithdrawalMinAge);
      expect(firstActive.age, 55);
      expect(firstActive.totalAmount, 12000000);
    });

    test('적립기에도 복리 성장은 계속된다', () {
      final grown = PensionSimulator.run(
        input45.copyWith(expectedReturnRate: 0.04, simulationYears: 5),
        taxFreeFirst,
      );
      // 45~49세: 인출 0 + 4% 복리 → 기말 잔액 > 원금
      expect(grown.totalWithdrawn, 0);
      expect(grown.finalBalance, greaterThan(100000000));
    });
  });

  group('연금수령연차 55세 기산', () {
    test('45세 시작이어도 55세 첫 인출 해의 퇴직세 감면은 1연차(30% 감면=3.5%)', () {
      // year=11(55세)에 도달 — 시뮬레이션 연차를 그대로 쓰면 11년차(40% 감면=3.0%)로
      // 과소과세된다. 수령연차 1년차 기준 3.5%가 정답.
      const input = PensionInput(
        pensionSavings: 0,
        pensionSavingsDeducted: 0,
        irpBalance: 100000000,
        irpRetirementPortion: 100000000, // 전액 퇴직금 재원
        isaMaturity: 0,
        currentAge: 45,
        targetAnnualWithdrawal: 10000000,
        simulationYears: 11,
        expectedReturnRate: 0,
      );
      final outcome = PensionSimulator.run(input, pensionFirst);
      final at55 = outcome.schedule.firstWhere((r) => r.age == 55);
      final retDetail = at55.withdrawals
          .firstWhere((d) => d.source == WithdrawalSource.irpRetirement);
      expect(retDetail.taxRate, closeTo(3.5, 0.001));
    });

    test('55세 첫 인출 해의 수령한도는 1연차 기준(평가액×1.2/10)으로 제한된다', () {
      // 평가액 1억 → 1연차 한도 1,200만. 목표 2,000만이면 800만은 한도초과 16.5%.
      const input = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 100000000, // 전액 과세재원
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 50,
        targetAnnualWithdrawal: 20000000,
        simulationYears: 6, // 50~55세
        expectedReturnRate: 0,
      );
      final outcome = PensionSimulator.run(input, pensionFirst);
      final at55 = outcome.schedule.firstWhere((r) => r.age == 55);
      final overSplit = at55.withdrawals
          .where((d) => d.taxRate == 16.5)
          .fold<int>(0, (s, d) => s + d.amount);
      expect(overSplit, 8000000, reason: '1연차 한도 1,200만 초과분 800만이어야 함');
    });
  });

  group('내러티브 — 적립기 행은 고갈 판정 제외', () {
    test('45세 시작: 적립 10년은 fundedYears·고갈 판정에서 제외', () {
      final outcome = PensionSimulator.run(input45, taxFreeFirst);
      final result = SimulationResult(
        schedule: outcome.schedule,
        totalTaxOptimal: 0,
        totalTaxBaseline: 0,
        optimalSequence: const [],
      );
      final narrative = computeWithdrawalNarrative(result, input45);
      // 잔액 1억, 55세부터 연 1,200만 × 5년(55~59세) 전부 충족
      expect(narrative.depleted, false);
      expect(narrative.fundedYears, 5);
    });
  });

  group('하위호환 — 55세 이상 시작은 기존 동작 그대로', () {
    test('58세 시작: 1년차부터 인출, 수령연차=시뮬레이션 연차', () {
      final outcome = PensionSimulator.run(
        input45.copyWith(currentAge: 58, simulationYears: 5),
        taxFreeFirst,
      );
      expect(outcome.schedule.first.totalAmount, 12000000);
      expect(outcome.schedule.first.age, 58);
    });
  });
}
