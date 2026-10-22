// 연금나침반(pension-compass)에서 이식 — 2026-10-22 v2 통합 (보강된 C안). 계산 규칙 SSOT 는 이 폴더.
import 'simulation_result.dart';

/// 인출 스텝 — 어느 풀에서, 어떤 캡을 지키며, 몇 세부터 인출할지
class DrawStep {
  final WithdrawalSource source;

  /// 1,500만원 저율 한도(절벽) 준수 — 과세재원에만 의미 있음
  final bool useBracketCap;

  /// 연금수령한도(10년 룰) 준수
  final bool usePayoutCap;

  /// 이 나이부터 인출 활성 (과세 이연 전략용)
  final int activeFromAge;

  const DrawStep(
    this.source, {
    this.useBracketCap = false,
    this.usePayoutCap = false,
    this.activeFromAge = 0,
  });
}

/// 인출 전략 — 스텝 순서 정책 (엔진은 PensionSimulator)
class WithdrawalStrategy {
  final String id;
  final String displayName;
  final String description;
  final List<DrawStep> steps;

  const WithdrawalStrategy({
    required this.id,
    required this.displayName,
    required this.description,
    required this.steps,
  });
}

const List<DrawStep> _taxFreeSteps = [
  DrawStep(WithdrawalSource.isaProfit),
  DrawStep(WithdrawalSource.isaPrincipal),
  DrawStep(WithdrawalSource.pensionNonDeducted),
];

const List<DrawStep> _taxableCappedSteps = [
  DrawStep(
    WithdrawalSource.pensionDeducted,
    useBracketCap: true,
    usePayoutCap: true,
  ),
  DrawStep(WithdrawalSource.irpSelf, useBracketCap: true, usePayoutCap: true),
  DrawStep(WithdrawalSource.earnings, useBracketCap: true, usePayoutCap: true),
];

const DrawStep _retirementCapped = DrawStep(
  WithdrawalSource.irpRetirement,
  usePayoutCap: true,
);

/// 전략 B — 매년 저율 1,500만원 한도를 채우고 부족분은 비과세로 (Fill the Bracket)
final fillBracket = WithdrawalStrategy(
  id: 'fill_bracket',
  displayName: '저율한도 채우기',
  description: '매년 과세 재원을 1,500만원 저율 한도까지 인출하고 부족분은 비과세로 충당',
  steps: [..._taxableCappedSteps, ..._taxFreeSteps, _retirementCapped],
);

/// 전략 A — 비과세 재원 우선 소진
final taxFreeFirst = WithdrawalStrategy(
  id: 'tax_free_first',
  displayName: '비과세 우선',
  description: '비과세 재원부터 소진하고 과세 재원은 저율 한도 내에서 인출',
  steps: [..._taxFreeSteps, ..._taxableCappedSteps, _retirementCapped],
);

/// 전략 C — 과세 인출을 70세(4.4%)·80세(3.3%) 저세율 구간으로 이연
final deferTaxable = WithdrawalStrategy(
  id: 'defer_taxable',
  displayName: '과세 이연 (노년 저세율)',
  description: '초기엔 비과세·퇴직금만 쓰고 과세 재원 인출을 70세 이후로 미룸',
  steps: [
    ..._taxFreeSteps,
    _retirementCapped,
    const DrawStep(
      WithdrawalSource.pensionDeducted,
      useBracketCap: true,
      usePayoutCap: true,
      activeFromAge: 70,
    ),
    const DrawStep(
      WithdrawalSource.irpSelf,
      useBracketCap: true,
      usePayoutCap: true,
      activeFromAge: 70,
    ),
    const DrawStep(
      WithdrawalSource.earnings,
      useBracketCap: true,
      usePayoutCap: true,
      activeFromAge: 70,
    ),
  ],
);

/// Baseline — 많은 이들이 무심코 택하는 순서 (절감액 비교 기준, 캡 미준수)
final pensionFirst = WithdrawalStrategy(
  id: 'pension_first',
  displayName: '기존 방식 (연금저축부터)',
  description: '연금저축 공제분부터 소진 — 절벽·한도를 고려하지 않는 일반적 방식',
  steps: const [
    DrawStep(WithdrawalSource.pensionDeducted),
    DrawStep(WithdrawalSource.irpSelf),
    DrawStep(WithdrawalSource.earnings),
    DrawStep(WithdrawalSource.irpRetirement),
    DrawStep(WithdrawalSource.isaProfit),
    DrawStep(WithdrawalSource.isaPrincipal),
    DrawStep(WithdrawalSource.pensionNonDeducted),
  ],
);

/// 토너먼트 참가 전략 — 순서가 동률 시 우선순위
final List<WithdrawalStrategy> kStrategies = [
  fillBracket,
  taxFreeFirst,
  deferTaxable,
  pensionFirst,
];

/// 목표 인출액 미달 시 캡 무시 폴백 순서 (세금 페널티 감수 — 현실 반영)
const List<WithdrawalSource> kFallbackOrder = [
  WithdrawalSource.isaProfit,
  WithdrawalSource.isaPrincipal,
  WithdrawalSource.pensionNonDeducted,
  WithdrawalSource.pensionDeducted,
  WithdrawalSource.irpSelf,
  WithdrawalSource.earnings,
  WithdrawalSource.irpRetirement,
];
