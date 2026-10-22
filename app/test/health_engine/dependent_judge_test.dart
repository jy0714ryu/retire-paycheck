import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

/// 매트릭스 한 행 — 기대값은 손으로 작성한 진리표 리터럴(엔진 산식 재사용 금지).
typedef _Row = ({
  int income, // 비사업 소득(연금으로 입력)
  int property, // 재산과표
  int biz, // 사업소득
  bool reg, // 사업자 등록 여부
  bool eligible,
  List<String> reasons,
});

void main() {
  late DependentJudge judge;

  setUpAll(() async {
    judge = DependentJudge(await loadParams2026());
  });

  DependentResult run(_Row r) => judge.judge(
    HouseholdInput(
      income: IncomeInput(
        pension: r.income,
        business: r.biz,
        businessRegistered: r.reg,
      ),
      propertyTaxBase: r.property,
    ),
  );

  group('피부양자 3중 요건 경계값 매트릭스 (소득×재산×사업소득)', () {
    // 손으로 작성한 진리표.
    // LOW(≤5.4억) 한도 2,000만 / MID(5.4~9억) 한도 1,000만.
    // 사업소득도 합산소득에 포함(소득 한도에 반영).
    const c1 = 'INCOME_OVER_LIMIT';
    const c1m = 'INCOME_OVER_MID_LIMIT';
    const cb = 'BUSINESS_REGISTERED';

    final matrix = <_Row>[
      // ===== 재산 5.39억 (LOW) =====
      (
        income: 19990000,
        property: 539000000,
        biz: 0,
        reg: false,
        eligible: true,
        reasons: [],
      ),
      (
        income: 19990000,
        property: 539000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 19990000,
        property: 539000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      (
        income: 20000000,
        property: 539000000,
        biz: 0,
        reg: false,
        eligible: true,
        reasons: [],
      ),
      (
        income: 20000000,
        property: 539000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20000000,
        property: 539000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      (
        income: 20010000,
        property: 539000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20010000,
        property: 539000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20010000,
        property: 539000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      // ===== 재산 5.4억 경계 (LOW, 이하 포함) =====
      (
        income: 19990000,
        property: 540000000,
        biz: 0,
        reg: false,
        eligible: true,
        reasons: [],
      ),
      (
        income: 19990000,
        property: 540000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 19990000,
        property: 540000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      (
        income: 20000000,
        property: 540000000,
        biz: 0,
        reg: false,
        eligible: true,
        reasons: [],
      ),
      (
        income: 20000000,
        property: 540000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20000000,
        property: 540000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      (
        income: 20010000,
        property: 540000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20010000,
        property: 540000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1],
      ),
      (
        income: 20010000,
        property: 540000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1, cb],
      ),
      // ===== 재산 8.99억 (MID, 한도 1,000만) — 모든 소득 초과 =====
      (
        income: 19990000,
        property: 899000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 19990000,
        property: 899000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 19990000,
        property: 899000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
      (
        income: 20000000,
        property: 899000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20000000,
        property: 899000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20000000,
        property: 899000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
      (
        income: 20010000,
        property: 899000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20010000,
        property: 899000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20010000,
        property: 899000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
      // ===== 재산 9.0억 경계 (MID, 이하 포함) =====
      (
        income: 19990000,
        property: 900000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 19990000,
        property: 900000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 19990000,
        property: 900000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
      (
        income: 20000000,
        property: 900000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20000000,
        property: 900000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20000000,
        property: 900000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
      (
        income: 20010000,
        property: 900000000,
        biz: 0,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20010000,
        property: 900000000,
        biz: 5000000,
        reg: false,
        eligible: false,
        reasons: [c1m],
      ),
      (
        income: 20010000,
        property: 900000000,
        biz: 5000000,
        reg: true,
        eligible: false,
        reasons: [c1m, cb],
      ),
    ];

    test('매트릭스 36개 조합 전수 검증', () {
      expect(matrix.length, 36);
      for (final row in matrix) {
        final res = run(row);
        final label =
            'income=${row.income} property=${row.property} biz=${row.biz} reg=${row.reg}';
        expect(res.isEligible, row.eligible, reason: '[$label] eligible');
        expect(
          res.failReasons,
          unorderedEquals(row.reasons),
          reason: '[$label] reasons',
        );
      }
    });
  });

  group('재산 중구간(5.4~9억) 소득 1,000만 룰 경계', () {
    _Row mid(int income) => (
      income: income,
      property: 700000000,
      biz: 0,
      reg: false,
      eligible: income <= 10000000,
      reasons: income <= 10000000 ? [] : ['INCOME_OVER_MID_LIMIT'],
    );

    test('999만 → 유지, 여유 10,000원', () {
      final r = run(mid(9990000));
      expect(r.isEligible, isTrue);
      expect(r.band, PropertyBand.mid);
      expect(r.applicableIncomeLimit, 10000000);
      expect(r.incomeMargin, 10000);
      expect(r.propertyMarginToNextBand, 200000000); // 9억 - 7억
    });

    test('1,000만 경계 → 유지 (이하 포함), 여유 0', () {
      final r = run(mid(10000000));
      expect(r.isEligible, isTrue);
      expect(r.incomeMargin, 0);
    });

    test('1,001만 → 탈락', () {
      final r = run(mid(10010000));
      expect(r.isEligible, isFalse);
      expect(r.failReasons, contains('INCOME_OVER_MID_LIMIT'));
      expect(r.incomeMargin, -10000);
    });
  });

  group('재산 9억 초과 → 무조건 탈락', () {
    test('9억 + 1원 → PROPERTY_OVER_LIMIT, 소득 사유 없음', () {
      final r = judge.judge(
        const HouseholdInput(income: IncomeInput(), propertyTaxBase: 900000001),
      );
      expect(r.isEligible, isFalse);
      expect(r.band, PropertyBand.over);
      expect(r.failReasons, ['PROPERTY_OVER_LIMIT']);
      expect(r.applicableIncomeLimit, -1);
      expect(r.incomeMargin, -1);
      expect(r.propertyMarginToNextBand, 0);
    });
  });

  group('여유 금액 역산 (여유 게이지)', () {
    test('LOW 유지 케이스: 소득 여유·재산 여유 역산', () {
      final r = run((
        income: 19990000,
        property: 539000000,
        biz: 0,
        reg: false,
        eligible: true,
        reasons: [],
      ));
      expect(r.band, PropertyBand.low);
      expect(r.applicableIncomeLimit, 20000000);
      expect(r.incomeMargin, 10000); // 2,000만 - 1,999만
      expect(r.propertyMarginToNextBand, 1000000); // 5.4억 - 5.39억
    });
  });

  group('배우자 동반탈락', () {
    test('본인 통과 + 배우자 연금 2,001만 → 동반탈락', () {
      final r = judge.judge(
        const HouseholdInput(
          income: IncomeInput(pension: 10000000), // 본인 소득 요건 통과
          propertyTaxBase: 100000000,
          spouse: PersonInput(
            income: IncomeInput(pension: 20010000), // 배우자 소득 한도 초과
            propertyTaxBase: 100000000,
          ),
        ),
      );
      expect(r.isEligible, isFalse);
      expect(r.spouseJointFail, isTrue);
      expect(r.failReasons, contains('SPOUSE_JOINT_FAIL'));
      // 본인 자체 소득 사유는 없다.
      expect(r.failReasons, isNot(contains('INCOME_OVER_LIMIT')));
    });

    test('본인·배우자 모두 통과 → 동반탈락 없음', () {
      final r = judge.judge(
        const HouseholdInput(
          income: IncomeInput(pension: 10000000),
          propertyTaxBase: 100000000,
          spouse: PersonInput(
            income: IncomeInput(pension: 20000000), // 한도 이하
            propertyTaxBase: 100000000,
          ),
        ),
      );
      expect(r.isEligible, isTrue);
      expect(r.spouseJointFail, isFalse);
    });
  });
}
