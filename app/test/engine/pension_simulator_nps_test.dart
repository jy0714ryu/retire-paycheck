import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/pension_input.dart';
import 'package:retire_paycheck/engine/pension_simulator.dart';
import 'package:retire_paycheck/engine/withdrawal_strategies.dart';

/// v1.1 Task 3 — 국민연금 소득 크레바스 엔진 통합 테스트.
///
/// 기존 25(→45, Task 2 이후) 테스트는 이 파일에서 절대 손대지 않는다 —
/// 무수정 통과가 하위호환의 증거다 (exec-plan §① "기존 25개 테스트 회귀 0").
void main() {
  group('PensionInput.hasNps — 하위호환 게이트', () {
    test('둘 다 null이면 false', () {
      const input = PensionInput(
        pensionSavings: 0,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
      );
      expect(input.hasNps, false);
    });

    test('하나만 있으면 false (짝 없는 입력은 미반영 취급)', () {
      const withOnlyAmount = PensionInput(
        pensionSavings: 0,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        npsMonthlyAmount: 600000,
      );
      const withOnlyAge = PensionInput(
        pensionSavings: 0,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        npsStartAge: 65,
      );
      expect(withOnlyAmount.hasNps, false);
      expect(withOnlyAge.hasNps, false);
    });

    test('둘 다 있으면 true', () {
      const input = PensionInput(
        pensionSavings: 0,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        npsMonthlyAmount: 600000,
        npsStartAge: 65,
      );
      expect(input.hasNps, true);
    });
  });

  group('PensionSimulator.run — 국민연금 하위호환 (미입력 시 기존 동작과 동일)', () {
    // 동일한 자산·목표로 국민연금 필드를 명시적으로 안 채운 입력과
    // example()에 npsMonthlyAmount/npsStartAge를 안 넣은 입력이 완전히
    // 동일한 결과를 내는지 — 새 필드 추가가 기존 계산 경로에 어떤
    // 부작용도 만들지 않았음을 직접 증명한다.
    test('example() 입력 — 4개 전략 전부 기존과 동일 스케줄', () {
      final input = PensionInput.example();
      expect(input.hasNps, false);

      for (final strategy in kStrategies) {
        final outcome = PensionSimulator.run(input, strategy);
        for (final year in outcome.schedule) {
          expect(
            year.npsAnnualAmount,
            0,
            reason: '${strategy.id} ${year.age}세: 미입력인데 국민연금 차감됨',
          );
        }
      }
    });

    test('국민연금 필드 null 명시 vs 생략 — 완전히 동일한 결과', () {
      const withoutFields = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 80000000,
        irpBalance: 50000000,
        irpRetirementPortion: 40000000,
        isaMaturity: 30000000,
        isaProfit: 5000000,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        simulationYears: 10,
        expectedReturnRate: 0.04,
      );
      const withNullFields = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 80000000,
        irpBalance: 50000000,
        irpRetirementPortion: 40000000,
        isaMaturity: 30000000,
        isaProfit: 5000000,
        currentAge: 58,
        targetAnnualWithdrawal: 24000000,
        simulationYears: 10,
        expectedReturnRate: 0.04,
        npsMonthlyAmount: null,
        npsStartAge: null,
      );

      final a = PensionSimulator.run(withoutFields, fillBracket);
      final b = PensionSimulator.run(withNullFields, fillBracket);
      expect(a.totalTax, b.totalTax);
      expect(a.totalWithdrawn, b.totalWithdrawn);
      expect(a.finalBalance, b.finalBalance);
      for (var i = 0; i < a.schedule.length; i++) {
        expect(a.schedule[i].totalAmount, b.schedule[i].totalAmount);
        expect(a.schedule[i].npsAnnualAmount, 0);
        expect(b.schedule[i].npsAnnualAmount, 0);
      }
    });
  });

  group('PensionSimulator.run — 소득 크레바스', () {
    // 58세 시작, 국민연금 65세 개시 월 60만원, 목표 연 2,000만원.
    // 비공제 연금저축 5억으로 캡·한도 이슈를 배제하고 순수 크레바스
    // 차감 로직만 검증한다 (payoutCap/bracketCap 모두 비적용 소스).
    const crevasseInput = PensionInput(
      pensionSavings: 500000000,
      pensionSavingsDeducted: 0, // 전액 비공제 → 캡 미적용 소스
      irpBalance: 0,
      irpRetirementPortion: 0,
      isaMaturity: 0,
      currentAge: 58,
      targetAnnualWithdrawal: 20000000,
      simulationYears: 10, // 58~67세
      expectedReturnRate: 0,
      npsMonthlyAmount: 600000, // 월 60만
      npsStartAge: 65,
    );

    test('58~64세(개시 전): 전액 연금계좌 인출, 국민연금 0', () {
      final outcome = PensionSimulator.run(crevasseInput, taxFreeFirst);
      final crevasseYears = outcome.schedule.where(
        (y) => y.age >= 58 && y.age <= 64,
      );
      expect(crevasseYears.length, 7);
      for (final year in crevasseYears) {
        expect(year.npsAnnualAmount, 0, reason: '${year.age}세');
        expect(year.totalAmount, 20000000, reason: '${year.age}세');
      }
    });

    test('65세부터: 연 720만 국민연금 차감, 계좌 인출은 차액만', () {
      final outcome = PensionSimulator.run(crevasseInput, taxFreeFirst);
      final activeYears = outcome.schedule.where(
        (y) => y.age >= 65 && y.age <= 67,
      );
      expect(activeYears.length, 3);
      for (final year in activeYears) {
        expect(year.npsAnnualAmount, 7200000, reason: '${year.age}세');
        expect(year.totalAmount, 20000000 - 7200000, reason: '${year.age}세');
      }
    });

    test('4개 전략 전부 동일한 국민연금 차감 (전략별 분기 없는 공통부 검증)', () {
      for (final strategy in kStrategies) {
        final outcome = PensionSimulator.run(crevasseInput, strategy);
        for (final year in outcome.schedule) {
          final expected = year.age >= 65 ? 7200000 : 0;
          expect(
            year.npsAnnualAmount,
            expected,
            reason: '${strategy.id} ${year.age}세',
          );
        }
      }
    });

    test('경계: 시작 나이가 이미 개시연령 이상이면 첫해부터 차감', () {
      const input = PensionInput(
        pensionSavings: 500000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 65, // 이미 개시연령
        targetAnnualWithdrawal: 20000000,
        simulationYears: 3,
        expectedReturnRate: 0,
        npsMonthlyAmount: 600000,
        npsStartAge: 65,
      );
      final outcome = PensionSimulator.run(input, taxFreeFirst);
      expect(outcome.schedule.first.age, 65);
      expect(outcome.schedule.first.npsAnnualAmount, 7200000);
      expect(outcome.schedule.first.totalAmount, 20000000 - 7200000);
    });
  });

  group('PensionSimulator.run — 국민연금 초과 (음수 인출 금지)', () {
    test('국민연금 연액 > 목표 인출액 → 계좌 인출 0, 세금 0, 잔액은 성장만', () {
      const input = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 65,
        targetAnnualWithdrawal: 5000000, // 연 500만
        simulationYears: 1,
        expectedReturnRate: 0.03,
        npsMonthlyAmount: 1000000, // 월 100만 → 연 1,200만 (목표 초과)
        npsStartAge: 65,
      );
      final outcome = PensionSimulator.run(input, taxFreeFirst);
      final year1 = outcome.schedule.first;

      expect(year1.npsAnnualAmount, 12000000);
      expect(year1.totalAmount, 0, reason: '국민연금이 목표 초과 → 계좌 인출 없음');
      expect(year1.totalTax, 0);
      expect(year1.withdrawals, isEmpty);

      // 잔액은 복리 성장분만큼만 증가 (인출 0이므로 1억×3% = 300만)
      expect(outcome.finalBalance, 103000000);
    });

    test('국민연금 연액 == 목표 인출액 → 정확히 0 (경계, 음수 아님)', () {
      const input = PensionInput(
        pensionSavings: 100000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 65,
        targetAnnualWithdrawal: 7200000,
        simulationYears: 1,
        expectedReturnRate: 0,
        npsMonthlyAmount: 600000, // 연 720만 == 목표
        npsStartAge: 65,
      );
      final outcome = PensionSimulator.run(input, taxFreeFirst);
      expect(outcome.schedule.first.totalAmount, 0);
      expect(outcome.schedule.first.npsAnnualAmount, 7200000);
    });
  });

  group('PensionSimulator.run — 단위 의미론 (월액×12 회귀 차단)', () {
    // Task 2에서 실제로 발생한 연/월 혼동 버그(FIX 6cd9343)와 같은 계열의
    // 회귀를 막기 위해 절대금액이 아닌 불변식으로 검증한다:
    // 국민연금 도입 전후 총 인출액(연금계좌) 차이 = 개시연령 이후 연수 × 연액.
    // 이 불변식은 "월액을 그대로 연액처럼 차감"(12배 과소차감) 또는
    // "월액을 연액인 줄 모르고 ×12 누락"(12배 과다차감 방지) 양쪽 방향의
    // 단위 버그를 모두 절대금액 없이 잡아낸다.
    test('불변식: 도입 전후 총 계좌인출 차이 = 개시연령 이후 연수 × (월수령액×12)', () {
      const baseline = PensionInput(
        pensionSavings: 500000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 20000000,
        simulationYears: 10, // 58~67세
        expectedReturnRate: 0,
      );
      const withNps = PensionInput(
        pensionSavings: 500000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 58,
        targetAnnualWithdrawal: 20000000,
        simulationYears: 10,
        expectedReturnRate: 0,
        npsMonthlyAmount: 600000,
        npsStartAge: 65, // 65~67세, 3개년 활성
      );

      final base = PensionSimulator.run(baseline, taxFreeFirst);
      final withCrevasse = PensionSimulator.run(withNps, taxFreeFirst);

      final baseTotalWithdrawn = base.schedule.fold<int>(
        0,
        (s, y) => s + y.totalAmount,
      );
      final crevasseTotalWithdrawn = withCrevasse.schedule.fold<int>(
        0,
        (s, y) => s + y.totalAmount,
      );

      const activeYears = 3; // 65,66,67세
      const npsAnnualAmount = 600000 * 12; // 7,200,000
      final expectedDiff = activeYears * npsAnnualAmount;

      expect(baseTotalWithdrawn - crevasseTotalWithdrawn, expectedDiff);

      // npsAnnualAmount 필드 합계도 동일 불변식을 만족해야 한다
      // (월액 그대로 노출되는 회귀 — 12배 작은 값 — 도 이 assert가 잡는다).
      final totalNpsExposed = withCrevasse.schedule.fold<int>(
        0,
        (s, y) => s + y.npsAnnualAmount,
      );
      expect(totalNpsExposed, expectedDiff);
    });

    test('연/월 혼동 회귀 직격: 연액(720만)을 월액인 줄 알고 다시 ×12 하면 8,640만 —'
        ' 실제 필드값은 정확히 연액(720만)이어야 한다', () {
      const input = PensionInput(
        pensionSavings: 500000000,
        pensionSavingsDeducted: 0,
        irpBalance: 0,
        irpRetirementPortion: 0,
        isaMaturity: 0,
        currentAge: 65,
        targetAnnualWithdrawal: 100000000, // 여유있게 커서 클램프 미발동
        simulationYears: 1,
        expectedReturnRate: 0,
        npsMonthlyAmount: 600000,
        npsStartAge: 65,
      );
      final outcome = PensionSimulator.run(input, taxFreeFirst);
      final actual = outcome.schedule.first.npsAnnualAmount;
      expect(actual, 7200000); // 월 60만 × 12 = 연 720만
      expect(actual, isNot(600000)); // 월액 그대로 노출(회귀) 아님
      expect(actual, isNot(86400000)); // 연액을 월액으로 오인해 재 ×12 아님
    });
  });
}
