import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

void main() {
  late VoluntaryCalculator calc;

  setUpAll(() async {
    calc = VoluntaryCalculator(await loadParams2026());
  });

  test('V1 보수월액 300만 → 본인부담 + 장기요양', () {
    // 300만 × 7.19% × 50% = 107,850
    // 장기요양 = floor(107,850 × 0.1314) = 14,171 → 월 122,021
    final r = calc.calculate(avgMonthlySalary: 3000000);
    expect(r.healthPremium, 107850);
    expect(r.ltcPremium, 14171);
    expect(r.monthlyTotal, 122021);
    expect(r.months, 36);
    expect(r.totalOverPeriod, 4392756); // 122,021 × 36
  });

  test('V2 보수월액 500만', () {
    // 500만 × 7.19% × 50% = 179,750
    // 장기요양 = floor(179,750 × 0.1314) = 23,619 → 월 203,369
    final r = calc.calculate(avgMonthlySalary: 5000000);
    expect(r.healthPremium, 179750);
    expect(r.ltcPremium, 23619);
    expect(r.monthlyTotal, 203369);
  });

  test('36개월 타임라인 누계', () {
    final r = calc.calculate(avgMonthlySalary: 3000000);
    expect(r.timeline.length, 36);
    expect(r.timeline.first.month, 1);
    expect(r.timeline.first.cumulative, 122021);
    expect(r.timeline.last.month, 36);
    expect(r.timeline.last.cumulative, 4392756);
    // 누계가 단조 증가.
    for (var i = 1; i < r.timeline.length; i++) {
      expect(r.timeline[i].cumulative,
          r.timeline[i - 1].cumulative + r.monthlyTotal);
    }
  });
}
