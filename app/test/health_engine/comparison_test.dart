import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

void main() {
  late RetirementComparison cmp;

  setUpAll(() async {
    cmp = RetirementComparison(await loadParams2026());
  });

  test('C1 저보수·고재산 → 임의계속 유리 (지역 대비 역전)', () {
    // 보수월액 200만 → 임의계속 월 81,347
    // 재산 8억(공제 후 7억, 36등급 921점) + 금융 1,500만 → 지역 월 322,071
    // 금융 1,500만 → 재산 MID 구간 소득한도(1,000만) 초과 → 피부양자 불가
    final r = cmp.compare(
      const HouseholdInput(
        income: IncomeInput(financial: 15000000),
        propertyTaxBase: 800000000,
        avgMonthlySalary: 2000000,
      ),
    );
    expect(r.voluntaryMonthly, 81347);
    expect(r.regionalMonthly, 322071);
    expect(r.dependentEligible, isFalse);
    expect(r.recommended, ComparisonOption.voluntary);
    expect(r.voluntary36Total, 81347 * 36);
    expect(r.regional36Total, 322071 * 36);
  });

  test('C2 고보수·저재산 → 지역 유리 (역전점 반대편)', () {
    // 보수월액 600만 → 임의계속 월 244,042
    // 금융 2,500만, 재산 0 → 지역 월 169,473
    // 금융 2,500만 → LOW 구간 소득한도(2,000만) 초과 → 피부양자 불가
    final r = cmp.compare(
      const HouseholdInput(
        income: IncomeInput(financial: 25000000),
        propertyTaxBase: 0,
        avgMonthlySalary: 6000000,
      ),
    );
    expect(r.voluntaryMonthly, 244042);
    expect(r.regionalMonthly, 169473);
    expect(r.dependentEligible, isFalse);
    expect(r.recommended, ComparisonOption.regional);
  });

  test('C3 소득·재산 없음 → 피부양자 편입(0원) 최우선', () {
    final r = cmp.compare(
      const HouseholdInput(
        income: IncomeInput(),
        propertyTaxBase: 0,
        avgMonthlySalary: 3000000,
      ),
    );
    expect(r.dependentEligible, isTrue);
    expect(r.dependentMonthly, 0);
    expect(r.dependent36Total, 0);
    expect(r.recommended, ComparisonOption.dependent);
    // 참고: 임의계속·지역 값도 함께 제공.
    expect(r.voluntaryMonthly, 122021);
    expect(r.regionalMonthly, 22809); // 하한 20,160 + 장기요양 2,649
  });
}
