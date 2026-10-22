import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/pension_input.dart';
import 'package:retire_paycheck/engine/withdrawal_optimizer.dart';

void main() {
  group('WithdrawalOptimizer.optimize — 전략 토너먼트', () {
    final result = WithdrawalOptimizer.optimize(PensionInput.example());

    test('4개 전략 결과가 전부 담긴다', () {
      expect(result.outcomes.length, 4);
    });

    test('절감액 ≥ 0 (우승 전략 세금 ≤ baseline 세금)', () {
      expect(
        result.totalTaxBaseline,
        greaterThanOrEqualTo(result.totalTaxOptimal),
      );
      expect(result.savings, greaterThanOrEqualTo(0));
    });

    test('우승 전략은 taxBurden 최소', () {
      final winner = result.outcomes.firstWhere(
        (o) => o.strategyId == result.optimalStrategyId,
      );
      for (final o in result.outcomes) {
        expect(winner.taxBurden, lessThanOrEqualTo(o.taxBurden));
      }
    });

    test('기존 API 계약: schedule·optimalSequence·baselineSchedule 채워짐', () {
      expect(result.schedule, isNotEmpty);
      expect(result.optimalSequence, isNotEmpty);
      expect(result.baselineSchedule, isNotEmpty);
      expect(result.optimalStrategyName, isNotEmpty);
      expect(
        result.cumulativeTaxBaseline.length,
        result.baselineSchedule.length,
      );
    });

    test('optimalSequence는 실제 인출 발생 순서 (중복 없음)', () {
      expect(
        result.optimalSequence.toSet().length,
        result.optimalSequence.length,
      );
    });
  });
}
