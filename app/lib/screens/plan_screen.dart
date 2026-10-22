import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/pension_input.dart';
import '../engine/result_narrative.dart';
import '../engine/simulation_result.dart';
import '../engine/withdrawal_optimizer.dart';
import '../providers/app_providers.dart';
import '../services/plan_mapper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/plan_accuracy_card.dart';

/// 계획 탭 — 연금나침반 엔진으로 인출 순서 4가지 전략의 총 세금을 비교한다 (v2, 2026-10-22).
///
/// 입력은 내 자산 탭의 계좌 잔액·월 인출액을 그대로 쓰고, 이 화면에서는 가정(기간·수익률·
/// 연간 인출 목표·국민연금)만 바꾼다. 1위 전략은 "추천"이 아니라 "계산 결과"로 표기한다.
/// 계획 탭 가정 — 탭을 오가도 유지(앱 실행 중 메모리만, 저장하지 않음).
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
      extras: retirement,
    );
    final unknowns = planUnknowns(accounts, retirement);
    final result = input == null ? null : WithdrawalOptimizer.optimize(input);

    return Scaffold(
      appBar: AppBar(title: const Text('인출 계획')),
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
                  '${unknowns.join('·')}을(를) 모름으로 두어 기본 가정으로 비교했어요. '
                  '아래 "더 정확하게 계산하기"에서 넣으면 순서가 바뀔 수 있어요.',
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
              _section('전략별 ${_a.years}년 총 세금'),
              const SizedBox(height: 8),
              ..._strategyTiles(result),
            ] else
              _InfoCard(
                text:
                    '월 인출액이 없어 계산할 수 없어요. 아래 "연간 인출 목표"를 입력하거나 '
                    '내 자산 탭에서 연금·ISA 계좌의 월 인출액을 넣어 주세요.',
              ),
            const SizedBox(height: 20),
            const PlanAccuracyCard(),
            const SizedBox(height: 20),
            _section('계산 가정'),
            const SizedBox(height: 8),
            _assumptions(balances),
            const SizedBox(height: 16),
            Text(
              '2026년 세법 기준의 추정 계산이며 투자 권유가 아닙니다. '
              '국민연금공단·국민건강보험공단과 무관한 민간 계산기입니다.',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
            ),
          ],
        ],
      ),
      bottomNavigationBar: const SafeArea(child: BannerAdWidget()),
    );
  }

  Widget _section(String t) => Text(
    t,
    style: AppTextStyles.labelSmall.copyWith(
      color: AppColors.gray500,
      letterSpacing: 0.6,
    ),
  );

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
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      o.strategyName,
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
                          '계산 결과 1위',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.surface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (o.strategyId == 'pension_first')
                      Text(
                        '통념',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.gray500,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${CurrencyFormat.man(o.totalTax)}만',
                style: AppTextStyles.amount,
              ),
            ],
          ),
        ),
    ];
  }

  Widget _assumptions(PlanBalances b) {
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
          const SizedBox(height: 12),
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
                ? '기본 가정에서 세금이 가장 적게 계산된 인출 순서'
                : '세금이 가장 적게 계산된 인출 순서',
            style: AppTextStyles.label.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 6),
          Text(
            result.optimalStrategyName,
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
                  '$years년 총 세금',
                  '${CurrencyFormat.man(result.totalTaxOptimal)}만원',
                  AppColors.navy,
                ),
              ),
              Expanded(
                child: _kv(
                  '통념 대비 절감',
                  '${CurrencyFormat.man(result.savings)}만원',
                  AppColors.green,
                ),
              ),
            ],
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
            '연금저축·IRP·ISA 잔액과 월 인출액을 내 자산 탭에 입력하면, 네 가지 인출 순서의 '
            '총 세금을 계산합니다.',
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
