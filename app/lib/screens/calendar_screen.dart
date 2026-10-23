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
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/settings_button.dart';

/// 배당금 보기의 계좌 필터(화면 로컬). 값: 'all' | 'type:general|isa|pension' |
/// 'acct:{id}'. 상단 카드는 이 값과 무관하게 항상 그 달 전체로 고정된다.
/// autoDispose — 화면을 벗어나면 '전체'로 초기화.
final _calendarFilterProvider = StateProvider.autoDispose<String>(
  (ref) => 'all',
);

/// 라인이 현재 필터에 부합하는지 — accountType/accountId 기준.
bool _lineMatches(DividendLine line, String filter) {
  if (filter == 'all') return true;
  if (filter.startsWith('type:')) {
    return line.accountType.name == filter.substring(5);
  }
  if (filter.startsWith('acct:')) return line.accountId == filter.substring(5);
  return true;
}

/// 그 달 배당 세전 합 — 일반계좌 + ISA·연금 계좌(필터 반영).
int _dividendsGross(MonthlyCashflow m, String filter) =>
    [...m.lines, ...m.reinvestLines]
        .where((l) => _lineMatches(l, filter))
        .fold<int>(0, (s, l) => s + l.amountGross);

/// 화면2 — 은퇴 월급 달력 (메인).
///
/// v2.3 보기 3분할([CalendarView]):
/// - 총계 = 세후 은퇴 월급(일반계좌 배당 + 연금·ISA 인출 + 이자). ISA·연금 계좌 배당은
///   계좌에 남으므로 빠지고, 하단에 한 줄로 알린다.
/// - 배당금 = 세전 배당 전체(ISA·연금 계좌 포함, 계좌 이름 배지).
/// - 연금 = 계좌별 인출.
///
/// 상단 카드는 "{N}월" — 막대를 누르면 그 달로 바뀐다("이번 달"이 바뀌는 혼란 방지).
/// 연간 합계는 막대 차트 머리에 둔다.
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
    // 월 넘김 3회당 1회 + 직전 광고 3분 경과 시에만 전면 광고(ad_service).
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
    // 필터 칩은 유저 계좌만 노출(화면 로컬 선택 UI) — 엔진 호출은 기본 계좌
    // 오버라이드까지 합산한 effectiveAccountsProvider 를 사용한다(v3 배선).
    final userAccounts = ref.watch(accountsProvider);
    final effectiveAccounts = ref.watch(effectiveAccountsProvider);
    final interestItems = ref.watch(interestItemsProvider);
    final view = ref.watch(calendarViewProvider);
    // 필터는 배당금 보기에서만 쓴다 — 다른 보기는 항상 전체.
    final filter = view == CalendarView.dividends
        ? ref.watch(_calendarFilterProvider)
        : 'all';
    // API + 수동 입력 합성 이벤트 merge (합성 연도 = 표시 중인 연도).
    final asyncEvents = ref.watch(combinedEventsProvider(_month.year));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('은퇴월급'),
        actions: const [SettingsButton()],
      ),
      body: asyncEvents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _ErrorView(onRetry: () => ref.invalidate(dividendEventsProvider)),
        data: (events) => _buildBody(
          holdings,
          input,
          userAccounts,
          effectiveAccounts,
          interestItems,
          filter,
          view,
          events,
        ),
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  Widget _buildBody(
    List<Holding> holdings,
    RetirementInput input,
    List<Account> userAccounts,
    List<Account> effectiveAccounts,
    List<InterestItem> interestItems,
    String filter,
    CalendarView view,
    List<DividendEvent> events,
  ) {
    final yearMonths = CashflowEngine.buildMonths(
      holdings: holdings,
      events: events,
      input: input,
      from: DateTime(_month.year, 1, 1),
      monthCount: 12,
      accounts: effectiveAccounts,
      interestItems: interestItems,
    );
    final cf = yearMonths[_month.month - 1];

    final gauges = CashflowEngine.buildGauges(
      holdings: holdings,
      events: events,
      input: input,
      year: _month.year,
      accounts: effectiveAccounts,
      interestItems: interestItems,
    );
    // 참고용(건보) 게이지는 메인 경고를 구동하지 않는다 — 금융소득·연금 저율 한도만.
    final overThreshold =
        gauges.financialIncome.ratio > 1.0 || gauges.pensionLowRate.ratio > 1.0;

    // 사적연금 그 해 실제 인출액이 저율 한도(1,500만원)를 넘으면 전액 16.5% 절벽.
    // 세금 탭 게이지(buildGauges.pensionLowRate — 개시월 반영 개월 수)를 그대로 쓴다.
    // 월 인출 × 12 로 따로 재면 연중 개시 때 화면끼리 판정이 어긋난다(v2.3 리뷰 I1).
    final pensionOverLowRate = gauges.pensionLowRate.ratio > 1.0;

    // 막대 = 보기별 월 금액. 총계·연금은 세후, 배당금은 세전(필터 반영).
    final byMonth = [
      for (final m in yearMonths)
        switch (view) {
          // 총계 = 모든 계좌 배당 + 연금 + 이자 (연금계좌·ISA 배당은 세금이 꺼낼 때라 그대로).
          CalendarView.total => m.totalNet + m.reinvestGross,
          CalendarView.dividends => _dividendsGross(m, filter),
          CalendarView.pension => m.pensionNet,
        },
    ];
    final yearTotal = byMonth.fold<int>(0, (s, v) => s + v);
    // 차트 표시 여부는 필터 무관 — 칩을 바꿔 0원이 돼도 차트가 사라져 화면이 튀지 않게.
    final showChart = switch (view) {
      CalendarView.dividends => yearMonths.any(
        (m) => _dividendsGross(m, 'all') > 0,
      ),
      _ => yearTotal > 0,
    };

    // 배당금 보기 캡션의 확정·예상 건수(필터 '전체'일 때만 — 엔진 요약은 필터 미반영).
    final divSummary = CashflowEngine.yearlyDividendSummary(
      holdings: holdings,
      events: events,
      year: _month.year,
      accounts: effectiveAccounts,
      includeInAccount: true,
    );

    final accountById = {for (final a in effectiveAccounts) a.id: a};
    // 라인 상세(주당×수량). 수량은 corpName+accountId 복합 키 — 같은 종목을 두 계좌에
    // 나눠 보유해도 라인마다 제 수량을 보여 준다(M1). perShare 는 종목 단위로 동일.
    final sharesByAccount = {
      for (final h in holdings) '${h.corpName}|${h.accountId}': h.shares,
    };
    final perShareByName = {for (final e in events) e.corpName: e.perShare};
    Widget lineTile(DividendLine line, int amount, {String? badge}) =>
        _DividendLineTile(
          line: line,
          amount: amount,
          perShare: perShareByName[line.corpName],
          shares: sharesByAccount['${line.corpName}|${line.accountId}'],
          badge: badge,
        );

    return RefreshIndicator(
      onRefresh: () async {
        // 당겨서 새로고침 — 신선 캐시를 무시하고 배당 데이터를 강제 갱신한다.
        ref.read(forceRefreshProvider.notifier).state++;
        // 화면이 실제 소비하는 combinedEventsProvider 를 await — 화면 데이터
        // rebuild 완료까지 스피너 유지(dividendEventsProvider 만 기다리면 옛 데이터 잔존).
        await ref.read(combinedEventsProvider(_month.year).future);
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<CalendarView>(
              key: const ValueKey('calendarViewToggle'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CalendarView.total, label: Text('총계')),
                ButtonSegment(
                  value: CalendarView.dividends,
                  label: Text('배당금'),
                ),
                ButtonSegment(value: CalendarView.pension, label: Text('연금')),
              ],
              selected: {view},
              onSelectionChanged: (v) =>
                  ref.read(calendarViewProvider.notifier).set(v.first),
            ),
          ),
          const SizedBox(height: 12),
          _MainCard(
            view: view,
            month: _month.month,
            cf: cf,
            overThreshold: overThreshold,
          ),
          if (view == CalendarView.dividends) ...[
            const SizedBox(height: 12),
            _AccountFilterChips(userAccounts: userAccounts),
          ],
          if (showChart) ...[
            const SizedBox(height: 12),
            _YearlyBarChart(
              title: switch (view) {
                CalendarView.total => '올해 총계',
                CalendarView.dividends => '올해 배당',
                CalendarView.pension => '올해 연금',
              },
              total: yearTotal,
              caption: view == CalendarView.dividends
                  ? filter == 'all'
                        ? '세전 · 확정 ${divSummary.confirmedCount}건 · '
                              '예상 ${divSummary.predictedCount}건'
                        : '세전'
                  : '세후',
              selectedMonth: _month.month,
              byMonth: byMonth,
              onSelectMonth: _goToMonth,
            ),
          ],
          const SizedBox(height: 20),
          ...switch (view) {
            CalendarView.total => _totalSection(
              cf,
              pensionOverLowRate,
              lineTile,
            ),
            CalendarView.dividends => _dividendSection(
              cf,
              filter,
              accountById,
              lineTile,
            ),
            CalendarView.pension => _pensionSection(
              cf,
              input,
              effectiveAccounts,
              pensionOverLowRate,
            ),
          },
          const SizedBox(height: 20),
          const _Notice('지급월은 예상이며 회사별로 다를 수 있어요'),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// 총계 — 그 달 생기는 돈(세후): 모든 계좌 배당 · 연금 인출 · 이자.
  List<Widget> _totalSection(
    MonthlyCashflow cf,
    bool pensionOverLowRate,
    Widget Function(DividendLine, int, {String? badge}) lineTile,
  ) {
    final hasAny =
        cf.lines.isNotEmpty ||
        cf.reinvestLines.isNotEmpty ||
        cf.pensionGross > 0 ||
        cf.interestNet > 0;
    return [
      Text('${cf.month.month}월 내역 (세후)', style: AppTextStyles.h4),
      const SizedBox(height: 8),
      if (!hasAny) const _EmptyMonth('이 달 들어오는 돈 없음'),
      for (final line in cf.lines) lineTile(line, line.amountNet),
      // 연금계좌·ISA 배당 — 세금은 꺼낼 때라 지금 금액 그대로, 계좌 이름 배지.
      for (final line in cf.reinvestLines)
        lineTile(
          line,
          line.amountGross,
          badge: line.accountType == AccountType.isa ? 'ISA' : '연금계좌',
        ),
      if (cf.pensionGross > 0)
        _SimpleTile(
          icon: Icons.account_balance,
          title: '연금 인출',
          subtitle: '세전 ${CalendarScreenFmt.man(cf.pensionGross)}만원',
          warning: pensionOverLowRate ? '연 1,500만원 초과 — 16.5% 적용' : null,
          amount: cf.pensionNet,
        ),
      if (cf.interestNet > 0)
        _SimpleTile(
          icon: Icons.savings_outlined,
          title: '이자',
          subtitle: '세전 ${CalendarScreenFmt.man(cf.interestGross)}만원',
          amount: cf.interestNet,
        ),
    ];
  }

  /// 배당금 — 그 달 배당 전체(세전). ISA·연금 계좌 배당엔 계좌 이름 배지.
  List<Widget> _dividendSection(
    MonthlyCashflow cf,
    String filter,
    Map<String, Account> accountById,
    Widget Function(DividendLine, int, {String? badge}) lineTile,
  ) {
    final lines = [
      ...cf.lines,
      ...cf.reinvestLines,
    ].where((l) => _lineMatches(l, filter)).toList();
    final hasInAccount = lines.any((l) => l.accountType != AccountType.general);

    return [
      Text('${cf.month.month}월 배당 (세전)', style: AppTextStyles.h4),
      const SizedBox(height: 8),
      if (lines.isEmpty) const _EmptyMonth('이 달 예정 배당 없음'),
      for (final line in lines)
        lineTile(
          line,
          line.amountGross,
          badge: line.accountType == AccountType.general
              ? null
              : accountById[line.accountId]?.name ??
                    (line.accountType == AccountType.isa ? 'ISA' : '연금계좌'),
        ),
      if (hasInAccount) ...[
        const SizedBox(height: 4),
        const _Notice('연금계좌·ISA 배당은 꺼내기 전까지 계좌에 남아요'),
      ],
    ];
  }

  /// 연금 — 계좌별 월 인출(세전) + 1,500만 절벽 안내.
  List<Widget> _pensionSection(
    MonthlyCashflow cf,
    RetirementInput input,
    List<Account> accounts,
    bool pensionOverLowRate,
  ) {
    final withdrawing = [
      for (final a in accounts)
        if (a.type != AccountType.general &&
            a.withdrawalActive &&
            a.monthlyWithdrawal > 0)
          a,
    ];
    final start = input.withdrawalStartMonth;
    final String? emptyText = withdrawing.isEmpty
        ? "인출 중인 계좌가 없어요\n내 자산 탭에서 현금성 잔액과 '인출 개시'를 확인하세요"
        : cf.pensionGross == 0 && start != null
        ? '${start.year}년 ${start.month}월부터 인출해요'
        : null;

    return [
      Text('${cf.month.month}월 계좌별 인출 (세전)', style: AppTextStyles.h4),
      const SizedBox(height: 8),
      if (emptyText != null)
        _EmptyMonth(emptyText)
      else ...[
        for (final a in withdrawing)
          _SimpleTile(
            icon: Icons.account_balance,
            title: a.name,
            subtitle: a.type == AccountType.isa ? '비과세(한도 내)' : '연금소득세 대상',
            amount: a.monthlyWithdrawal,
          ),
        if (pensionOverLowRate) ...[
          const SizedBox(height: 4),
          const _Notice('연금저축·IRP 인출이 연 1,500만원을 넘어 전액 16.5% 적용', warn: true),
        ],
      ],
    ];
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

/// 메인 카드 — "{N}월 은퇴 월급/배당금/연금" 큰 숫자 + 한 줄 내역.
class _MainCard extends StatelessWidget {
  final CalendarView view;
  final int month;
  final MonthlyCashflow cf;
  final bool overThreshold;

  const _MainCard({
    required this.view,
    required this.month,
    required this.cf,
    required this.overThreshold,
  });

  static String _m(int won) => CalendarScreenFmt.man(won);

  @override
  Widget build(BuildContext context) {
    // v2.3.1: 세 탭의 숫자가 맞물리게 — 총계 = 배당금 탭 '통장 입금' + 연금 탭 '통장 입금'
    // (+ 이자). 각 항목을 천원 단위로 먼저 반올림하고 큰 숫자는 그 합으로 보여 줘
    // 화면에 보이는 숫자끼리 더하면 정확히 맞는다.
    final divNet = _r(cf.dividendNet);
    final divTax = _r(cf.dividendGross) - divNet;
    final inAccount = _r(cf.reinvestGross);
    final penNet = _r(cf.pensionNet);
    final penTax = _r(cf.pensionGross) - penNet;
    final interest = _r(cf.interestNet);

    final (
      String title,
      int amount,
      List<_Row> rows,
      String? note,
    ) = switch (view) {
      CalendarView.total => (
        '$month월 총계 (세후)',
        divNet + inAccount + penNet + interest,
        [
          _Row('배당금 (모든 계좌)', divNet + inAccount),
          _Row('연금', penNet),
          if (interest > 0) _Row('이자', interest),
          _Row(
            '이 중 통장 입금',
            divNet + penNet + interest,
            strong: true,
            separated: true,
          ),
        ],
        inAccount > 0
            ? '연금계좌·ISA 배당 ${_m(inAccount)}만원은 계좌에 쌓여요 (세금은 꺼낼 때)'
            : null,
      ),
      CalendarView.dividends => (
        '$month월 배당금 (세전)',
        divNet + divTax + inAccount,
        [
          if (divNet > 0) _Row('통장 입금 (일반계좌, 세후)', divNet, strong: true),
          if (divTax > 0) _Row('배당소득세 15.4%', divTax),
          if (inAccount > 0) _Row('연금계좌·ISA에 쌓임 (세금은 꺼낼 때)', inAccount),
        ],
        divNet + divTax + inAccount == 0 ? '이 달 배당 없음' : null,
      ),
      CalendarView.pension => (
        '$month월 연금 통장 입금 (세후)',
        penNet,
        [
          if (penNet + penTax > 0) _Row('꺼내는 돈 (세전)', penNet + penTax),
          if (penTax > 0) _Row('연금소득세', -penTax),
        ],
        penNet == 0 ? '이 달 인출 없음' : null,
      ),
    };

    // v2 프라이빗 뱅킹: 아이보리 카드 + 골드 헤어라인, 큰 금액은 명조.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
          Row(
            children: [
              Text(
                title,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.gray500,
                  letterSpacing: 0.3,
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
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _m(amount),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.serif,
                    fontFeatures: AppTextStyles.tabular,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    height: 1.1,
                  ),
                ),
                const TextSpan(
                  text: ' 만원',
                  style: TextStyle(
                    fontFamily: AppTextStyles.serif,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          for (final row in rows) ...[
            if (row.separated) const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: row.strong ? AppColors.navy : AppColors.gray600,
                        fontWeight: row.strong
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    '${row.amount < 0 ? '−' : ''}${_m(row.amount.abs())}만',
                    style: TextStyle(
                      fontSize: 14,
                      fontFeatures: AppTextStyles.tabular,
                      color: row.strong ? AppColors.navy : AppColors.gray600,
                      fontWeight: row.strong
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
            ),
          ],
          if (overThreshold) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '세금 문턱 초과 — 세금 탭 확인',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
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

  /// 천원 단위 반올림(원) — 화면 표기 단위(0.1만원)와 같은 정밀도.
  static int _r(int won) => (won / 1000).round() * 1000;
}

/// 메인 카드 내역 한 줄.
class _Row {
  final String label;
  final int amount;
  final bool strong;

  /// 위에 구분선 — "이 중 통장 입금" 처럼 합계의 일부를 따로 보여 줄 때.
  final bool separated;

  const _Row(
    this.label,
    this.amount, {
    this.strong = false,
    this.separated = false,
  });
}

/// 배당 라인 타일 — 종목명(+계좌 배지) / 주당×수량 / 금액. 예측이면 흐린 색+"예상" 배지.
class _DividendLineTile extends StatelessWidget {
  final DividendLine line;

  /// 표시 금액 — 엔진이 계좌 유형별로 이미 계산한 값(총계=amountNet, 배당금=amountGross).
  /// 여기서 세금을 재계산하지 않는다(ISA·연금 라인 과세 오표시 방지 — 2026-07-11 C1).
  final int amount;
  final int? perShare;
  final int? shares;

  /// ISA·연금 계좌 라인의 계좌 이름 배지(일반계좌는 null).
  final String? badge;

  const _DividendLineTile({
    required this.line,
    required this.amount,
    this.perShare,
    this.shares,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final dimmed = !line.isConfirmed;
    final nameColor = dimmed ? AppColors.gray400 : AppColors.gray800;
    final amountColor = dimmed ? AppColors.gray400 : AppColors.navy;

    final fmt = NumberFormat('#,###');
    // 수동 입력 라인은 이 달 금액에서 주당 배당을 역산(지급월별 분할이라 연간값과 다름).
    final isManual = line.source == 'manual';
    final effPerShare = isManual && shares != null && shares! > 0
        ? line.amountGross ~/ shares!
        : perShare;
    final detail = (effPerShare != null && shares != null)
        ? '주당 ${fmt.format(effPerShare)}원 × ${fmt.format(shares)}주'
              '${isManual ? ' (직접 입력)' : ''}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
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
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      _Badge(badge!, color: AppColors.goldSoft),
                    ],
                    if (dimmed) ...[
                      const SizedBox(width: 8),
                      const _Badge('예상', color: AppColors.gray200),
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
            '${CalendarScreenFmt.man(amount)}만원',
            style: AppTextStyles.numberSmall.copyWith(color: amountColor),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.gray700),
      ),
    );
  }
}

/// 빈 달 안내 칸.
class _EmptyMonth extends StatelessWidget {
  final String text;

  const _EmptyMonth(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: AppColors.gray500),
      ),
    );
  }
}

/// 연금 인출·이자·계좌별 인출 공용 타일 — 아이콘 / 제목·부제 / 금액.
class _SimpleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? warning;
  final int amount;

  const _SimpleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
                ),
                if (warning != null) ...[
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
                          warning!,
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
            '${CalendarScreenFmt.man(amount)}만원',
            style: AppTextStyles.numberSmall.copyWith(
              color: AppColors.greenDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// 연간 12개월 막대 차트 — 머리에 연간 합계("올해 배당 7,698만원"), 아래 작은 캡션.
/// 막대 탭 → 해당 월로 직접 이동(광고 트리거 없음) — 위 카드·내역이 그 달로 바뀐다.
class _YearlyBarChart extends StatelessWidget {
  /// "올해 은퇴 월급" / "올해 배당" / "올해 연금".
  final String title;

  /// 연간 합계(원) — 막대 합과 같다.
  final int total;

  /// 기준 캡션 — "세후" / "세전 · 확정 3건 · 예상 9건".
  final String caption;

  /// 현재 표시 중인 월(1~12) — 하이라이트 대상.
  final int selectedMonth;

  /// 1~12월 순서의 월별 금액. 막대 높이 ∝ 이 값.
  final List<int> byMonth;

  /// 막대 탭 콜백(1~12).
  final void Function(int month) onSelectMonth;

  const _YearlyBarChart({
    required this.title,
    required this.total,
    required this.caption,
    required this.selectedMonth,
    required this.byMonth,
    required this.onSelectMonth,
  });

  static const double _maxBarHeight = 88;
  static const double _minStub = 4;

  @override
  Widget build(BuildContext context) {
    final maxValue = byMonth.fold<int>(0, (m, v) => v > m ? v : m);

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 한 줄 고정 — 좁은 화면에선 줄바꿈 대신 살짝 줄인다.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$title ${CalendarScreenFmt.man(total)}만원',
                    key: const ValueKey('yearlyTotal'),
                    maxLines: 1,
                    style: AppTextStyles.h4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$caption · 막대를 누르면 그 달 내역',
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
                for (var i = 0; i < byMonth.length; i++)
                  _bar(byMonth[i], i + 1, maxValue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(int value, int month, int maxValue) {
    final isSelected = month == selectedMonth;
    final isZero = value <= 0;

    final double height = maxValue <= 0 || isZero
        ? _minStub
        : _minStub + (_maxBarHeight - _minStub) * (value / maxValue);

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

/// 계좌 필터 칩 — [전체 | 일반 | ISA | 연금 | <유저 계좌명…>]. 배당금 보기 전용.
/// 선택은 [_calendarFilterProvider] 에 기록되며 내역·차트에만 적용된다
/// (상단 카드는 항상 그 달 전체 고정).
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
      ('연금계좌', 'type:pension'),
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
              fontWeight: selected == value ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

/// 작은 안내 한 줄(ⓘ). [warn] 이면 경고색.
class _Notice extends StatelessWidget {
  final String text;
  final bool warn;

  const _Notice(this.text, {this.warn = false});

  @override
  Widget build(BuildContext context) {
    final color = warn ? AppColors.warning : AppColors.gray500;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warn ? Icons.warning_amber_rounded : Icons.info_outline,
          size: 16,
          color: warn ? AppColors.warning : AppColors.gray400,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(color: color),
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
  static String man(int won) => CurrencyFormat.man(won);
}
