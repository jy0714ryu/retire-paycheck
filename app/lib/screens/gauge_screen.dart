import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../services/cashflow_engine.dart';
import '../services/health_bridge.dart';
import '../health_engine/engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/settings_button.dart';

/// 화면3 — 세금 임계치 게이지 3종.
///
/// [CashflowEngine.buildGauges] 로 산출한 연간 게이지(금융소득종합과세·건보 산입·
/// 연금 저율 한도)를 카드로 시각화한다. 색 규칙은 초록(<80%)/노랑(80~100%)/빨강(>100%).
/// 건보 카드는 산식 단순화로 "참고용" 배지 + 디스클레이머를 상시 노출한다(단정 금지).
class GaugeScreen extends ConsumerWidget {
  /// 기준 연도(테스트 주입용). null 이면 현재 연도.
  final int? year;

  const GaugeScreen({super.key, this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);
    final input = ref.watch(retirementInputProvider);
    // 기본 계좌 오버라이드(연금저축·IRP 등)까지 합산한 effectiveAccountsProvider 로
    // 게이지·ISA 절세효과를 산출한다(v3 배선 — Task 6).
    final accounts = ref.watch(effectiveAccountsProvider);
    final interestItems = ref.watch(interestItemsProvider);
    final targetYear = year ?? DateTime.now().year;
    // API + 수동 입력 합성 이벤트 merge (합성 연도 = 게이지 기준 연도).
    final asyncEvents = ref.watch(combinedEventsProvider(targetYear));
    // 건보료나침반 엔진 파라미터(번들) — 로딩 전엔 기존 단순 카드로 보인다.
    final healthParams = ref.watch(healthParamsProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('세금'),
        actions: const [SettingsButton()],
      ),
      body: asyncEvents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _ErrorView(onRetry: () => ref.invalidate(dividendEventsProvider)),
        data: (events) => _buildBody(
          context,
          holdings,
          input,
          events,
          targetYear,
          accounts,
          interestItems,
          healthParams,
        ),
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Holding> holdings,
    RetirementInput input,
    List<DividendEvent> events,
    int targetYear,
    List<Account> accounts,
    List<InterestItem> interestItems,
    HealthParams? healthParams,
  ) {
    final gauges = CashflowEngine.buildGauges(
      holdings: holdings,
      events: events,
      input: input,
      year: targetYear,
      accounts: accounts,
      interestItems: interestItems,
    );
    final isaSavings = CashflowEngine.isaAnnualSavings(
      holdings: holdings,
      events: events,
      accounts: accounts,
      year: targetYear,
    );
    // 인출을 켠 pension 계좌가 하나도 없거나, 전역 인출 개시월이 미래면(오늘 <
    // 개시월) 절벽 게이지는 실제 인출 전 시뮬레이션 값 — 건보 참고용 배지 패턴을
    // 재사용해 "인출 시작 전" 임을 명시한다. v4: 계좌별 Account.isWithdrawing 게이트
    // (buildGauges 와 동일), v5: 전역 withdrawalStartMonth 게이트를 추가로 반영.
    final start = input.withdrawalStartMonth;
    final now = DateTime.now();
    final globalStartInFuture =
        start != null &&
        DateTime(
          now.year,
          now.month,
        ).isBefore(DateTime(start.year, start.month));
    final pensionIsReference =
        globalStartInFuture ||
        !accounts.any(
          (a) => a.type == AccountType.pension && a.withdrawalActive,
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TaxHero(
          year: targetYear,
          // 메인 판정은 금융소득·연금 저율 한도만(건보는 참고용 — 달력 경고와 같은 기준).
          ratios: [
            gauges.financialIncome.ratio,
            if (!pensionIsReference) gauges.pensionLowRate.ratio,
          ],
        ),
        const SizedBox(height: 14),
        // 만원 단위 표시가 0이 되는 소액(1만원 미만)은 "0만원 절세 중" 으로
        // 보이므로 노출하지 않는다 (실기기 E2E 발견 — 2026-07-12).
        if (isaSavings >= 10000) ...[
          _IsaSavingsCard(savings: isaSavings),
          const SizedBox(height: 14),
        ],
        _GaugeCard(
          title: '금융소득 종합과세',
          status: gauges.financialIncome,
          overWarning: '2,000만원 초과분은 종합과세 대상입니다',
        ),
        const SizedBox(height: 14),
        _GaugeCard(
          title: '사적연금 저율과세 한도',
          status: gauges.pensionLowRate,
          overWarning: '1,500만원을 넘으면 전액 16.5% 과세될 수 있어요',
          isReference: pensionIsReference,
          referenceNote: pensionIsReference
              ? '연금 인출 전 (참고용)'
              : ((input.pensionNonDeducted ?? 0) > 0 ||
                    (input.irpRetirement ?? 0) > 0)
              // 게이지는 월 인출 합계로 센다 — 어느 재원에서 꺼낼지는 계획 탭이 정한다.
              ? '공제 안 받은 원금·퇴직금 인출은 한도에서 빠져요 — 여유가 더 클 수 있어요'
              : null,
        ),
        const SizedBox(height: 14),
        ..._healthCard(
          input,
          gauges.healthInsurance,
          gauges.financialIncome.current,
          healthParams,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// 건보 카드 — 가입 형태별로 기준·문구가 다르다 (2026년 기준, v2.2 건보료나침반 엔진).
/// 공적연금·그 밖의 소득·재산은 '내 자산 › 공통 설정 › 건강보험'에서 입력.
List<Widget> _healthCard(
  RetirementInput input,
  GaugeStatus status,
  int financialIncomeAnnual,
  HealthParams? params,
) {
  final household = householdFrom(
    input,
    financialIncomeAnnual: financialIncomeAnnual,
  );
  final cards = <Widget>[];
  switch (input.healthInsType) {
    case HealthInsType.dependent:
      if (params == null) {
        cards.add(
          _GaugeCard(
            title: '건강보험 피부양자 소득',
            status: status,
            overWarning: '2,000만원을 넘으면 피부양자에서 빠질 수 있어요',
            referenceNote:
                '금융소득(1,000만원 초과 시 전액) + 공적연금 + 기타 소득 · '
                '연금저축·IRP 인출 제외',
          ),
        );
      } else {
        cards.add(
          _DependentCard(
            result: DependentJudge(params).judge(household),
            propertyTaxBase: input.propertyTaxBase,
          ),
        );
      }
    case HealthInsType.employee:
      cards.add(
        _GaugeCard(
          title: '월급 외 소득 (건보료 추가)',
          status: status,
          overWarning: '2,000만원 넘는 부분에 건보료 추가',
          referenceNote: '넉넉히 전액 합산 — 실제는 더 낮을 수 있어요 · 1,000만원 하향 개편 논의 중',
        ),
      );
    case HealthInsType.regional:
      if (params == null) {
        cards.add(
          const _HealthShell(
            title: '건강보험 (지역가입자)',
            children: [Text('소득·재산 기준을 불러오는 중이에요')],
          ),
        );
      } else {
        cards.add(
          _RegionalCard(
            result: RegionalCalculator(params).calculate(
              income: household.income,
              propertyTaxBase: household.propertyTaxBase,
            ),
            propertyEntered: input.propertyTaxBase > 0,
          ),
        );
      }
  }
  // 퇴직 전 월급을 넣었으면 퇴직 후 36개월 선택지 비교 (임의계속·지역·피부양자).
  // 지금 피부양자면 퇴직 후 비교는 해당 없음 — 직장·지역가입자만.
  if (params != null &&
      input.lastMonthlySalary > 0 &&
      input.healthInsType != HealthInsType.dependent) {
    cards
      ..add(const SizedBox(height: 14))
      ..add(
        _RetireCompareCard(
          result: RetirementComparison(params).compare(household),
          propertyEntered: input.propertyTaxBase > 0,
        ),
      );
  }
  return cards;
}

String _manWon(int won) => '${CurrencyFormat.man(won)}만원';
String _eok(int won) => CurrencyFormat.eokMan(won);

class _HealthShell extends StatelessWidget {
  const _HealthShell({required this.title, required this.children, this.badge});

  final String title;
  final Widget? badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(title, style: AppTextStyles.h4)),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

Widget _pill(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(text, style: AppTextStyles.labelSmall.copyWith(color: color)),
);

Widget _note(String text) => Padding(
  padding: const EdgeInsets.only(top: 10),
  child: Text(
    text,
    style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
  ),
);

/// 게이지 막대 + "연간 ○ ÷ 기준 ○ (○%)" 한 줄 — [_GaugeCard] 와 같은 색 규칙.
class _GaugeBar extends StatelessWidget {
  const _GaugeBar({required this.status});

  final GaugeStatus status;

  @override
  Widget build(BuildContext context) {
    final ratio = status.ratio;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 12,
              backgroundColor: AppColors.gray100,
              valueColor: AlwaysStoppedAnimation<Color>(
                _GaugeCard._gaugeColor(ratio),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '연 소득 ${_GaugeCard._man(status.current)}만원 ÷ '
            '한도 ${_GaugeCard._man(status.threshold)}만원 (${_GaugeCard._pct(ratio)})',
            style: AppTextStyles.body.copyWith(
              color: AppColors.gray700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 피부양자 판정 — 소득(재산 구간별 한도)·재산·사업소득.
class _DependentCard extends StatelessWidget {
  const _DependentCard({required this.result, required this.propertyTaxBase});

  final DependentResult result;
  final int propertyTaxBase;

  static const _reasonText = {
    DependentReason.incomeOverLimit: '연 소득이 2,000만원을 넘어요',
    DependentReason.incomeOverMidLimit: '재산 5.4억~9억은 소득 한도 1,000만원 — 넘어요',
    DependentReason.propertyOverLimit: '재산 과세표준이 9억원을 넘어요',
    DependentReason.businessRegistered: '사업자등록이 있고 사업소득이 있어요',
    DependentReason.businessUnregistered: '사업자등록 없는 사업소득이 500만원을 넘어요',
    DependentReason.spouseJointFail: '배우자가 소득 요건을 넘어요',
  };

  @override
  Widget build(BuildContext context) {
    final ok = result.isEligible;
    final bandText = switch (result.band) {
      PropertyBand.low => '5.4억 이하 구간 (소득 한도 2,000만원)',
      PropertyBand.mid => '5.4억~9억 구간 (소득 한도 1,000만원)',
      PropertyBand.over => '9억 초과 (재산 요건 초과)',
    };
    return _HealthShell(
      title: '건강보험 피부양자',
      badge: ok
          ? _pill('계산상 유지', AppColors.success)
          : _pill('계산상 탈락 가능', AppColors.error),
      children: [
        if (result.band != PropertyBand.over)
          _GaugeBar(
            status: GaugeStatus(
              current: result.totalIncome,
              threshold: result.applicableIncomeLimit,
            ),
          ),
        Text(
          propertyTaxBase > 0
              ? '재산 과세표준 ${_eok(propertyTaxBase)} — $bandText'
              : '재산 미입력 — 5.4억 이하로 가정',
          key: const Key('dependent_band'),
          style: AppTextStyles.body.copyWith(color: AppColors.gray700),
        ),
        for (final r in result.failReasons)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '· ${_reasonText[r] ?? r}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        _note(
          '금융소득(1,000만원 초과 시 전액) + 공적연금 + 기타 소득 · 연금저축·IRP 인출 제외 · '
          '배우자도 함께 봐요 · 2026년 기준 추정',
        ),
      ],
    );
  }
}

/// 지역가입자 예상 월 건보료 (소득분 + 재산분 + 장기요양).
class _RegionalCard extends StatelessWidget {
  const _RegionalCard({required this.result, required this.propertyEntered});

  final RegionalResult result;
  final bool propertyEntered;

  @override
  Widget build(BuildContext context) {
    return _HealthShell(
      title: '건강보험 (지역가입자)',
      children: [
        Text(
          '예상 월 건보료 ${_manWon(result.total)}',
          key: const Key('regional_total'),
          style: AppTextStyles.h3.copyWith(color: AppColors.navy),
        ),
        const SizedBox(height: 6),
        Text(
          '소득분 ${_manWon(result.incomePremium)} · 재산분 ${_manWon(result.propertyPremium)}'
          ' · 장기요양 ${_manWon(result.ltcPremium)}',
          style: AppTextStyles.body.copyWith(color: AppColors.gray700),
        ),
        if (result.clampedToMin) _note('최저 보험료가 적용됐어요.'),
        if (result.clampedToMax) _note('상한 보험료가 적용됐어요.'),
        _note(
          '${propertyEntered ? '' : '재산 미입력 → 재산분 0 · '}'
          '2026년 기준 추정 · 자동차·부양가족에 따라 달라져요',
        ),
      ],
    );
  }
}

/// 퇴직 후 36개월 — 임의계속가입·지역가입·피부양자 비교. "추천" 대신 계산상 비교만.
class _RetireCompareCard extends StatelessWidget {
  const _RetireCompareCard({
    required this.result,
    required this.propertyEntered,
  });

  final ComparisonResult result;
  final bool propertyEntered;

  @override
  Widget build(BuildContext context) {
    final cheapest = switch (result.recommended) {
      ComparisonOption.dependent => '피부양자',
      ComparisonOption.voluntary => '임의계속가입',
      ComparisonOption.regional => '지역가입',
    };
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: AppTextStyles.tabular,
            ),
          ),
        ],
      ),
    );
    return _HealthShell(
      title: '퇴직 후 건보료 비교 (36개월)',
      children: [
        row(
          '임의계속가입',
          '월 ${_manWon(result.voluntaryMonthly)} · 36개월 ${_manWon(result.voluntary36Total)}',
        ),
        row(
          '지역가입',
          '월 ${_manWon(result.regionalMonthly)} · 36개월 ${_manWon(result.regional36Total)}',
        ),
        row('피부양자', result.dependentEligible ? '계산상 가능 (0원)' : '계산상 어려움'),
        const SizedBox(height: 4),
        Text(
          '계산상 부담이 가장 적은 쪽: $cheapest',
          key: const Key('retire_compare_cheapest'),
          style: AppTextStyles.body.copyWith(color: AppColors.navy),
        ),
        _note(
          '${propertyEntered ? '' : '재산 미입력 → 지역 재산분 0 · '}'
          '임의계속은 지역 첫 고지서 후 2개월 안 신청 · 선택 전 공단 확인',
        ),
      ],
    );
  }
}

/// 게이지 카드 1종 — 제목 / 진행바(색 규칙) / "연간 ○○○만원 ÷ 기준 ○○○만원 (○○%)"
/// / 초과 시 경고 한 줄. [isReference] 이면 "참고용" 배지 + 디스클레이머 상시 노출.
class _GaugeCard extends StatelessWidget {
  final String title;
  final GaugeStatus status;
  final String overWarning;
  final bool isReference;
  final String? referenceNote;

  const _GaugeCard({
    required this.title,
    required this.status,
    required this.overWarning,
    this.isReference = false,
    this.referenceNote,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = status.ratio;
    final color = _gaugeColor(ratio);
    final isOver = ratio > 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: AppTextStyles.h4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isReference) ...[const SizedBox(width: 8), _ReferenceBadge()],
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 12,
              backgroundColor: AppColors.gray100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '연간 ${_man(status.current)}만원 ÷ '
            '기준 ${_man(status.threshold)}만원 (${_pct(ratio)})',
            style: AppTextStyles.body.copyWith(
              color: AppColors.gray700,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isOver) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      overWarning,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (referenceNote != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.gray400,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    referenceNote!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 색 규칙: <0.8 초록 / 0.8~1.0 노랑 / >1.0 빨강.
  static Color _gaugeColor(double ratio) {
    if (ratio > 1.0) return AppColors.error;
    if (ratio >= 0.8) return AppColors.warning;
    return AppColors.success;
  }

  /// 원 → 만원(소수 한 자리, 반올림) + 천단위 콤마.
  static String _man(int won) => CurrencyFormat.man(won);

  /// 비율 → 퍼센트 문자열. 정수면 정수, 아니면 소수 1자리.
  static String _pct(double ratio) {
    final p = ratio * 100;
    if ((p - p.roundToDouble()).abs() < 0.05) return '${p.round()}%';
    return '${p.toStringAsFixed(1)}%';
  }
}

/// ISA 절세효과 카드 — ISA 계좌 배당 gross × 15.4% 절세액을 게이지 목록 위에 노출.
/// [savings] 가 0 이하면 호출부에서 아예 렌더링하지 않는다.
class _IsaSavingsCard extends StatelessWidget {
  final int savings;

  const _IsaSavingsCard({required this.savings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.savings_outlined,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ISA 덕분에 연 ${_GaugeCard._man(savings)}만원 절세 중',
                  style: AppTextStyles.h4.copyWith(color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '(일반계좌 대비 · 비과세 한도 내 기준)',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
        ],
      ),
    );
  }
}

/// "참고용" 배지 — 건보 게이지 산식 단순화 고지(단정 금지).
class _ReferenceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '참고용',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.info,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: AppColors.gray400),
          const SizedBox(height: 12),
          Text(
            '배당 정보를 불러오지 못했습니다',
            style: AppTextStyles.body.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

/// 세금 탭 요약 카드 — 다른 탭과 같은 머리 카드(골드 선 + 라벨 + 큰 글씨) 규칙.
class _TaxHero extends StatelessWidget {
  const _TaxHero({required this.year, required this.ratios});
  final int year;
  final List<double> ratios;

  @override
  Widget build(BuildContext context) {
    final over = ratios.where((r) => r > 1.0).length;
    final near = ratios.where((r) => r >= 0.8 && r <= 1.0).length;
    final (String headline, Color color) = over > 0
        ? ('기준을 넘은 항목 $over개', AppColors.error)
        : near > 0
        ? ('기준에 가까운 항목 $near개', AppColors.warning)
        : ('모두 기준 안이에요', AppColors.navy);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 28, height: 2, color: AppColors.gold),
          const SizedBox(height: 12),
          Text(
            '$year년 세금 문턱',
            style: AppTextStyles.label.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            key: const Key('tax_hero_headline'),
            style: AppTextStyles.h2.copyWith(color: color, fontSize: 24),
          ),
          const SizedBox(height: 6),
          Text(
            '올해 누계를 기준선과 비교 · 80% 넘으면 주의',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
        ],
      ),
    );
  }
}
