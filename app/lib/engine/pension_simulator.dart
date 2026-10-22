// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
import 'pension_input.dart';
import 'simulation_result.dart';
import 'tax_calculator.dart';
import 'withdrawal_strategies.dart';

/// 사적연금 과세재원 저율 분리과세 연간 한도 (원)
/// 수령한도 내 인정액 합계가 이를 초과하면 그 해 인정액 전액 16.5% (절벽)
const int kAnnualPensionBracket = 15000000;

/// 퇴직소득세 실효세율 가정 (근속연수·금액별 편차가 커 5% 고정 가정 — UI에 명시)
const double kRetirementEffectiveRate = 0.05;

/// 기타소득세율 (절벽·수령한도 초과)
const double kPenaltyRate = 0.165;

/// 연금계좌 인출(연금수령) 개시 최소 나이 — 55세 미만은 연금수령 자체가 불가
/// (소득세법상 연금외수령 16.5%). 시뮬레이션은 55세 전 구간을 인출 없는
/// 적립(운용)기로 처리하고, 연금수령연차도 55세부터 기산한다 (v1.1.1 감사 I1).
const int kPensionWithdrawalMinAge = 55;

/// 1,500만원 절벽 판정 대상 (사적연금 과세재원)
const Set<WithdrawalSource> kBracketSources = {
  WithdrawalSource.pensionDeducted,
  WithdrawalSource.irpSelf,
  WithdrawalSource.earnings,
};

/// 연금수령한도 소진 대상 (과세제외금액·ISA는 한도 미적용 — 소득세법 시행령 40조의3)
const Set<WithdrawalSource> kPayoutLimitedSources = {
  WithdrawalSource.pensionDeducted,
  WithdrawalSource.irpSelf,
  WithdrawalSource.earnings,
  WithdrawalSource.irpRetirement,
};

/// 연간 인출 원장 항목 — 수령한도 내(within)/초과(over) 분리 기록
class DrawSplit {
  int within = 0;
  int over = 0;
  int get total => within + over;
}

/// 연금 인출 시뮬레이션 엔진
class PensionSimulator {
  PensionSimulator._();

  /// 연금수령한도: 연차 1~10년 = 연초 연금계좌 평가액(ISA 제외) / (11-연차) × 1.2
  /// 연차 11년+ 무제한. ×1.2 는 정수 연산 (평가액×12 ÷ ((11-연차)×10)).
  static int payoutLimitFor(Map<WithdrawalSource, int> pools, int year) {
    if (year >= 11) return 1 << 60;
    final base =
        (pools[WithdrawalSource.pensionNonDeducted] ?? 0) +
        (pools[WithdrawalSource.pensionDeducted] ?? 0) +
        (pools[WithdrawalSource.irpSelf] ?? 0) +
        (pools[WithdrawalSource.earnings] ?? 0) +
        (pools[WithdrawalSource.irpRetirement] ?? 0);
    final limit = (base * 12) ~/ ((11 - year) * 10);
    // 몬테카를로 손실 연도에는 earnings 풀이 음수가 되어 평가액 합이 음수일 수
    // 있다 — 한도는 0 하한 (음수 한도는 clamp(0, 음수) ArgumentError 유발).
    return limit < 0 ? 0 : limit;
  }

  /// 연말 세금 확정 — 절벽·수령한도 초과·퇴직세 감면을 연간 합산 기준으로 일괄 판정
  static List<WithdrawalDetail> finalizeYearTax(
    Map<WithdrawalSource, DrawSplit> ledger,
    int age,
    int year, [
    double retirementRate = kRetirementEffectiveRate,
  ]) {
    final details = <WithdrawalDetail>[];

    // 1) 비과세 소스
    for (final src in const [
      WithdrawalSource.isaProfit,
      WithdrawalSource.isaPrincipal,
      WithdrawalSource.pensionNonDeducted,
    ]) {
      final split = ledger[src];
      if (split == null || split.total <= 0) continue;
      details.add(
        WithdrawalDetail(source: src, amount: split.total, tax: 0, taxRate: 0),
      );
    }

    // 2) 사적연금 과세재원 — 절벽 판정 (수령한도 내 인정액 합계 기준)
    final recognized = kBracketSources.fold<int>(
      0,
      (sum, src) => sum + (ledger[src]?.within ?? 0),
    );
    final cliff = recognized > kAnnualPensionBracket;
    final withinRate = cliff
        ? kPenaltyRate
        : TaxCalculator.getPensionTaxRate(age);
    for (final src in kBracketSources) {
      final split = ledger[src];
      if (split == null) continue;
      if (split.within > 0) {
        details.add(
          WithdrawalDetail(
            source: src,
            amount: split.within,
            tax: (split.within * withinRate).round(),
            taxRate: withinRate * 100,
          ),
        );
      }
      if (split.over > 0) {
        // 수령한도 초과 = 연금외수령 → 기타소득세 16.5%
        details.add(
          WithdrawalDetail(
            source: src,
            amount: split.over,
            tax: (split.over * kPenaltyRate).round(),
            taxRate: kPenaltyRate * 100,
          ),
        );
      }
    }

    // 3) 퇴직금 재원 — 한도 내 30% 감면(11년차부터 40%), 한도 초과 시 감면 없음
    final ret = ledger[WithdrawalSource.irpRetirement];
    if (ret != null) {
      final reduction = year <= 10 ? 0.7 : 0.6;
      if (ret.within > 0) {
        final rate = retirementRate * reduction;
        details.add(
          WithdrawalDetail(
            source: WithdrawalSource.irpRetirement,
            amount: ret.within,
            tax: (ret.within * rate).round(),
            taxRate: rate * 100,
          ),
        );
      }
      if (ret.over > 0) {
        details.add(
          WithdrawalDetail(
            source: WithdrawalSource.irpRetirement,
            amount: ret.over,
            tax: (ret.over * retirementRate).round(),
            taxRate: retirementRate * 100,
          ),
        );
      }
    }

    return details;
  }

  /// 단일 전략 시뮬레이션 — 연 단위 인출 → 연말 세금 확정 → 복리 성장 편입
  ///
  /// [yearlyReturns] 지정 시 해당 연차(index = year-1)의 수익률로 성장을 계산한다
  /// — 몬테카를로 경로 시뮬레이션용 (v1.3). 미지정이면 기존과 동일하게
  /// [PensionInput.expectedReturnRate] 고정 수익률.
  static StrategyOutcome run(
    PensionInput input,
    WithdrawalStrategy strategy, {
    List<double>? yearlyReturns,
  }) {
    final pools = <WithdrawalSource, int>{
      WithdrawalSource.isaProfit: input.isaProfit,
      WithdrawalSource.isaPrincipal: input.isaPrincipal,
      WithdrawalSource.pensionNonDeducted: input.pensionSavingsNonDeducted,
      WithdrawalSource.pensionDeducted: input.pensionSavingsDeducted,
      WithdrawalSource.irpSelf: input.irpSelfContribution,
      WithdrawalSource.earnings: 0,
      WithdrawalSource.irpRetirement: input.irpRetirementPortion,
    };

    final schedule = <YearlyWithdrawal>[];
    var totalTax = 0;
    var totalWithdrawn = 0;

    // 55세 전 적립기 연수 — 연금수령연차(수령한도·퇴직세 감면)는 55세부터 기산
    final preYears = (kPensionWithdrawalMinAge - input.currentAge).clamp(
      0,
      1 << 32,
    );

    for (int year = 1; year <= input.simulationYears; year++) {
      final age = input.currentAge + year - 1;
      // 55세 미만 = 인출 불가(연금외수령 16.5%) — 적립·운용만 수행
      final withdrawalActive = age >= kPensionWithdrawalMinAge;
      final payoutYear = (year - preYears).clamp(1, 1 << 32);

      // 국민연금 소득 크레바스 — 개시연령 이후 연간 목표 인출액에서
      // (월수령액×12)만큼 선차감. 미입력(hasNps=false)이거나 개시 전이면
      // 0으로 계산되어 기존 동작과 완전히 동일 (하위호환).
      // 세금 계산엔 일절 반영하지 않는다 — 순수 현금흐름 차감만
      // (exec-plan §① 보수 가정, TAX_RULES.md §7.7).
      final npsAnnualAmount = input.hasNps && age >= input.npsStartAge!
          ? input.npsMonthlyAmount! * 12
          : 0;

      var payoutRemaining = payoutLimitFor(pools, payoutYear);
      var bracketRemaining = kAnnualPensionBracket;
      // 국민연금이 목표를 초과해도 연금계좌 인출은 0에서 멈춘다 (음수 인출 금지).
      var remaining = withdrawalActive
          ? (input.targetAnnualWithdrawal - npsAnnualAmount).clamp(0, 1 << 60)
          : 0;
      final ledger = <WithdrawalSource, DrawSplit>{};

      // 풀 차감 + 원장 기록 + 한도 소진 (amount는 호출부에서 available 이내 보장)
      void draw(WithdrawalSource src, int amount) {
        if (amount <= 0) return;
        pools[src] = (pools[src] ?? 0) - amount;
        remaining -= amount;
        final split = ledger.putIfAbsent(src, DrawSplit.new);
        if (kPayoutLimitedSources.contains(src)) {
          final within = amount.clamp(0, payoutRemaining);
          split.within += within;
          split.over += amount - within;
          payoutRemaining -= within;
          if (kBracketSources.contains(src)) {
            bracketRemaining = (bracketRemaining - within).clamp(0, 1 << 60);
          }
        } else {
          split.within += amount; // 한도 미적용 소스는 전액 within
        }
      }

      // 1) 전략 스텝 순회 (캡 준수)
      for (final step in strategy.steps) {
        if (remaining <= 0) break;
        if (age < step.activeFromAge) continue;
        final available = pools[step.source] ?? 0;
        if (available <= 0) continue;
        var cap = available;
        if (step.usePayoutCap && kPayoutLimitedSources.contains(step.source)) {
          cap = cap.clamp(0, payoutRemaining);
        }
        if (step.useBracketCap && kBracketSources.contains(step.source)) {
          cap = cap.clamp(0, bracketRemaining);
        }
        draw(step.source, remaining.clamp(0, cap));
      }

      // 2) 폴백 — 목표 미달 시 캡 무시 (세금 페널티 감수, 현실 반영)
      for (final src in kFallbackOrder) {
        if (remaining <= 0) break;
        final available = pools[src] ?? 0;
        if (available <= 0) continue;
        draw(src, remaining.clamp(0, available));
      }

      // 3) 연말 세금 확정 (퇴직세 감면 연차도 연금수령연차 기준)
      final yearly = YearlyWithdrawal(
        year: year,
        age: age,
        withdrawals: finalizeYearTax(
          ledger,
          age,
          payoutYear,
          input.retirementTaxRate,
        ),
        npsAnnualAmount: npsAnnualAmount,
      );
      schedule.add(yearly);
      totalTax += yearly.totalTax;
      totalWithdrawn += yearly.totalAmount;

      // 4) 복리 성장 — 남은 잔액 × 수익률, 전액 과세재원(운용수익) 편입
      // 비과세 풀(ISA·비공제분)의 성장분도 과세 earnings로 편입 — 보수적
      // 단순화 (ISA 만기 후 연금계좌 이전 가정, UI '시뮬레이션 가정' 팁에 고지).
      final rate = yearlyReturns != null && year - 1 < yearlyReturns.length
          ? yearlyReturns[year - 1]
          : input.expectedReturnRate;
      var growth = 0;
      pools.forEach((src, balance) {
        if (balance > 0) growth += (balance * rate).round();
      });
      pools[WithdrawalSource.earnings] =
          (pools[WithdrawalSource.earnings] ?? 0) + growth;

      if (pools.values.every((v) => v <= 0)) break;
    }

    // 기말 잔액과 잠재세 (근사: 과세재원×기말나이 저율, 퇴직금×3.5%)
    final endAge = input.currentAge + schedule.length - 1;
    final taxableLeft = kBracketSources.fold<int>(
      0,
      (s, src) => s + (pools[src] ?? 0),
    );
    final retirementLeft = pools[WithdrawalSource.irpRetirement] ?? 0;
    // 잠재세는 저율 일괄 근사 — 잔여 과세재원이 커서 향후 인출이 1,500만
    // 절벽(16.5%)을 반복 유발하는 시나리오에서는 과소평가되어 과세이연
    // 전략이 유리하게 편향될 수 있다 (MVP 근사, 절벽 반영은 P1 후속).
    final latentTax =
        (taxableLeft * TaxCalculator.getPensionTaxRate(endAge)).round() +
        (retirementLeft * input.retirementTaxRate * 0.7).round();
    final finalBalance = pools.values.fold<int>(0, (s, v) => s + v);

    return StrategyOutcome(
      strategyId: strategy.id,
      strategyName: strategy.displayName,
      schedule: schedule,
      totalTax: totalTax,
      totalWithdrawn: totalWithdrawn,
      finalBalance: finalBalance,
      latentTax: latentTax,
    );
  }
}
