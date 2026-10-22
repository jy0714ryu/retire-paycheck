import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/health_bridge.dart';

const _base = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 66,
  monthlyPensionWithdrawal: 0,
  monthlyOtherWithdrawal: 0,
);

void main() {
  test('공적연금 월액 ×12, 금융소득 1,000만 이하는 0·초과는 전액', () {
    final x = _base.copyWith(publicPensionMonthly: 800000);
    expect(
      householdFrom(x, financialIncomeAnnual: 9000000).income.pension,
      9600000,
    );
    expect(
      householdFrom(x, financialIncomeAnnual: 9000000).income.financial,
      0,
    );
    expect(
      householdFrom(x, financialIncomeAnnual: 12000000).income.financial,
      12000000,
    );
  });

  test('그 밖의 소득(사업·임대)은 사업소득 — 등록 여부는 판정 규칙에 넘김', () {
    for (final reg in [true, false]) {
      final h = householdFrom(
        _base.copyWith(otherAnnualIncome: 3000000, businessRegistered: reg),
        financialIncomeAnnual: 0,
      );
      expect(h.income.business, 3000000);
      expect(h.income.other, 0);
      expect(h.income.businessRegistered, reg);
    }
  });

  test('가입 형태·재산·퇴직 전 월급 전달', () {
    final h = householdFrom(
      _base.copyWith(
        healthInsType: HealthInsType.regional,
        propertyTaxBase: 500000000,
        lastMonthlySalary: 4000000,
      ),
      financialIncomeAnnual: 0,
    );
    expect(h.currentStatus, HealthStatus.regional);
    expect(h.propertyTaxBase, 500000000);
    expect(h.avgMonthlySalary, 4000000);
  });

  test('저장·복원 — 새 필드 없는 옛 JSON 은 0·false', () {
    final legacy = _base.toJson()
      ..remove('property_tax_base')
      ..remove('business_registered')
      ..remove('last_monthly_salary');
    final r = RetirementInput.fromJson(legacy);
    expect(r.propertyTaxBase, 0);
    expect(r.businessRegistered, isFalse);
    expect(r.lastMonthlySalary, 0);
    final full = _base.copyWith(
      propertyTaxBase: 1,
      businessRegistered: true,
      lastMonthlySalary: 2,
    );
    expect(RetirementInput.fromJson(full.toJson()), full);
  });
}
