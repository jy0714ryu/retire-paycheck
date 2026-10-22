import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/nps_estimator.dart';

void main() {
  group('normalStartAgeFor — 출생연도별 수급개시연령 (TAX_RULES §7.3)', () {
    test('1952년 이전 → 60세', () {
      expect(NpsEstimator.normalStartAgeFor(1950), 60);
      expect(NpsEstimator.normalStartAgeFor(1952), 60);
    });

    test('1953~1956년 → 61세', () {
      expect(NpsEstimator.normalStartAgeFor(1953), 61);
      expect(NpsEstimator.normalStartAgeFor(1956), 61);
    });

    test('1957~1960년 → 62세', () {
      expect(NpsEstimator.normalStartAgeFor(1957), 62);
      expect(NpsEstimator.normalStartAgeFor(1960), 62);
    });

    test('1961~1964년 → 63세', () {
      expect(NpsEstimator.normalStartAgeFor(1961), 63);
      expect(NpsEstimator.normalStartAgeFor(1964), 63);
    });

    test('1965~1968년 → 64세', () {
      expect(NpsEstimator.normalStartAgeFor(1965), 64);
      expect(NpsEstimator.normalStartAgeFor(1968), 64);
    });

    test('1969년 이후 → 65세', () {
      expect(NpsEstimator.normalStartAgeFor(1969), 65);
      expect(NpsEstimator.normalStartAgeFor(1990), 65);
    });
  });

  group('estimate — 산식 손계산 검증 (TAX_RULES §7.1)', () {
    // 공통 산식: 기본연금액(연액) = 1.290 × (A값 + B값) × [1 + 0.05×(가입월수-240)/12]
    // ★ 산식 결과는 연액(원/년) — 월액 = 연액 ÷ 12
    // A값 = 3,193,511원 (2026년 고시)

    test('월소득 300만·가입 20년(240개월)·정상수령 → 계수 1.0', () {
      // 계수 = 1 + 0.05×(240-240)/12 = 1.0
      // 연액 = 1.290 × (3,193,511 + 3,000,000) × 1.0
      //      = 1.290 × 6,193,511 = 7,989,629.19 (원/년)
      // 월액 = 7,989,629.19 / 12 = 665,802.4325 → round 665,802
      // (상식 대조: 20년 가입 평균 수령액 60~70만원대 현실 통계와 부합)
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 240,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      expect(result.eligibility, NpsEligibility.eligible);
      expect(result.monthlyPensionAmount, 665802);
      expect(result.normalStartAge, 65);
      expect(result.actualStartAge, 65);
      expect(result.adjustmentRate, 0);
      expect(result.appliedOffsetYears, 0);
      expect(result.isEstimate, true);
    });

    test('월소득 500만·가입 30년(360개월)·정상수령 → 20년 초과 가산 계수 1.5', () {
      // 계수 = 1 + 0.05×(360-240)/12 = 1 + 0.5 = 1.5
      // 연액 = 1.290 × (3,193,511 + 5,000,000) × 1.5
      //      = 1.290 × 8,193,511 × 1.5 = 15,854,443.785 (원/년)
      // 월액 = 15,854,443.785 / 12 = 1,321,203.64875 → round 1,321,204
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 5000000,
          enrollmentMonths: 360,
          birthYear: 1958,
          receiptType: NpsReceiptType.normal,
        ),
      );

      expect(result.monthlyPensionAmount, 1321204);
      expect(result.normalStartAge, 62);
    });

    test('월소득 200만·가입 15년(180개월)·정상수령 → 20년 미만 감액 계수 0.75', () {
      // 계수 = 1 + 0.05×(180-240)/12 = 1 - 0.25 = 0.75
      // 연액 = 1.290 × (3,193,511 + 2,000,000) × 0.75
      //      = 1.290 × 5,193,511 × 0.75 = 5,024,721.8925 (원/년)
      // 월액 = 5,024,721.8925 / 12 = 418,726.824... → round 418,727
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 2000000,
          enrollmentMonths: 180,
          birthYear: 1975,
          receiptType: NpsReceiptType.normal,
        ),
      );

      expect(result.eligibility, NpsEligibility.eligible);
      expect(result.monthlyPensionAmount, 418727);
    });

    test('소득대체율 상식 대조: B=A·40년(480개월)·정상 → 월 수령액 ≈ A값의 43%', () {
      // 소득대체율 정의: 40년 가입·평균소득자(B=A)의 월 수령액 = 월소득의 43%
      // 계수(480개월) = 1 + 0.05×(480-240)/12 = 2.0
      // 연액 = 1.290 × 2A × 2.0 = 5.16A → 월액 = 5.16A/12 = 0.43A (정확히 43%)
      // 이 semantic 검증이 연액↔월액 혼동(12배 과대 추정) 회귀를 차단한다.
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: npsAValue, // B = A (평균소득자)
          enrollmentMonths: 480,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      final replacementRatio = result.monthlyPensionAmount / npsAValue;
      expect(replacementRatio, closeTo(0.43, 0.0043)); // 43% ±1%
    });
  });

  group('estimate — 경계 처리', () {
    test('가입 10년 미만(119개월) → 수급 불가', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 119,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      expect(result.eligibility, NpsEligibility.ineligibleShortEnrollment);
      expect(result.isEligible, false);
      expect(result.monthlyPensionAmount, 0);
    });

    test('가입 정확히 10년(120개월) → 수급 가능 (경계값 포함)', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 120,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      // 계수 = 1 + 0.05×(120-240)/12 = 1 - 0.5 = 0.5
      // 연액 = 1.290 × 6,193,511 × 0.5 = 3,994,814.595 (원/년)
      // 월액 = 3,994,814.595 / 12 = 332,901.216... → round 332,901
      expect(result.eligibility, NpsEligibility.eligible);
      expect(result.monthlyPensionAmount, 332901);
    });

    test('월소득이 상한(6,590,000원) 초과 시 상한으로 클램프', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 10000000,
          enrollmentMonths: 240,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      // 연액 = 1.290 × (3,193,511 + 6,590,000) × 1.0 = 12,620,729.19 (원/년)
      // 월액 = 12,620,729.19 / 12 = 1,051,727.4325 → round 1,051,727
      expect(result.clampedMonthlyIncome, npsIncomeCeiling);
      expect(result.monthlyPensionAmount, 1051727);
    });

    test('월소득이 하한(410,000원) 미만 시 하한으로 클램프', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 100000,
          enrollmentMonths: 240,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      // 연액 = 1.290 × (3,193,511 + 410,000) × 1.0 = 4,648,529.19 (원/년)
      // 월액 = 4,648,529.19 / 12 = 387,377.4325 → round 387,377
      expect(result.clampedMonthlyIncome, npsIncomeFloor);
      expect(result.monthlyPensionAmount, 387377);
    });

    test('조기 5년 → 최대 30% 감액, 개시연령 -5세', () {
      // 계수(300개월) = 1 + 0.05×(300-240)/12 = 1.25
      // 연액 = 1.290 × (3,193,511 + 4,000,000) × 1.25
      //      = 1.290 × 7,193,511 × 1.25 = 11,599,536.4875 (원/년)
      // 월액 = 11,599,536.4875 / 12 = 966,628.04... → round 966,628
      // 감액 -30% → round(966,628 × 0.7) = round(676,639.6) = 676,640
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 4000000,
          enrollmentMonths: 300,
          birthYear: 1958, // 정상 62세
          receiptType: NpsReceiptType.early,
          offsetYears: 5,
        ),
      );

      expect(result.appliedOffsetYears, 5);
      expect(result.adjustmentRate, closeTo(-0.30, 1e-9));
      expect(result.actualStartAge, 57); // 62 - 5, 최소 조기연령(57)과 정확히 일치
      expect(result.monthlyPensionAmount, 676640);
    });

    test('조기 입력 7년 → 최대 5년으로 클램프 (최대 30% 감액 초과 불가)', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 4000000,
          enrollmentMonths: 300,
          birthYear: 1958,
          receiptType: NpsReceiptType.early,
          offsetYears: 7,
        ),
      );

      expect(result.appliedOffsetYears, 5);
      expect(result.adjustmentRate, closeTo(-0.30, 1e-9));
    });

    test('연기 5년 → 최대 36% 증액, 개시연령 +5세', () {
      // 계수(252개월) = 1 + 0.05×(252-240)/12 = 1.05
      // 연액 = 1.290 × (3,193,511 + 3,500,000) × 1.05
      //      = 1.290 × 6,693,511 × 1.05 = 9,066,360.6495 (원/년)
      // 월액 = 9,066,360.6495 / 12 = 755,530.054... → round 755,530
      // 증액 +36% → round(755,530 × 1.36) = round(1,027,520.8) = 1,027,521
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3500000,
          enrollmentMonths: 252,
          birthYear: 1963, // 정상 63세
          receiptType: NpsReceiptType.deferred,
          offsetYears: 5,
        ),
      );

      expect(result.appliedOffsetYears, 5);
      expect(result.adjustmentRate, closeTo(0.36, 1e-9));
      expect(result.actualStartAge, 68); // 63 + 5
      expect(result.monthlyPensionAmount, 1027521);
    });

    test('연기 입력 9년 → 최대 5년으로 클램프 (최대 36% 증액 초과 불가)', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3500000,
          enrollmentMonths: 252,
          birthYear: 1963,
          receiptType: NpsReceiptType.deferred,
          offsetYears: 9,
        ),
      );

      expect(result.appliedOffsetYears, 5);
      expect(result.adjustmentRate, closeTo(0.36, 1e-9));
    });

    test('정상수령은 offsetYears 입력값과 무관하게 0으로 처리', () {
      final result = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 240,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
          offsetYears: 5, // 무시되어야 함
        ),
      );

      expect(result.appliedOffsetYears, 0);
      expect(result.adjustmentRate, 0);
      expect(result.actualStartAge, result.normalStartAge);
    });
  });

  group('isEstimate 플래그 (간이 추정 구분용)', () {
    test('수급 가능·불가 케이스 모두 isEstimate = true', () {
      final eligible = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 240,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );
      final ineligible = NpsEstimator.estimate(
        const NpsEstimateInput(
          monthlyIncome: 3000000,
          enrollmentMonths: 60,
          birthYear: 1970,
          receiptType: NpsReceiptType.normal,
        ),
      );

      expect(eligible.isEstimate, true);
      expect(ineligible.isEstimate, true);
    });
  });
}
