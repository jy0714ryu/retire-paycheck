import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

void main() {
  late HealthParams params;

  setUpAll(() async {
    params = await loadParams2026();
  });

  group('params 로딩', () {
    test('스칼라 값이 JSON 과 일치한다', () {
      expect(params.year, 2026);
      expect(params.version, '2026.1');
      expect(params.employeeRate, 0.0719);
      expect(params.regionalIncomeRate, 0.0719);
      expect(params.ltcRateOfHealth, 0.1314);
      expect(params.propertyDeduction, 100000000);
      expect(params.propertyPointPrice, 211.5);
      expect(params.minPremium, 20160);
      expect(params.maxPremium, 4591740);
      expect(params.propertyGradeTable.length, 60);
    });

    test('반영률·피부양자 임계값이 JSON 과 일치한다', () {
      expect(params.incomeReflect.pension, 0.5);
      expect(params.incomeReflect.labor, 0.5);
      expect(params.incomeReflect.financial, 1.0);
      expect(params.dependent.incomeLimit, 20000000);
      expect(params.dependent.propertyLimitLow, 540000000);
      expect(params.dependent.propertyLimitHigh, 900000000);
      expect(params.dependent.midIncomeLimit, 10000000);
      expect(params.dependent.bizUnregisteredLimit, 5000000);
    });

    test('장기요양 소득환산율 ≈ 직장요율 × 건보료대비율', () {
      // ltc_rate_of_income(0.009448) ≈ employee_rate × ltc_rate_of_health.
      expect(
        params.employeeRate * params.ltcRateOfHealth,
        closeTo(params.ltcRateOfIncome, 1e-6),
      );
    });
  });

  group('재산 등급표 경계값(±1원)', () {
    test('공제 후 0 이하 → 부과점수 없음(null)', () {
      expect(params.gradeForAmount(0), isNull);
      expect(params.gradeForAmount(-1), isNull);
    });

    test('1등급 경계 (450만원)', () {
      expect(params.gradeForAmount(1)!.grade, 1);
      expect(params.gradeForAmount(1)!.points, 22);
      expect(params.gradeForAmount(4500000)!.grade, 1); // 이하 포함
      expect(params.gradeForAmount(4500000)!.points, 22);
      expect(params.gradeForAmount(4500001)!.grade, 2); // 초과 → 2등급
      expect(params.gradeForAmount(4500001)!.points, 44);
    });

    test('10등급 경계 (4,500만원)', () {
      expect(params.gradeForAmount(45000000)!.grade, 10);
      expect(params.gradeForAmount(45000000)!.points, 244);
      expect(params.gradeForAmount(45000001)!.grade, 11);
      expect(params.gradeForAmount(45000001)!.points, 268);
    });

    test('30등급 경계 (3.88억)', () {
      expect(params.gradeForAmount(388000000)!.grade, 30);
      expect(params.gradeForAmount(388000000)!.points, 731);
      expect(params.gradeForAmount(388000001)!.grade, 31);
      expect(params.gradeForAmount(388000001)!.points, 757);
    });

    test('60등급 경계 (77.8124억)', () {
      // 59등급 상한 = 7,781,240,000 (이하) → 59등급.
      expect(params.gradeForAmount(7781240000)!.grade, 59);
      expect(params.gradeForAmount(7781240000)!.points, 2271);
      // 초과 → 60등급(상한 없음).
      expect(params.gradeForAmount(7781240001)!.grade, 60);
      expect(params.gradeForAmount(7781240001)!.points, 2341);
      expect(params.gradeForAmount(99999999999)!.grade, 60);
    });
  });
}
