import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/services/plan_mapper.dart';

Account acc(String id, AccountType t,
        {int bal = 0, int monthly = 0, bool? withdrawing}) =>
    Account(
        id: id,
        name: id,
        type: t,
        balance: bal,
        monthlyWithdrawal: monthly,
        isWithdrawing: withdrawing ?? monthly > 0);

void main() {
  final accounts = [
    acc('default_general', AccountType.general, bal: 500000000),
    acc('default_isa', AccountType.isa, bal: 30000000, monthly: 200000),
    acc('default_pension_savings', AccountType.pension, bal: 240000000, monthly: 1000000),
    acc('default_irp', AccountType.pension, bal: 110000000, monthly: 500000),
    acc('user_pension', AccountType.pension, bal: 10000000),
  ];

  test('계좌 묶음 — IRP 는 기본 IRP만, 다른 연금계좌는 연금저축, 일반계좌 제외', () {
    final b = planBalancesFrom(accounts);
    expect(b.pensionSavings, 250000000);
    expect(b.irp, 110000000);
    expect(b.isa, 30000000);
    expect(b.monthlyWithdrawal, 1700000);
    expect(b.total, 390000000);
  });

  test('인출 개시하지 않은 계좌의 월 인출액은 합산하지 않는다 (이번 달 탭과 같은 기준)', () {
    final b = planBalancesFrom([
      acc('default_pension_savings', AccountType.pension, bal: 100000000, monthly: 1000000),
      acc('default_irp', AccountType.pension,
          bal: 50000000, monthly: 500000, withdrawing: false),
    ]);
    expect(b.monthlyWithdrawal, 1000000);
    expect(b.irp, 50000000);
  });

  test('계획 입력 — 기본 인출 목표 = 월 인출 합 × 12, 보수적 가정', () {
    final i = buildPlanInput(
        accounts: accounts, currentAge: 66, assumptions: const PlanAssumptions())!;
    expect(i.targetAnnualWithdrawal, 1700000 * 12);
    expect(i.pensionSavingsDeducted, i.pensionSavings);
    expect(i.irpRetirementPortion, 0);
    expect(i.simulationYears, 25);
    expect(i.hasNps, isFalse);
  });

  test('연간 목표·국민연금 가정 반영', () {
    final i = buildPlanInput(
        accounts: accounts,
        currentAge: 60,
        assumptions: const PlanAssumptions(
            years: 30, returnRate: 0.03, annualTargetOverride: 24000000,
            npsMonthly: 700000, npsStartAge: 65))!;
    expect(i.targetAnnualWithdrawal, 24000000);
    expect(i.simulationYears, 30);
    expect(i.hasNps, isTrue);
  });

  test('계산 불가 — 잔액 0·인출 목표 0·나이 범위 밖이면 null', () {
    expect(buildPlanInput(
        accounts: [acc('default_general', AccountType.general, bal: 1)],
        currentAge: 66, assumptions: const PlanAssumptions()), isNull);
    expect(buildPlanInput(
        accounts: [acc('default_pension_savings', AccountType.pension, bal: 100)],
        currentAge: 66, assumptions: const PlanAssumptions()), isNull);
    expect(buildPlanInput(
        accounts: accounts, currentAge: 10, assumptions: const PlanAssumptions()), isNull);
  });
}
