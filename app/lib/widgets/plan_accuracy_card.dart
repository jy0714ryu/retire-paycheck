import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'input_widgets.dart';

enum _Ans { unknown, none, yes }

/// 계획 탭 "더 정확하게" — 질문형 입력 3종 (v2.1).
/// 모름(null) = 보수적 가정, 없음(0), 있음(금액). 값은 내 자산과 같은 RetirementInput 에 저장.
class PlanAccuracyCard extends ConsumerStatefulWidget {
  const PlanAccuracyCard({super.key});

  @override
  ConsumerState<PlanAccuracyCard> createState() => _PlanAccuracyCardState();
}

class _PlanAccuracyCardState extends ConsumerState<PlanAccuracyCard> {
  /// '있음'을 눌렀지만 아직 금액을 안 넣은 질문 (저장값은 여전히 모름).
  final Set<String> _pendingYes = {};
  late final TextEditingController _rateCtl;

  @override
  void initState() {
    super.initState();
    final pct = ref.read(retirementInputProvider).retirementTaxRatePct;
    _rateCtl = TextEditingController(text: pct == null ? '' : _pctText(pct));
  }

  @override
  void dispose() {
    _rateCtl.dispose();
    super.dispose();
  }

  static String _pctText(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  _Ans _ansOf(String key, int? v) {
    if (v == null) return _pendingYes.contains(key) ? _Ans.yes : _Ans.unknown;
    return v == 0 ? _Ans.none : _Ans.yes;
  }

  void _save(RetirementInput Function(RetirementInput s) f) =>
      ref.read(retirementInputProvider.notifier).update(f);

  RetirementInput _with(
    RetirementInput s, {
    Object? nonDeducted = _keep,
    Object? irp = _keep,
    Object? rate = _keep,
    Object? isa = _keep,
  }) => s.withPlanExtras(
    pensionNonDeducted: identical(nonDeducted, _keep)
        ? s.pensionNonDeducted
        : nonDeducted as int?,
    irpRetirement: identical(irp, _keep) ? s.irpRetirement : irp as int?,
    retirementTaxRatePct: identical(rate, _keep)
        ? s.retirementTaxRatePct
        : rate as double?,
    isaProfit: identical(isa, _keep) ? s.isaProfit : isa as int?,
  );

  @override
  Widget build(BuildContext context) {
    final input = ref.watch(retirementInputProvider);
    return Material(
      key: const Key('plan_accuracy'),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.gray200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('plan_accuracy_tile'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text('더 정확하게 계산하기 (선택)', style: AppTextStyles.bodyLarge),
          subtitle: Text(
            '모르면 그대로 두세요. 세금이 크게 나오는 쪽으로 가정해요.',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          children: [
            _question(
              key: 'nonDeducted',
              q: '연금저축에 세액공제를 안 받고 넣은 돈이 있나요?',
              hint: '공제 안 받은 원금은 세금 없이 꺼낼 수 있어요.',
              value: input.pensionNonDeducted,
              onAns: (v) => _save((s) => _with(s, nonDeducted: v)),
            ),
            const SizedBox(height: 16),
            _question(
              key: 'irp',
              q: '퇴직금을 IRP로 받으셨나요?',
              hint: '퇴직금은 연금으로 받으면 퇴직소득세를 30~40% 덜 내요.',
              value: input.irpRetirement,
              onAns: (v) => _save((s) => _with(s, irp: v)),
              extra: _rateField(input),
            ),
            const SizedBox(height: 16),
            _question(
              key: 'isa',
              q: 'ISA에 수익(평가이익)이 있나요?',
              hint: 'ISA 수익은 비과세 한도까지 세금이 없어요.',
              value: input.isaProfit,
              onAns: (v) => _save((s) => _with(s, isa: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rateField(RetirementInput input) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: TextField(
      key: const Key('plan_retirement_rate'),
      controller: _rateCtl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: const InputDecoration(
        labelText: '퇴직소득세 실효세율',
        suffixText: '%',
        helperText: '퇴직소득 원천징수영수증에 있어요. 모르면 비워 두세요(5%로 계산).',
      ),
      onChanged: (t) {
        final v = double.tryParse(t.trim());
        _save(
          (s) => _with(s, rate: (v == null || v <= 0 || v > 45) ? null : v),
        );
      },
    ),
  );

  Widget _question({
    required String key,
    required String q,
    required String hint,
    required int? value,
    required void Function(int? v) onAns,
    Widget? extra,
  }) {
    final ans = _ansOf(key, value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          q,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Ans>(
            key: Key('plan_q_$key'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Ans.unknown, label: Text('모름')),
              ButtonSegment(value: _Ans.none, label: Text('없음')),
              ButtonSegment(value: _Ans.yes, label: Text('있음')),
            ],
            selected: {ans},
            onSelectionChanged: (sel) {
              final a = sel.first;
              setState(() {
                if (a == _Ans.yes && (value ?? 0) == 0) {
                  _pendingYes.add(key);
                } else {
                  _pendingYes.remove(key);
                }
              });
              if (a == _Ans.unknown) onAns(null);
              if (a == _Ans.none) onAns(0);
              if (a == _Ans.yes && (value ?? 0) == 0) onAns(null);
            },
          ),
        ),
        if (ans == _Ans.yes) ...[
          const SizedBox(height: 10),
          AmountInputField(
            key: ValueKey('plan_amount_$key'),
            label: '금액',
            value: value ?? 0,
            onChanged: (v) {
              // 금액을 지우는 중에도 '있음' 선택은 유지 (저장값만 모름으로).
              if (v > 0) {
                _pendingYes.remove(key);
              } else {
                _pendingYes.add(key);
              }
              onAns(v > 0 ? v : null);
            },
          ),
          ?extra,
        ],
      ],
    );
  }
}

const Object _keep = Object();
