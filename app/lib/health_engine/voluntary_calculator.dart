// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 임의계속가입자 보험료 계산.
///
/// 퇴직 후 최대 36개월 직장 자격 유지. 보험료 = 보수월액 × 요율 × 50%(본인부담)
/// + 장기요양. 36개월 타임라인을 생성한다.
library;

import 'params.dart';
import 'rounding.dart';

/// 임의계속 월별 타임라인 항목.
class VoluntaryTimelineEntry {
  const VoluntaryTimelineEntry({
    required this.month,
    required this.monthlyTotal,
    required this.cumulative,
  });

  /// 1~36.
  final int month;
  final int monthlyTotal;
  final int cumulative;
}

/// 임의계속 계산 결과.
class VoluntaryResult {
  const VoluntaryResult({
    required this.healthPremium,
    required this.ltcPremium,
    required this.monthlyTotal,
    required this.months,
    required this.totalOverPeriod,
    required this.timeline,
  });

  /// 본인부담 건강보험료(원).
  final int healthPremium;

  /// 장기요양보험료(원).
  final int ltcPremium;

  /// 월 납부 총액(원).
  final int monthlyTotal;

  /// 유지 개월 수(36).
  final int months;

  /// 전 기간 총액(원).
  final int totalOverPeriod;

  /// 36개월 타임라인.
  final List<VoluntaryTimelineEntry> timeline;
}

/// 임의계속 계산기.
class VoluntaryCalculator {
  const VoluntaryCalculator(this.params, {this.maxMonths = 36});

  final HealthParams params;

  /// 임의계속 최대 유지 개월(제도상 36개월).
  final int maxMonths;

  VoluntaryResult calculate({required num avgMonthlySalary}) {
    // 보수월액 × 요율 × 50%(본인부담).
    final healthDouble = avgMonthlySalary * params.employeeRate * 0.5;
    final health = wonFloor(healthDouble);
    final ltc = wonFloor(health * params.ltcRateOfHealth);
    final monthly = health + ltc;

    final timeline = <VoluntaryTimelineEntry>[];
    var cumulative = 0;
    for (var m = 1; m <= maxMonths; m++) {
      cumulative += monthly;
      timeline.add(VoluntaryTimelineEntry(
        month: m,
        monthlyTotal: monthly,
        cumulative: cumulative,
      ));
    }

    return VoluntaryResult(
      healthPremium: health,
      ltcPremium: ltc,
      monthlyTotal: monthly,
      months: maxMonths,
      totalOverPeriod: monthly * maxMonths,
      timeline: List.unmodifiable(timeline),
    );
  }
}
