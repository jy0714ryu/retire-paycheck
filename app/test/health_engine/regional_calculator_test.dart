import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

void main() {
  late RegionalCalculator calc;

  setUpAll(() async {
    calc = RegionalCalculator(await loadParams2026());
  });

  // 기대값은 params_2026.json 수치로 손계산한 리터럴(산식 재사용 금지).
  // 절사 규칙: 소득분/재산분 각각·합계를 원 단위 절사, 클램프 후 장기요양 절사.

  test('R1 소득(연금 50%)+재산 복합', () {
    // 연금 2,400만 → 반영 1,200만 → 소득월액 100만 × 7.19% = 71,900
    // 재산 2.1억 → 공제 후 1.1억 → 19등급 465점 × 211.5 = 98,347.5 → 98,347
    // 건보료 = floor(71,900 + 98,347.5) = 170,247
    // 장기요양 = floor(170,247 × 0.1314) = 22,370 → 총 192,617
    final r = calc.calculate(
      income: const IncomeInput(pension: 24000000),
      propertyTaxBase: 210000000,
    );
    expect(r.reflectedAnnualIncome, 12000000);
    expect(r.incomePremium, 71900);
    expect(r.propertyPoints, 465);
    expect(r.propertyPremium, 98347);
    expect(r.healthPremium, 170247);
    expect(r.ltcPremium, 22370);
    expect(r.total, 192617);
    expect(r.clampedToMin, isFalse);
    expect(r.clampedToMax, isFalse);
  });

  test('R2 금융소득 전액 반영, 재산 0', () {
    // 금융 2,400만 → 소득월액 200만 × 7.19% = 143,800
    // 재산 0 → 공제 후 음수 → 0점
    // 장기요양 = floor(143,800 × 0.1314) = 18,895 → 총 162,695
    final r = calc.calculate(
      income: const IncomeInput(financial: 24000000),
      propertyTaxBase: 0,
    );
    expect(r.incomePremium, 143800);
    expect(r.propertyPoints, 0);
    expect(r.propertyPremium, 0);
    expect(r.healthPremium, 143800);
    expect(r.ltcPremium, 18895);
    expect(r.total, 162695);
  });

  test('R3 연금 50% 반영 검증 — 동일 금액 연금은 이자의 절반', () {
    final pension = calc.calculate(
      income: const IncomeInput(pension: 24000000),
      propertyTaxBase: 0,
    );
    final financial = calc.calculate(
      income: const IncomeInput(financial: 24000000),
      propertyTaxBase: 0,
    );
    expect(pension.incomePremium, 71900);
    expect(financial.incomePremium, 143800);
    // 연금은 50% 반영이므로 정확히 절반.
    expect(pension.incomePremium * 2, financial.incomePremium);
  });

  test('R4 하한 도달 (소득·재산 0)', () {
    // 건보료 0 → 하한 20,160 클램프 → 장기요양 floor(20,160×0.1314)=2,649 → 22,809
    final r = calc.calculate(
      income: const IncomeInput(),
      propertyTaxBase: 0,
    );
    expect(r.healthPremiumRaw, 0);
    expect(r.healthPremium, 20160);
    expect(r.clampedToMin, isTrue);
    expect(r.ltcPremium, 2649);
    expect(r.total, 22809);
  });

  test('R5 상한 도달 (고액 금융소득)', () {
    // 금융 8억 → 소득월액 66,666,666.67 × 7.19% = 4,793,333 > 상한
    // 상한 4,591,740 클램프 → 장기요양 floor(4,591,740×0.1314)=603,354 → 5,195,094
    final r = calc.calculate(
      income: const IncomeInput(financial: 800000000),
      propertyTaxBase: 0,
    );
    expect(r.healthPremiumRaw, 4793333);
    expect(r.healthPremium, 4591740);
    expect(r.clampedToMax, isTrue);
    expect(r.ltcPremium, 603354);
    expect(r.total, 5195094);
  });

  group('R6 재산공제 경계 (과표 9,999만/1억/1.1억)', () {
    // 금융 2,400만 고정(소득분 143,800)으로 재산분만 관찰.
    test('과표 9,999만 → 공제 후 음수 → 0점', () {
      final r = calc.calculate(
        income: const IncomeInput(financial: 24000000),
        propertyTaxBase: 99990000,
      );
      expect(r.propertyPoints, 0);
      expect(r.propertyPremium, 0);
    });

    test('과표 1억 → 공제 후 0 → 0점', () {
      final r = calc.calculate(
        income: const IncomeInput(financial: 24000000),
        propertyTaxBase: 100000000,
      );
      expect(r.propertyPoints, 0);
      expect(r.propertyPremium, 0);
    });

    test('과표 1.1억 → 공제 후 1,000만 → 3등급 66점', () {
      // 66 × 211.5 = 13,959.0
      final r = calc.calculate(
        income: const IncomeInput(financial: 24000000),
        propertyTaxBase: 110000000,
      );
      expect(r.propertyPoints, 66);
      expect(r.propertyPremium, 13959);
    });
  });
}
