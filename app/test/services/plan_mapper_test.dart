import 'package:retire_paycheck/engine/withdrawal_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/plan_mapper.dart';

Account acc(
  String id,
  AccountType t, {
  int bal = 0,
  int monthly = 0,
  bool? withdrawing,
}) => Account(
  id: id,
  name: id,
  type: t,
  balance: bal,
  monthlyWithdrawal: monthly,
  isWithdrawing: withdrawing ?? monthly > 0,
);

void main() {
  final accounts = [
    acc('default_general', AccountType.general, bal: 500000000),
    acc('default_isa', AccountType.isa, bal: 30000000, monthly: 200000),
    acc(
      'default_pension_savings',
      AccountType.pension,
      bal: 240000000,
      monthly: 1000000,
    ),
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
      acc(
        'default_pension_savings',
        AccountType.pension,
        bal: 100000000,
        monthly: 1000000,
      ),
      acc(
        'default_irp',
        AccountType.pension,
        bal: 50000000,
        monthly: 500000,
        withdrawing: false,
      ),
    ]);
    expect(b.monthlyWithdrawal, 1000000);
    expect(b.irp, 50000000);
  });

  test('계획 입력 — 기본 인출 목표 = 월 인출 합 × 12, 보수적 가정', () {
    final i = buildPlanInput(
      accounts: accounts,
      currentAge: 66,
      assumptions: const PlanAssumptions(),
    )!;
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
        years: 30,
        returnRate: 0.03,
        annualTargetOverride: 24000000,
        npsMonthly: 700000,
        npsStartAge: 65,
      ),
    )!;
    expect(i.targetAnnualWithdrawal, 24000000);
    expect(i.simulationYears, 30);
    expect(i.hasNps, isTrue);
  });

  test('계산 불가 — 잔액 0·인출 목표 0·나이 범위 밖이면 null', () {
    expect(
      buildPlanInput(
        accounts: [acc('default_general', AccountType.general, bal: 1)],
        currentAge: 66,
        assumptions: const PlanAssumptions(),
      ),
      isNull,
    );
    expect(
      buildPlanInput(
        accounts: [
          acc('default_pension_savings', AccountType.pension, bal: 100),
        ],
        currentAge: 66,
        assumptions: const PlanAssumptions(),
      ),
      isNull,
    );
    expect(
      buildPlanInput(
        accounts: accounts,
        currentAge: 10,
        assumptions: const PlanAssumptions(),
      ),
      isNull,
    );
  });

  group('정확도 입력 (v2.1)', () {
    const base = RetirementInput(
      pensionSavings: 0,
      irpBalance: 0,
      isaBalance: 0,
      currentAge: 66,
      monthlyPensionWithdrawal: 0,
      monthlyOtherWithdrawal: 0,
    );

    test('모름(null) → 기존 보수적 가정 그대로 + 모름 목록 3개', () {
      final i = buildPlanInput(
        accounts: accounts,
        currentAge: 66,
        assumptions: const PlanAssumptions(),
        extras: base,
      )!;
      expect(i.pensionSavingsDeducted, i.pensionSavings);
      expect(i.irpRetirementPortion, 0);
      expect(i.isaProfit, 0);
      expect(i.retirementTaxRate, 0.05);
      expect(planUnknowns(accounts, base), hasLength(3));
    });

    test('입력값 반영 — 공제 안 받은 원금·IRP 퇴직금·ISA 수익·실효세율, 잔액으로 상한', () {
      final x = base.withPlanExtras(
        pensionNonDeducted: 30000000,
        irpRetirement: 999000000, // 잔액보다 크면 잔액까지
        retirementTaxRatePct: 7.5,
        isaProfit: 5000000,
      );
      final i = buildPlanInput(
        accounts: accounts,
        currentAge: 66,
        assumptions: const PlanAssumptions(),
        extras: x,
      )!;
      expect(i.pensionSavingsDeducted, 250000000 - 30000000);
      expect(i.irpRetirementPortion, 110000000);
      expect(i.isaProfit, 5000000);
      expect(i.retirementTaxRate, closeTo(0.075, 1e-9));
      expect(planUnknowns(accounts, x), isEmpty);
    });

    test('없음(0)은 모름과 달리 확인된 값 — 모름 목록에서 빠진다', () {
      final x = base.withPlanExtras(
        pensionNonDeducted: 0,
        irpRetirement: 0,
        retirementTaxRatePct: null,
        isaProfit: 0,
      );
      expect(planUnknowns(accounts, x), isEmpty);
    });

    test('국민연금: 계획 탭 입력이 없으면 내 자산 공적연금 사용(65세 개시, 지났으면 지금)', () {
      final x = base.copyWith(publicPensionMonthly: 900000);
      final i60 = buildPlanInput(
        accounts: accounts,
        currentAge: 60,
        assumptions: const PlanAssumptions(),
        extras: x,
      )!;
      expect(i60.npsMonthlyAmount, 900000);
      expect(i60.npsStartAge, 65);
      final i70 = buildPlanInput(
        accounts: accounts,
        currentAge: 70,
        assumptions: const PlanAssumptions(),
        extras: x,
      )!;
      expect(i70.npsStartAge, 70);
      // 계획 탭에 직접 넣은 값이 우선.
      final own = buildPlanInput(
        accounts: accounts,
        currentAge: 60,
        assumptions: const PlanAssumptions(npsMonthly: 500000, npsStartAge: 63),
        extras: x,
      )!;
      expect(own.npsMonthlyAmount, 500000);
      expect(own.npsStartAge, 63);
    });

    test('저장·복원 — 모름(null)은 키 없이, 0 은 0 으로', () {
      final x = base.withPlanExtras(
        pensionNonDeducted: 0,
        irpRetirement: 40000000,
        retirementTaxRatePct: 6,
        isaProfit: null,
      );
      final back = RetirementInput.fromJson(x.toJson());
      expect(back, x);
      expect(x.toJson().containsKey('isa_profit'), isFalse);
    });
  });

  test('v2.3.1 국민연금은 계좌 인출을 줄이지 않는다 — 월 120만 인출이면 해마다 1,440만 인출', () {
    final accounts = [
      kDefaultAccounts[1].copyWith(balance: 30000000),
      kDefaultAccounts[2].copyWith(
        balance: 200000000,
        monthlyWithdrawal: 800000,
        isWithdrawing: true,
      ),
      kDefaultAccounts[3].copyWith(
        balance: 100000000,
        monthlyWithdrawal: 400000,
        isWithdrawing: true,
      ),
    ];
    const extras = RetirementInput(
      pensionSavings: 0,
      irpBalance: 0,
      isaBalance: 0,
      currentAge: 66,
      monthlyPensionWithdrawal: 0,
      monthlyOtherWithdrawal: 0,
      publicPensionMonthly: 900000,
    );
    final input = buildPlanInput(
      accounts: accounts,
      currentAge: 66,
      assumptions: const PlanAssumptions(),
      extras: extras,
    )!;
    final r = WithdrawalOptimizer.optimize(input);
    expect(r.schedule.first.npsAnnualAmount, 10800000);
    expect(r.schedule.first.totalAmount, 14400000);
  });
}
