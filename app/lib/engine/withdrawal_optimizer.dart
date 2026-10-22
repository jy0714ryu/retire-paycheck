// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
import 'pension_input.dart';
import 'simulation_result.dart';
import 'pension_simulator.dart';
import 'withdrawal_strategies.dart';

/// 인출 전략 토너먼트 — 4개 후보 전략을 전부 시뮬레이션해 최적을 고른다
class WithdrawalOptimizer {
  WithdrawalOptimizer._();

  static SimulationResult optimize(PensionInput input) {
    final outcomes =
        kStrategies.map((s) => PensionSimulator.run(input, s)).toList();

    // 우승: taxBurden(낸 세금+잠재세) 최소 — 동률 시 kStrategies 순서 우선
    var best = outcomes.first;
    for (final o in outcomes.skip(1)) {
      if (o.taxBurden < best.taxBurden) best = o;
    }
    final baseline =
        outcomes.firstWhere((o) => o.strategyId == 'pension_first');

    // 최적 시퀀스 = 우승 스케줄에서 실제 인출이 발생한 소스의 등장 순서
    final sequence = <WithdrawalSource>[];
    for (final year in best.schedule) {
      for (final d in year.withdrawals) {
        if (!sequence.contains(d.source)) sequence.add(d.source);
      }
    }

    return SimulationResult(
      schedule: best.schedule,
      totalTaxOptimal: best.totalTax,
      totalTaxBaseline: baseline.totalTax,
      optimalSequence: sequence,
      outcomes: outcomes,
      optimalStrategyId: best.strategyId,
      optimalStrategyName: best.strategyName,
      baselineSchedule: baseline.schedule,
    );
  }
}
