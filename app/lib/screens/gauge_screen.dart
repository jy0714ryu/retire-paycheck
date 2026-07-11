import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../services/cashflow_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/banner_ad_widget.dart';

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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('세금 임계치'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: asyncEvents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.invalidate(dividendEventsProvider),
        ),
        data: (events) => _buildBody(
          context,
          holdings,
          input,
          events,
          targetYear,
          accounts,
          interestItems,
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
    // 연금 인출 모드 OFF 면 절벽 게이지는 실제 인출 전 시뮬레이션 값 —
    // 건보 참고용 배지 패턴을 재사용해 "인출 전" 임을 명시한다.
    final pensionIsReference = !input.isWithdrawing;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('$targetYear년 세금 임계치', style: AppTextStyles.h3),
        const SizedBox(height: 4),
        Text(
          '연간 누계가 기준선에 얼마나 가까운지 보여줍니다',
          style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
        ),
        const SizedBox(height: 20),
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
          overWarning:
              '1,500만원을 넘으면 초과분이 아니라 전액이 16.5% 과세로 전환될 수 있습니다',
          isReference: pensionIsReference,
          referenceNote: pensionIsReference ? '연금 인출 전 (참고용)' : null,
        ),
        const SizedBox(height: 14),
        _GaugeCard(
          title: '건강보험 피부양자 소득',
          status: gauges.healthInsurance,
          overWarning: '피부양자 자격에 영향을 줄 수 있습니다',
          isReference: true,
          referenceNote:
              '공적연금·기타 소득 합산에 따라 달라질 수 있으며, 사적연금 인출은 포함되지 않습니다 (기준: 2026-07 현행)',
        ),
        const SizedBox(height: 40),
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
              if (isReference) ...[
                const SizedBox(width: 8),
                _ReferenceBadge(),
              ],
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
                  const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.error),
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
          if (isReference && referenceNote != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.gray400),
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

  static final NumberFormat _fmt = NumberFormat('#,###');

  /// 원 → 만원(정수 절사) + 천단위 콤마.
  static String _man(int won) => _fmt.format(won ~/ 10000);

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
              const Icon(Icons.savings_outlined,
                  size: 18, color: AppColors.success),
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
          Text('배당 정보를 불러오지 못했습니다',
              style: AppTextStyles.body.copyWith(color: AppColors.gray500)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
