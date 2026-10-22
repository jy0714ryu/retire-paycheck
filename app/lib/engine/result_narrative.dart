// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
import 'pension_input.dart';
import 'simulation_result.dart';
import 'pension_simulator.dart' show kPensionWithdrawalMinAge;

/// 결과 화면 상단 "불안 → 숫자" 내러티브 계산 결과.
///
/// 순수 계산 로직만 담당 — 위젯에 직접 넣지 않고 단위 테스트 가능하게 분리한다
/// (v1.1 Task 6, exec-plan §③).
class WithdrawalNarrative {
  /// 월 인출액 (원) = targetAnnualWithdrawal ÷ 12
  final int monthlyWithdrawal;

  /// 목표 인출을 온전히 채운 연수 (잔액 고갈 전) — 고갈이 없으면 스케줄 전체 연수
  final int fundedYears;

  /// 시뮬레이션 기간 중 목표 인출에 미달한 해가 있었는지 (중간 고갈 여부)
  final bool depleted;

  /// 고갈 나이 (목표 미달 첫 해의 나이) — depleted가 true일 때만 값이 있음
  final int? depletionAge;

  const WithdrawalNarrative({
    required this.monthlyWithdrawal,
    required this.fundedYears,
    required this.depleted,
    this.depletionAge,
  });
}

/// 국민연금 개시 전/후 소득 크레바스 요약.
///
/// hasNps=false 이면 호출하지 않는다(결과 null 아님 — 호출부에서 hasNps 가드).
class CrevasseSummary {
  /// 국민연금 개시 전 공백기 연수 (스케줄 시작부터 개시 연도 전까지)
  final int gapYears;

  /// 공백기 대표 연간 인출액 (원) — 스케줄 첫 해 기준. gapYears가 0이면 0.
  final int preNpsAnnualWithdrawal;

  /// 개시 이후 대표 연간 인출액 (원) — 개시 연도 기준. 개시 연도가 스케줄에
  /// 없으면(시뮬레이션 기간이 개시 전에 끝남) null.
  final int? postNpsAnnualWithdrawal;

  /// 스케줄 내 개시 연도 인덱스 (0-based) — 없으면 null
  final int? startYearIndex;

  const CrevasseSummary({
    required this.gapYears,
    required this.preNpsAnnualWithdrawal,
    required this.postNpsAnnualWithdrawal,
    required this.startYearIndex,
  });
}

/// 결과 최상단 내러티브 계산 — "이 계획이면 월 ○○만원을 N년간 쓸 수 있습니다".
///
/// N은 [SimulationResult.schedule]을 순회하며 각 해의 실제 인출액
/// ([YearlyWithdrawal.totalAmount])이 그 해의 목표 인출액(연간 목표 - 국민연금
/// 수령액)에 미달하는 첫 해를 찾는다. 미달하는 해가 없으면 스케줄 전체가
/// "여유 있음"으로 처리된다.
WithdrawalNarrative computeWithdrawalNarrative(
  SimulationResult result,
  PensionInput input,
) {
  final monthlyWithdrawal = (input.targetAnnualWithdrawal / 12).round();

  var fundedYears = 0;
  int? depletionAge;

  for (final yearRow in result.schedule) {
    // 55세 전 적립기 행은 인출 0이 정상 — 고갈·충족 판정 대상에서 제외
    if (yearRow.age < kPensionWithdrawalMinAge) continue;
    final targetForYear =
        (input.targetAnnualWithdrawal - yearRow.npsAnnualAmount)
            .clamp(0, 1 << 60);
    if (yearRow.totalAmount < targetForYear) {
      depletionAge = yearRow.age;
      break;
    }
    fundedYears++;
  }

  return WithdrawalNarrative(
    monthlyWithdrawal: monthlyWithdrawal,
    fundedYears: fundedYears,
    depleted: depletionAge != null,
    depletionAge: depletionAge,
  );
}

/// 국민연금 개시 전/후 크레바스 요약 계산 — hasNps=true 일 때만 호출한다.
CrevasseSummary computeCrevasseSummary(
  SimulationResult result,
  PensionInput input,
) {
  final schedule = result.schedule;

  // 공백기·대표 인출액은 실제 인출이 가능한 55세 이후 행 기준으로 계산한다
  // (55세 전 적립기 행은 인출 0이라 공백기 연수·대표액을 왜곡).
  var gapYears = 0;
  int? startYearIndex;
  int? firstActiveIndex;
  for (var i = 0; i < schedule.length; i++) {
    if (schedule[i].npsAnnualAmount > 0) {
      startYearIndex = i;
      break;
    }
    if (schedule[i].age >= kPensionWithdrawalMinAge) {
      firstActiveIndex ??= i;
      gapYears++;
    }
  }

  final preNpsAnnualWithdrawal = gapYears > 0 && firstActiveIndex != null
      ? schedule[firstActiveIndex].totalAmount
      : 0;
  final postNpsAnnualWithdrawal =
      startYearIndex != null ? schedule[startYearIndex].totalAmount : null;

  return CrevasseSummary(
    gapYears: gapYears,
    preNpsAnnualWithdrawal: preNpsAnnualWithdrawal,
    postNpsAnnualWithdrawal: postNpsAnnualWithdrawal,
    startYearIndex: startYearIndex,
  );
}
