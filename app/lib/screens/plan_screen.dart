import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/pension_input.dart';
import '../engine/result_narrative.dart';
import '../engine/simulation_result.dart';
import '../engine/withdrawal_optimizer.dart';
import '../providers/app_providers.dart';
import '../services/plan_mapper.dart';
import '../services/review_prompt.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/nps_estimate_sheet.dart';
import '../widgets/plan_accuracy_card.dart';
import '../widgets/settings_button.dart';

/// 계획 탭 — 연금나침반 엔진으로 인출 순서 4가지 전략의 총 세금을 비교한다 (v2, 2026-10-22).
///
/// 입력은 내 자산 탭의 계좌 잔액·월 인출액을 그대로 쓰고, 이 화면에서는 가정(기간·수익률·
/// 연간 인출 목표·국민연금)만 바꾼다. 1위 전략은 "추천"이 아니라 "계산 결과"로 표기한다.
/// 계획 탭 가정 — 탭을 오가도 유지(앱 실행 중 메모리만, 저장하지 않음).
/// 전략 쉬운 이름·한 줄 설명 (v2.3.1 — 엔진 이름 '과세 이연' 등이 어렵다는 피드백).
/// 엔진(연금나침반 이식)의 displayName 은 그대로 두고 화면에서만 바꿔 부른다.
String planStrategyName(String id, String fallback) => switch (id) {
  'defer_taxable' => '세금 붙는 연금은 70세 이후에',
  'tax_free_first' => '세금 없는 돈부터',
  'fill_bracket' => '매년 1,500만원까지 연금 먼저',
  'pension_first' => '연금저축부터 (흔한 방식)',
  _ => fallback,
};

String planStrategyDesc(String id) => switch (id) {
  'defer_taxable' => 'ISA·원금·퇴직금을 먼저 쓰고, 공제받은 연금은 세율이 낮아지는 70세 이후에',
  'tax_free_first' => 'ISA·공제 안 받은 원금부터, 연금은 연 1,500만원 안에서',
  'fill_bracket' => '공제받은 연금을 매년 1,500만원까지 먼저, 모자라면 ISA·원금',
  'pension_first' => '한도를 따지지 않고 연금저축부터 차례로',
  _ => '',
};

final planAssumptionsProvider = StateProvider<PlanAssumptions>(
  (ref) => const PlanAssumptions(),
);

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.onGoToAssets});

  /// 내 자산 탭으로 이동 (잔액이 없을 때 안내 버튼).
  final VoidCallback? onGoToAssets;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _reviewCounted = false;
  late final TextEditingController _targetCtl;
  late final TextEditingController _npsCtl;
  late final TextEditingController _npsAgeCtl;

  PlanAssumptions get _a => ref.read(planAssumptionsProvider);
  set _a(PlanAssumptions v) =>
      ref.read(planAssumptionsProvider.notifier).state = v;

  @override
  void initState() {
    super.initState();
    // 탭을 다시 열면 직전 가정을 입력칸에 되살린다.
    final a = ref.read(planAssumptionsProvider);
    String man(int? won) => won == null ? '' : '${won ~/ 10000}';
    _targetCtl = TextEditingController(text: man(a.annualTargetOverride));
    _npsCtl = TextEditingController(text: man(a.npsMonthly));
    _npsAgeCtl = TextEditingController(text: '${a.npsStartAge ?? 65}');
  }

  @override
  void dispose() {
    _targetCtl.dispose();
    _npsCtl.dispose();
    _npsAgeCtl.dispose();
    super.dispose();
  }

  int? _manToWon(String s) {
    final v = int.tryParse(s.replaceAll(',', '').trim());
    return (v == null || v <= 0) ? null : v * 10000;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(planAssumptionsProvider);
    final accounts = ref.watch(effectiveAccountsProvider);
    final retirement = ref.watch(retirementInputProvider);
    final age = retirement.currentAge;
    final balances = planBalancesFrom(accounts);
    final input = buildPlanInput(
      accounts: accounts,
      currentAge: age,
      assumptions: _a,
      // 국민연금 칸을 비워 둘 때만 내 자산 공적연금으로 대체 (입력 중 깜빡 바뀌지 않게).
      extras: _npsCtl.text.trim().isEmpty
          ? retirement
          : retirement.copyWith(publicPensionMonthly: 0),
    );
    final unknowns = planUnknowns(accounts, retirement);
    final result = input == null ? null : WithdrawalOptimizer.optimize(input);
    // 리뷰 요청 판정은 화면을 열 때 한 번만 (계산 칩을 바꿀 때마다 세지 않게).
    if (result != null && !_reviewCounted) {
      _reviewCounted = true;
      final savings = result.savings;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ReviewPrompt.onPlanViewed(savings),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('계획'),
        actions: const [SettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (balances.total <= 0)
            _EmptyCard(onGoToAssets: widget.onGoToAssets)
          else ...[
            if (result != null && input != null) ...[
              _HeroCard(
                result: result,
                years: _a.years,
                basicAssumption: unknowns.isNotEmpty,
              ),
              if (unknowns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${unknowns.join('·')}은(는) 기본값으로 계산 · 아래에서 넣으면 더 정확해요',
                  key: const Key('plan_unknown_note'),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _NarrativeLine(
                result: result,
                inputYears: _a.years,
                input: input,
              ),
              const SizedBox(height: 18),
              _section('꺼내는 순서별 ${_a.years}년 세금'),
              const SizedBox(height: 8),
              ..._strategyTiles(result),
              const SizedBox(height: 4),
              _YearlyTable(result: result),
            ] else
              _InfoCard(
                text:
                    '월 인출액이 없어 계산할 수 없어요. 아래 "연간 인출 목표"를 입력하거나 '
                    '내 자산 탭에서 연금·ISA 계좌의 월 인출액을 넣어 주세요.',
              ),
            const SizedBox(height: 20),
            const PlanAccuracyCard(),
            const SizedBox(height: 20),
            _AssumptionsTile(
              summary:
                  '${_a.years}년 · 수익률 연 ${(_a.returnRate * 100).round()}%'
                  '${_a.npsMonthly != null ? ' · 국민연금 포함' : ''}',
              child: _assumptions(balances),
            ),
            const SizedBox(height: 16),
            Text(
              '2026년 세법 기준 추정 · 투자 권유 아님 · 공단과 무관한 민간 계산기',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
            ),
          ],
        ],
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  /// 섹션 제목 — 화면 공통 규칙(v2.3.1): 모든 탭이 h4 하나로.
  Widget _section(String t) => Text(t, style: AppTextStyles.h4);

  List<Widget> _strategyTiles(SimulationResult r) {
    final sorted = [...r.outcomes]
      ..sort((a, b) => a.totalTax.compareTo(b.totalTax));
    return [
      for (final o in sorted)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: o.strategyId == r.optimalStrategyId
                ? AppColors.goldSoft
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: o.strategyId == r.optimalStrategyId
                  ? AppColors.gold
                  : AppColors.gray200,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          planStrategyName(o.strategyId, o.strategyName),
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.navy,
                          ),
                        ),
                        if (o.strategyId == r.optimalStrategyId)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '세금 가장 적음',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.surface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planStrategyDesc(o.strategyId),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.gray500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${CurrencyFormat.man(o.totalTax)}만원',
                style: AppTextStyles.amount,
              ),
            ],
          ),
        ),
    ];
  }

  Widget _assumptions(PlanBalances b) {
    final publicPension = ref
        .read(retirementInputProvider)
        .publicPensionMonthly;
    Widget chips<T>(
      String label,
      List<(T, String)> opts,
      T selected,
      void Function(T) onSel,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray600),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                for (final (v, t) in opts)
                  ChoiceChip(
                    label: Text(t),
                    selected: v == selected,
                    selectedColor: AppColors.goldSoft,
                    side: BorderSide(
                      color: v == selected ? AppColors.gold : AppColors.gray200,
                    ),
                    onSelected: (_) => onSel(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final defaultTarget = b.monthlyWithdrawal * 12;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '연금저축 ${CurrencyFormat.eokMan(b.pensionSavings)} · IRP ${CurrencyFormat.eokMan(b.irp)} · '
            'ISA ${CurrencyFormat.eokMan(b.isa)} (내 자산 기준)',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.gray600,
              fontFeatures: AppTextStyles.tabular,
            ),
          ),
          const SizedBox(height: 12),
          chips<int>(
            '기간',
            const [(20, '20년'), (25, '25년'), (30, '30년')],
            _a.years,
            (v) => setState(() => _a = _a.copyWith(years: v)),
          ),
          chips<double>(
            '수익률',
            const [(0.03, '연 3%'), (0.04, '연 4%'), (0.05, '연 5%')],
            _a.returnRate,
            (v) => setState(() => _a = _a.copyWith(returnRate: v)),
          ),
          TextField(
            key: const Key('plan_target'),
            controller: _targetCtl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: InputDecoration(
              labelText: '연간 인출 목표 (만원)',
              helperText: defaultTarget > 0
                  ? '비워 두면 내 자산의 월 인출액 기준 연 ${CurrencyFormat.man(defaultTarget)}만원'
                  : '내 자산에 월 인출액이 없으면 여기에 입력하세요',
            ),
            onChanged: (s) => setState(() {
              final w = _manToWon(s);
              _a = w == null
                  ? _a.copyWith(clearAnnualTarget: true)
                  : _a.copyWith(annualTargetOverride: w);
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('plan_nps'),
                  controller: _npsCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: const InputDecoration(
                    labelText: '국민연금 월 예상액 (만원, 선택)',
                  ),
                  onChanged: (_) => _syncNps(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _npsAgeCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: const InputDecoration(labelText: '개시 나이'),
                  onChanged: (_) => _syncNps(),
                ),
              ),
            ],
          ),
          if (_npsCtl.text.trim().isEmpty && publicPension > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '비워 두면 내 자산의 공적연금 월 ${CurrencyFormat.man(publicPension)}만원을 써요',
                key: const Key('plan_nps_from_assets'),
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('plan_nps_estimate'),
              onPressed: () async {
                final r = await showNpsEstimateSheet(context);
                if (r == null || !mounted) return;
                _npsCtl.text = '${r.monthly ~/ 10000}';
                _npsAgeCtl.text = '${r.startAge}';
                _syncNps();
              },
              child: const Text('국민연금 금액을 모르면 추정하기'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _syncNps() {
    final m = _manToWon(_npsCtl.text);
    final age = int.tryParse(_npsAgeCtl.text.trim());
    setState(() {
      // 개시 나이를 고쳐 치는 도중(예: "6")엔 엔진 범위(50~100) 밖이라 국민연금 가정만 뺀다.
      _a = (m == null || age == null || age < 50 || age > 100)
          ? _a.copyWith(clearNps: true)
          : _a.copyWith(npsMonthly: m, npsStartAge: age);
    });
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.result,
    required this.years,
    this.basicAssumption = false,
  });
  final SimulationResult result;
  final int years;

  /// 정확도 입력에 '모름'이 남아 있으면 "기본 가정" 비교라고 밝힌다 (단정 금지).
  final bool basicAssumption;

  @override
  Widget build(BuildContext context) {
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
            basicAssumption
                ? '연금저축·IRP·ISA 꺼내는 순서 중 세금이 가장 적은 방법 (기본 가정)'
                : '연금저축·IRP·ISA 꺼내는 순서 중 세금이 가장 적은 방법',
            style: AppTextStyles.label.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 6),
          Text(
            planStrategyName(
              result.optimalStrategyId,
              result.optimalStrategyName,
            ),
            style: AppTextStyles.h2.copyWith(
              color: AppColors.navy,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kv(
                  '$years년 동안 세금',
                  '${CurrencyFormat.man(result.totalTaxOptimal)}만원',
                  AppColors.navy,
                ),
              ),
              Expanded(
                child: _kv(
                  '흔한 방식보다 적게',
                  '${CurrencyFormat.man(result.savings)}만원',
                  AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('plan_share'),
              onPressed: () => SharePlus.instance.share(
                ShareParams(text: planShareText(result, years)),
              ),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('결과 공유'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: AppTextStyles.caption.copyWith(color: AppColors.gray500)),
      const SizedBox(height: 2),
      Text(v, style: AppTextStyles.amount.copyWith(color: c, fontSize: 17)),
    ],
  );
}

class _NarrativeLine extends StatelessWidget {
  const _NarrativeLine({
    required this.result,
    required this.inputYears,
    required this.input,
  });
  final SimulationResult result;
  final int inputYears;
  final PensionInput input;

  @override
  Widget build(BuildContext context) {
    final n = computeWithdrawalNarrative(result, input);
    final text = n.depleted
        ? '계산상 월 ${CurrencyFormat.man(n.monthlyWithdrawal)}만원을 ${n.fundedYears}년간 쓸 수 있고, '
              '${n.depletionAge}세쯤 잔액이 모자라기 시작해요.'
        : '계산상 월 ${CurrencyFormat.man(n.monthlyWithdrawal)}만원을 $inputYears년 내내 쓸 수 있어요.';
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        color: n.depleted ? AppColors.warning : AppColors.gray700,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({this.onGoToAssets});
  final VoidCallback? onGoToAssets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '연금 계좌 잔액을 넣으면\n인출 순서별 세금을 비교해 드려요',
            style: AppTextStyles.h3.copyWith(
              fontFamily: AppTextStyles.serif,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '내 자산 탭에 잔액·월 인출액을 넣으면 인출 순서 4가지의 세금을 비교해요',
            style: AppTextStyles.body.copyWith(color: AppColors.gray600),
          ),
          if (onGoToAssets != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onGoToAssets,
              child: const Text('내 자산 입력하기'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.gray200),
    ),
    child: Text(
      text,
      style: AppTextStyles.body.copyWith(color: AppColors.gray600),
    ),
  );
}

/// 결과 공유 문구 — 총자산·잔액은 넣지 않는다 (개인 자산 노출 방지).
String planShareText(SimulationResult r, int years) =>
    '은퇴월급 계산 결과\n'
    '세금이 가장 적은 인출 순서: '
    '${planStrategyName(r.optimalStrategyId, r.optimalStrategyName)}\n'
    '$years년 세금 ${CurrencyFormat.man(r.totalTaxOptimal)}만원 · '
    '흔한 방식보다 ${CurrencyFormat.man(r.savings)}만원 적음\n'
    '(현행 세법 기준 추정, 투자 권유 아님)\n'
    'https://play.google.com/store/apps/details?id=com.quantlog.retirepaycheck';

/// 연도별 인출·세금 표 (1위 방식) — 연금나침반 연도별 상세 이식, 접힌 상태가 기본.
class _YearlyTable extends StatelessWidget {
  const _YearlyTable({required this.result});

  final SimulationResult result;

  @override
  Widget build(BuildContext context) {
    final rows = result.schedule;
    TextStyle num0([Color? c]) => AppTextStyles.caption.copyWith(
      fontFeatures: AppTextStyles.tabular,
      color: c ?? AppColors.gray800,
    );
    Widget cell(
      String t, {
      bool head = false,
      TextAlign align = TextAlign.right,
    }) => Expanded(
      child: Text(
        t,
        textAlign: align,
        style: head
            ? AppTextStyles.labelSmall.copyWith(color: AppColors.gray500)
            : num0(),
      ),
    );
    return Material(
      key: const Key('plan_yearly'),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.gray200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('plan_yearly_tile'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            '해마다 얼마 꺼내고 세금은 얼마? (표)',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          ),
          children: [
            Row(
              children: [
                cell('나이', head: true, align: TextAlign.left),
                cell('인출', head: true),
                cell('세금', head: true),
                cell('국민연금', head: true),
              ],
            ),
            const SizedBox(height: 4),
            for (final y in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    cell('${y.age}세', align: TextAlign.left),
                    cell('${CurrencyFormat.man(y.totalAmount)}만'),
                    cell('${CurrencyFormat.man(y.totalTax)}만'),
                    cell(
                      y.npsAnnualAmount > 0
                          ? '${CurrencyFormat.man(y.npsAnnualAmount)}만'
                          : '-',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '연 단위 · 국민연금은 연금계좌 인출과 따로 들어오는 돈이라 세금 계산에서 뺐어요.',
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 계산 조건(기간·수익률·인출 목표·국민연금) — 기본 접힘. 처음 보는 사람에겐 결과만 보이게.
class _AssumptionsTile extends StatelessWidget {
  const _AssumptionsTile({required this.summary, required this.child});
  final String summary;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('plan_assumptions_tile'),
    color: AppColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.gray200),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '계산 조건 바꾸기',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          summary,
          style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
        ),
        children: [child],
      ),
    ),
  );
}
