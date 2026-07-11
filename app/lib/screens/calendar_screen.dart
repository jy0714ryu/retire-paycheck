import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../services/ad_service.dart';
import '../services/cashflow_engine.dart';
import '../services/tax_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/banner_ad_widget.dart';

/// 화면2 — 은퇴 월급 달력 (메인).
///
/// 세후 통일: 메인 카드 = "이번 달 실수령"(net), 서브 = 세전(gross) 병기.
/// 상단 월 네비게이션(◀ ▶)으로 임의의 월을 조회한다. 각 월은
/// [CashflowEngine.buildMonths] 로 단건 산출, 게이지 경고는
/// [CashflowEngine.buildGauges] 로 해당 연도 기준 판정한다.
class CalendarScreen extends ConsumerStatefulWidget {
  /// 초기 표시 월(테스트 주입용). null 이면 현재 월.
  final DateTime? initialMonth;

  const CalendarScreen({super.key, this.initialMonth});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final base = widget.initialMonth ?? DateTime.now();
    _month = DateTime(base.year, base.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
    // 월 네비게이션 2회당 1회 전면 광고(첫 호출 면제 — ad_service 카운터).
    AdService().showInterstitialIfEligible();
  }

  /// 연간 막대 차트 탭 → 같은 연도 [month] 로 직접 이동.
  /// _shiftMonth 와 달리 광고를 트리거하지 않는다(광고 카운터 오염 방지).
  void _goToMonth(int month) {
    setState(() {
      _month = DateTime(_month.year, month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final holdings = ref.watch(holdingsProvider);
    final input = ref.watch(retirementInputProvider);
    final asyncEvents = ref.watch(dividendEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('은퇴 월급 달력'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: asyncEvents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(dividendEventsProvider)),
        data: (result) => _buildBody(holdings, input, result.events),
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  Widget _buildBody(
    List<Holding> holdings,
    RetirementInput input,
    List<DividendEvent> events,
  ) {
    final months = CashflowEngine.buildMonths(
      holdings: holdings,
      events: events,
      input: input,
      from: _month,
      monthCount: 1,
    );
    final cf = months.first;

    final gauges = CashflowEngine.buildGauges(
      holdings: holdings,
      events: events,
      input: input,
      year: _month.year,
    );
    // 참고용(건보) 게이지는 메인 경고를 구동하지 않는다 — 금융소득·연금 저율 한도만.
    final overThreshold = gauges.financialIncome.ratio > 1.0 ||
        gauges.pensionLowRate.ratio > 1.0;

    // 사적연금 연 인출액이 저율 한도(1,500만원)를 초과하면 전액 16.5% 절벽 적용.
    final pensionOverLowRate =
        input.monthlyPensionWithdrawal * 12 > kPensionLowRateLimit;

    // 연간 배당 요약(예측 포함) — 배당이 특정 월에 몰려 비어 보이는 문제 보완.
    final divSummary = CashflowEngine.yearlyDividendSummary(
      holdings: holdings,
      events: events,
      year: _month.year,
    );

    // 연간 12개월 현금흐름(세후) — 미니 막대 차트용. 배당 편중을 한눈에 보여준다.
    final yearMonths = CashflowEngine.buildMonths(
      holdings: holdings,
      events: events,
      input: input,
      from: DateTime(_month.year, 1, 1),
      monthCount: 12,
    );
    // 보유·연금이 전부 0이면(12개월 실수령 모두 0) 차트 미표시.
    final showBarChart = yearMonths.any((m) => m.totalNet > 0);

    // 라인 상세(주당×수량) 재구성용 조회 맵.
    final sharesByName = {for (final h in holdings) h.corpName: h.shares};
    final perShareByName = {for (final e in events) e.corpName: e.perShare};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MonthNav(
          month: _month,
          onPrev: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
        ),
        const SizedBox(height: 16),
        _MainCard(
          net: cf.totalNet,
          gross: cf.totalGross,
          dividendGross: cf.dividendGross,
          pensionGross: cf.pensionGross,
          overThreshold: overThreshold,
        ),
        if (holdings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _YearlyDividendCard(year: _month.year, summary: divSummary),
        ],
        if (showBarChart) ...[
          const SizedBox(height: 12),
          _YearlyBarChart(
            selectedMonth: _month.month,
            months: yearMonths,
            onSelectMonth: _goToMonth,
          ),
        ],
        const SizedBox(height: 20),
        Text('배당 내역 (세후 기준)', style: AppTextStyles.h4),
        const SizedBox(height: 8),
        if (cf.lines.isEmpty)
          _EmptyDividend()
        else
          ...cf.lines.map((line) => _DividendLineTile(
                line: line,
                perShare: perShareByName[line.corpName],
                shares: sharesByName[line.corpName],
              )),
        const SizedBox(height: 16),
        Text('연금 인출', style: AppTextStyles.h4),
        const SizedBox(height: 8),
        _PensionTile(
          pensionNet: cf.pensionNet,
          pensionGross: cf.pensionGross,
          overLowRate: pensionOverLowRate,
        ),
        const SizedBox(height: 20),
        _Notice(),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// 상단 월 네비게이션: ◀ YYYY년 M월 ▶.
class _MonthNav extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthNav({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left, size: 32),
          color: AppColors.navy,
          tooltip: '이전 달',
        ),
        Text(
          '${month.year}년 ${month.month}월',
          style: AppTextStyles.h3,
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, size: 32),
          color: AppColors.navy,
          tooltip: '다음 달',
        ),
      ],
    );
  }
}

/// 메인 카드 — "이번 달 실수령 ○○○만원"(net 대표) + 세전·배당·연금 서브.
class _MainCard extends StatelessWidget {
  final int net;
  final int gross;
  final int dividendGross;
  final int pensionGross;
  final bool overThreshold;

  const _MainCard({
    required this.net,
    required this.gross,
    required this.dividendGross,
    required this.pensionGross,
    required this.overThreshold,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '이번 달 실수령',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              if (overThreshold) ...[
                const SizedBox(width: 6),
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.warning),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${CalendarScreenFmt.man(net)}만원',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '세전 ${CalendarScreenFmt.man(gross)}만원 · '
            '배당 ${CalendarScreenFmt.man(dividendGross)}만 + '
            '연금 ${CalendarScreenFmt.man(pensionGross)}만',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          if (overThreshold) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '세금 임계치 초과 — 게이지 탭 확인',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 배당 라인 타일 — 종목명 / 주당×수량 / 금액. 예측이면 흐린 색+"예상" 배지.
class _DividendLineTile extends StatelessWidget {
  final DividendLine line;
  final int? perShare;
  final int? shares;

  const _DividendLineTile({
    required this.line,
    required this.perShare,
    required this.shares,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !line.isConfirmed;
    final nameColor = dimmed ? AppColors.gray400 : AppColors.gray800;
    final amountColor = dimmed ? AppColors.gray400 : AppColors.navy;

    final fmt = NumberFormat('#,###');
    final detail = (perShare != null && shares != null)
        ? '주당 ${fmt.format(perShare)}원 × ${fmt.format(shares)}주'
        : null;

    // 카드(net)와 합산 일치를 위해 라인도 세후로 통일.
    final netAmount = (line.amountGross * (1 - kDividendWithholding)).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.corpName,
                        style: AppTextStyles.bodyLarge.copyWith(color: nameColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (dimmed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gray200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '예상',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.gray600),
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppTextStyles.caption.copyWith(
                      color: dimmed ? AppColors.gray400 : AppColors.gray500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${CalendarScreenFmt.man(netAmount)}만원',
            style: AppTextStyles.numberSmall.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}

/// 빈 월 — "이 달 예정 배당 없음".
class _EmptyDividend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Center(
        child: Text(
          '이 달 예정 배당 없음',
          style: AppTextStyles.body.copyWith(color: AppColors.gray500),
        ),
      ),
    );
  }
}

/// 연금 인출 라인(고정 1개). 연 1,500만원 초과 시 16.5% 절벽 캡션 노출.
class _PensionTile extends StatelessWidget {
  final int pensionNet;
  final int pensionGross;
  final bool overLowRate;

  const _PensionTile({
    required this.pensionNet,
    required this.pensionGross,
    required this.overLowRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance, size: 20, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('연금 인출', style: AppTextStyles.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  '세전 ${CalendarScreenFmt.man(pensionGross)}만원',
                  style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
                ),
                if (overLowRate) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: AppColors.warning),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '연 1,500만원 초과 — 16.5% 적용',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${CalendarScreenFmt.man(pensionNet)}만원',
            style: AppTextStyles.numberSmall.copyWith(color: AppColors.greenDark),
          ),
        ],
      ),
    );
  }
}

/// 연간 배당 요약 카드 — "올해 예상 배당 총 ○○만원 (세후 ○○만원)" + 확정·예측 건수.
/// 예측이 포함되므로 "예상" 단어를 유지한다(단정 금지).
class _YearlyDividendCard extends StatelessWidget {
  final int year;
  final YearlyDividendSummary summary;

  const _YearlyDividendCard({required this.year, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 20, color: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '올해 예상 배당 총 ${CalendarScreenFmt.man(summary.gross)}만원 '
                  '(세후 ${CalendarScreenFmt.man(summary.net)}만원)',
                  style: AppTextStyles.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '확정 ${summary.confirmedCount}건 · 예측 ${summary.predictedCount}건',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.gray500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 연간 12개월 미니 막대 차트 — "은퇴 월급 연봉표".
/// 배당이 특정 월(4월 등)에 몰리는 편중을 한눈에. 막대 높이 ∝ 세후 실수령(totalNet).
/// 막대 탭 → 해당 월로 직접 이동(광고 트리거 없음).
class _YearlyBarChart extends StatelessWidget {
  /// 현재 표시 중인 월(1~12) — 하이라이트 대상.
  final int selectedMonth;

  /// 1~12월 순서의 12개월 현금흐름.
  final List<MonthlyCashflow> months;

  /// 막대 탭 콜백(1~12).
  final void Function(int month) onSelectMonth;

  const _YearlyBarChart({
    required this.selectedMonth,
    required this.months,
    required this.onSelectMonth,
  });

  // 막대 영역 높이 상수.
  static const double _maxBarHeight = 88;
  static const double _minStub = 4;

  @override
  Widget build(BuildContext context) {
    final maxNet =
        months.fold<int>(0, (m, cf) => cf.totalNet > m ? cf.totalNet : m);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('올해 월별 흐름', style: AppTextStyles.h4),
                const SizedBox(width: 6),
                Text(
                  '(세후 기준)',
                  style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _maxBarHeight + 26, // 막대 + 라벨 영역(라벨 높이 여유 포함).
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < months.length; i++)
                  _bar(months[i], i + 1, maxNet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(MonthlyCashflow cf, int month, int maxNet) {
    final isSelected = month == selectedMonth;
    final isZero = cf.totalNet <= 0;

    double height;
    if (maxNet <= 0) {
      height = _minStub; // 전부 0 → 균등 최소 높이.
    } else if (isZero) {
      height = _minStub; // 이 달만 0 → 회색 최소 스텁.
    } else {
      height = _minStub + (_maxBarHeight - _minStub) * (cf.totalNet / maxNet);
    }

    final Color color = isSelected
        ? AppColors.green
        : isZero
            ? AppColors.gray300
            : AppColors.navyLight.withValues(alpha: 0.35);

    return Expanded(
      child: GestureDetector(
        key: ValueKey('yearlyBar_$month'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelectMonth(month),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              key: ValueKey('yearlyBarFill_$month'),
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$month',
              style: AppTextStyles.labelSmall.copyWith(
                color: isSelected ? AppColors.greenDark : AppColors.gray500,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 하단 고지 — 지급월 예상 안내(단정 표기 금지).
class _Notice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.gray400),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '지급월은 예상이며 회사별로 다를 수 있습니다',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
        ),
      ],
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

/// 만원 단위 포맷 헬퍼(위젯 공용).
class CalendarScreenFmt {
  CalendarScreenFmt._();
  static final NumberFormat _fmt = NumberFormat('#,###');
  static String man(int won) => _fmt.format(won ~/ 10000);
}
