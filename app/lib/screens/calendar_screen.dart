import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../services/ad_service.dart';
import '../services/cashflow_engine.dart';
import '../services/tax_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/banner_ad_widget.dart';

/// 달력 상세·차트 필터(화면 로컬). 값: 'all' | 'type:general|isa|pension' |
/// 'acct:{id}'. 상단 합산 카드는 이 값과 무관하게 항상 전체 합산으로 고정된다.
/// autoDispose — 화면을 벗어나면 '전체'로 초기화.
final _calendarFilterProvider =
    StateProvider.autoDispose<String>((ref) => 'all');

/// 라인이 현재 필터에 부합하는지 — accountType/accountId 기준.
bool _lineMatches(DividendLine line, String filter) {
  if (filter == 'all') return true;
  if (filter.startsWith('type:')) {
    return line.accountType.name == filter.substring(5);
  }
  if (filter.startsWith('acct:')) return line.accountId == filter.substring(5);
  return true;
}

/// 필터 적용 후 월 실수령(세후) — 걸러진 배당 라인 amountNet 합.
/// 연금 인출은 '연금' 필터에서만, 이자·재투자는 계좌 소속이 아니므로 'all' 에서만 산입.
int _filteredNet(MonthlyCashflow cf, String filter) {
  if (filter == 'all') return cf.totalNet;
  var net = 0;
  for (final line in cf.lines) {
    if (_lineMatches(line, filter)) net += line.amountNet;
  }
  if (filter == 'type:pension') net += cf.pensionNet;
  return net;
}

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
    final accounts = ref.watch(accountsProvider);
    final interestItems = ref.watch(interestItemsProvider);
    final filter = ref.watch(_calendarFilterProvider);
    // API + 수동 입력 합성 이벤트 merge (합성 연도 = 표시 중인 연도).
    final asyncEvents = ref.watch(combinedEventsProvider(_month.year));

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
        error: (e, _) =>
            _ErrorView(onRetry: () => ref.invalidate(dividendEventsProvider)),
        data: (events) => _buildBody(
          holdings,
          input,
          accounts,
          interestItems,
          filter,
          events,
        ),
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  Widget _buildBody(
    List<Holding> holdings,
    RetirementInput input,
    List<Account> accounts,
    List<InterestItem> interestItems,
    String filter,
    List<DividendEvent> events,
  ) {
    final months = CashflowEngine.buildMonths(
      holdings: holdings,
      events: events,
      input: input,
      from: _month,
      monthCount: 1,
      accounts: accounts,
      interestItems: interestItems,
    );
    final cf = months.first;

    final gauges = CashflowEngine.buildGauges(
      holdings: holdings,
      events: events,
      input: input,
      year: _month.year,
      accounts: accounts,
      interestItems: interestItems,
    );
    // 참고용(건보) 게이지는 메인 경고를 구동하지 않는다 — 금융소득·연금 저율 한도만.
    final overThreshold =
        gauges.financialIncome.ratio > 1.0 || gauges.pensionLowRate.ratio > 1.0;

    // 사적연금 연 인출액이 저율 한도(1,500만원)를 초과하면 전액 16.5% 절벽 적용.
    final pensionOverLowRate =
        input.monthlyPensionWithdrawal * 12 > kPensionLowRateLimit;

    // 연간 배당 요약(예측 포함) — 배당이 특정 월에 몰려 비어 보이는 문제 보완.
    final divSummary = CashflowEngine.yearlyDividendSummary(
      holdings: holdings,
      events: events,
      year: _month.year,
      accounts: accounts,
    );

    // 연간 12개월 현금흐름(세후) — 미니 막대 차트용. 배당 편중을 한눈에 보여준다.
    final yearMonths = CashflowEngine.buildMonths(
      holdings: holdings,
      events: events,
      input: input,
      from: DateTime(_month.year, 1, 1),
      monthCount: 12,
      accounts: accounts,
      interestItems: interestItems,
    );
    // 보유·연금이 전부 0이면(12개월 실수령 모두 0) 차트 미표시(필터 무관 — 전체 기준).
    final showBarChart = yearMonths.any((m) => m.totalNet > 0);
    // 막대 높이는 필터 반영(실수령) — 걸러진 라인 기준 월별 세후 합.
    final netByMonth = [for (final m in yearMonths) _filteredNet(m, filter)];

    // 라인 상세(주당×수량) 재구성용 조회 맵.
    // 수량은 corpName+accountId 복합 키로 조회 — 같은 종목을 일반+ISA 등
    // 두 계좌에 나눠 보유하면 corpName 단일 키는 마지막 holding 으로 덮어써져
    // 두 라인이 같은 수량을 잘못 표시한다(M1). perShare 는 계좌와 무관하게
    // corpName(종목) 단위로 동일하므로 단일 키 유지.
    final sharesByAccount = {
      for (final h in holdings) '${h.corpName}|${h.accountId}': h.shares,
    };
    final perShareByName = {for (final e in events) e.corpName: e.perShare};

    // 상세 리스트·아코디언 = 필터 적용. 상단 카드는 항상 전체(cf) 기준.
    final filteredLines =
        cf.lines.where((l) => _lineMatches(l, filter)).toList();
    final filteredReinvest =
        cf.reinvestLines.where((l) => _lineMatches(l, filter)).toList();
    final filteredReinvestGross =
        filteredReinvest.fold<int>(0, (s, l) => s + l.amountGross);
    // 연금 인출 섹션 — 계좌 소속이 아니므로 '전체'/'연금' 필터에서만 노출.
    // 인출 모드 OFF(스펙 §2·§3)면 필터와 무관하게 타일 자체를 렌더하지 않는다.
    final showPension =
        input.isWithdrawing && (filter == 'all' || filter == 'type:pension');

    return RefreshIndicator(
      onRefresh: () async {
        // 당겨서 새로고침 — 신선 캐시를 무시하고 배당 데이터를 강제 갱신한다.
        ref.read(forceRefreshProvider.notifier).state++;
        await ref.read(dividendEventsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
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
            interestGross: cf.interestGross,
            overThreshold: overThreshold,
          ),
          const SizedBox(height: 12),
          _AccountFilterChips(userAccounts: accounts),
          if (holdings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _YearlyDividendCard(year: _month.year, summary: divSummary),
          ],
          if (showBarChart) ...[
            const SizedBox(height: 12),
            _YearlyBarChart(
              selectedMonth: _month.month,
              netByMonth: netByMonth,
              onSelectMonth: _goToMonth,
            ),
          ],
          const SizedBox(height: 20),
          Text('배당 내역 (세후 기준)', style: AppTextStyles.h4),
          const SizedBox(height: 8),
          if (filteredLines.isEmpty)
            _EmptyDividend()
          else
            ...filteredLines.map(
              (line) => _DividendLineTile(
                line: line,
                perShare: perShareByName[line.corpName],
                shares: sharesByAccount['${line.corpName}|${line.accountId}'],
              ),
            ),
          if (filteredReinvestGross > 0) ...[
            const SizedBox(height: 8),
            _ReinvestAccordion(
              gross: filteredReinvestGross,
              lines: filteredReinvest,
            ),
          ],
          if (showPension) ...[
            const SizedBox(height: 16),
            Text('연금 인출', style: AppTextStyles.h4),
            const SizedBox(height: 8),
            _PensionTile(
              pensionNet: cf.pensionNet,
              pensionGross: cf.pensionGross,
              overLowRate: pensionOverLowRate,
            ),
          ],
          const SizedBox(height: 20),
          _Notice(),
          const SizedBox(height: 40),
        ],
      ),
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
        Text('${month.year}년 ${month.month}월', style: AppTextStyles.h3),
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
  final int interestGross;
  final bool overThreshold;

  const _MainCard({
    required this.net,
    required this.gross,
    required this.dividendGross,
    required this.pensionGross,
    required this.interestGross,
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
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
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
            interestGross > 0
                ? '세전 ${CalendarScreenFmt.man(gross)}만원 · '
                    '배당 ${CalendarScreenFmt.man(dividendGross)}만 + '
                    '연금 ${CalendarScreenFmt.man(pensionGross)}만 + '
                    '이자 ${CalendarScreenFmt.man(interestGross)}만'
                : '세전 ${CalendarScreenFmt.man(gross)}만원 · '
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
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
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
    // 수동 입력 라인은 이 달 금액에서 주당 배당을 역산(지급월별 분할이라 연간값과 다름)
    // 하고 "(직접 입력)" 을 병기한다.
    final isManual = line.source == 'manual';
    final effPerShare = isManual && shares != null && shares! > 0
        ? line.amountGross ~/ shares!
        : perShare;
    final detail = (effPerShare != null && shares != null)
        ? '주당 ${fmt.format(effPerShare)}원 × ${fmt.format(shares)}주'
              '${isManual ? ' (직접 입력)' : ''}'
        : null;

    // 엔진(cashflow_engine)이 계좌 유형별로 이미 정확히 계산한 net 을 그대로
    // 쓴다(일반=원천징수 15.4% 후, ISA·연금=gross 그대로) — 여기서 재계산 금지.
    // 재계산하면 ISA·연금 라인이 일반계좌 공식으로 잘못 과세돼 상단 합산 카드와
    // 어긋난다(2026-07-11 최종 리뷰 C1).
    final netAmount = line.amountNet;

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
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: nameColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (dimmed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gray200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '예상',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.gray600,
                          ),
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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
                ),
                if (overLowRate) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '연 1,500만원 초과 — 16.5% 적용',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                          ),
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
            style: AppTextStyles.numberSmall.copyWith(
              color: AppColors.greenDark,
            ),
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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
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

  /// 1~12월 순서의 월별 세후 실수령(필터 반영). 막대 높이 ∝ 이 값.
  final List<int> netByMonth;

  /// 막대 탭 콜백(1~12).
  final void Function(int month) onSelectMonth;

  const _YearlyBarChart({
    required this.selectedMonth,
    required this.netByMonth,
    required this.onSelectMonth,
  });

  // 막대 영역 높이 상수.
  static const double _maxBarHeight = 88;
  static const double _minStub = 4;

  @override
  Widget build(BuildContext context) {
    final maxNet = netByMonth.fold<int>(
      0,
      (m, net) => net > m ? net : m,
    );

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
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
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
                for (var i = 0; i < netByMonth.length; i++)
                  _bar(netByMonth[i], i + 1, maxNet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(int net, int month, int maxNet) {
    final isSelected = month == selectedMonth;
    final isZero = net <= 0;

    double height;
    if (maxNet <= 0) {
      height = _minStub; // 전부 0 → 균등 최소 높이.
    } else if (isZero) {
      height = _minStub; // 이 달만 0 → 회색 최소 스텁.
    } else {
      height = _minStub + (_maxBarHeight - _minStub) * (net / maxNet);
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(3),
                ),
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

/// 계좌 필터 칩 — [전체 | 일반 | ISA | 연금 | <유저 계좌명…>] 가로 스크롤.
/// 선택은 [_calendarFilterProvider] 에 기록되며 상세 리스트·차트에만 적용된다
/// (상단 합산 카드는 항상 전체 고정).
class _AccountFilterChips extends ConsumerWidget {
  final List<Account> userAccounts;

  const _AccountFilterChips({required this.userAccounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_calendarFilterProvider);

    final chips = <(String, String)>[
      ('전체', 'all'),
      ('일반', 'type:general'),
      ('ISA', 'type:isa'),
      ('연금', 'type:pension'),
      for (final a in userAccounts) (a.name, 'acct:${a.id}'),
    ];

    // Wrap 로 넘치면 다음 줄로 흐른다 — 세로 ListView 외의 Scrollable 을 추가하지
    // 않아(스크롤 테스트 단일 Scrollable 전제 유지) 오버플로를 처리한다.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, value) in chips)
          ChoiceChip(
            label: Text(label),
            selected: selected == value,
            showCheckmark: false,
            onSelected: (_) =>
                ref.read(_calendarFilterProvider.notifier).state = value,
            selectedColor: AppColors.navy,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: selected == value ? AppColors.navy : AppColors.gray200,
            ),
            labelStyle: AppTextStyles.caption.copyWith(
              color: selected == value ? Colors.white : AppColors.gray700,
              fontWeight:
                  selected == value ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

/// 재투자 아코디언 — 연금계좌 배당(과세이연 재투자). 기본 접힘, 보조 톤 제목.
/// reinvestGross 0 이면 [_buildBody] 에서 애초에 렌더하지 않는다.
class _ReinvestAccordion extends StatelessWidget {
  /// 재투자 세전 합(원).
  final int gross;
  final List<DividendLine> lines;

  const _ReinvestAccordion({required this.gross, required this.lines});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    return Material(
      // ListTile 잉크/배경이 상위 Material 에 그려지도록 Container 대신 Material 사용.
      color: AppColors.gray50,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.gray200),
      ),
      child: Theme(
        // ExpansionTile 기본 상·하단 divider 제거.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('reinvestAccordion'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(
            Icons.autorenew,
            size: 20,
            color: AppColors.gray500,
          ),
          title: Text(
            '계좌 내 재투자 +${fmt.format(gross)}원',
            style: AppTextStyles.body.copyWith(color: AppColors.gray600),
          ),
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.corpName,
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.gray700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '+${fmt.format(line.amountGross)}원',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.gray600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              '연금계좌 배당은 인출 전까지 계좌 안에서 재투자됩니다 (과세이연)',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
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

/// 만원 단위 포맷 헬퍼(위젯 공용).
class CalendarScreenFmt {
  CalendarScreenFmt._();
  static final NumberFormat _fmt = NumberFormat('#,###');
  static String man(int won) => _fmt.format(won ~/ 10000);
}
