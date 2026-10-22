import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../health_engine/engine.dart';
import '../models/retirement_input.dart';
import '../providers/app_providers.dart';
import '../services/health_bridge.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import 'input_widgets.dart';
import 'keyboard_safe_back.dart';

/// 내 자산 › 공통 설정 › 건강보험 (선택) — 접힘 카드 (v2.2).
///
/// 접힌 상태에선 요약 한 줄만. 직장 다님이면 재산·사업자 칸은 숨긴다(직장인은 소득월액만 봄).
class HealthInputsCard extends ConsumerWidget {
  const HealthInputsCard({super.key});

  static String _typeLabel(HealthInsType t) => switch (t) {
    HealthInsType.dependent => '피부양자',
    HealthInsType.employee => '직장 다님',
    HealthInsType.regional => '지역가입자',
  };

  static String _help(HealthInsType t) => switch (t) {
    HealthInsType.dependent => '가족 건강보험에 피부양자로 올라 있어요 — 소득·재산 기준을 함께 봐요',
    HealthInsType.employee => '본인이 직장에 다녀요 — 월급 외 소득 2,000만원 넘으면 건보료 추가',
    HealthInsType.regional => '본인 이름으로 건보료를 내요 — 소득·재산으로 월 보험료를 계산해요',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = ref.watch(retirementInputProvider);
    final notifier = ref.read(retirementInputProvider.notifier);
    final employee = input.healthInsType == HealthInsType.employee;
    // 직장인도 퇴직 전 월급을 넣으면 퇴직 후 비교에 재산·사업자가 필요하다.
    final showProperty = !employee || input.lastMonthlySalary > 0;
    final summary = [
      _typeLabel(input.healthInsType),
      '공적연금 월 ${CurrencyFormat.man(input.publicPensionMonthly)}만원',
      if (showProperty)
        input.propertyTaxBase > 0
            ? '재산 ${CurrencyFormat.eokMan(input.propertyTaxBase)}'
            : '재산 미입력',
    ].join(' · ');

    return Material(
      key: const Key('health_inputs'),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.gray200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('health_inputs_tile'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text('건강보험 (선택)', style: AppTextStyles.captionBold),
          subtitle: Text(
            summary,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<HealthInsType>(
                key: const Key('health_ins_type'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: HealthInsType.dependent,
                    label: Text('피부양자'),
                  ),
                  ButtonSegment(
                    value: HealthInsType.employee,
                    label: Text('직장 다님'),
                  ),
                  ButtonSegment(
                    value: HealthInsType.regional,
                    label: Text('지역가입자'),
                  ),
                ],
                selected: {input.healthInsType},
                onSelectionChanged: (v) =>
                    notifier.update((s) => s.copyWith(healthInsType: v.first)),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _help(input.healthInsType),
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            ),
            const SizedBox(height: 14),
            AmountInputField(
              key: const ValueKey('public_pension_monthly'),
              label: '국민연금 등 공적연금 (월)',
              value: input.publicPensionMonthly,
              helperText: '받고 있지 않으면 0',
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(publicPensionMonthly: v)),
            ),
            const SizedBox(height: 12),
            AmountInputField(
              key: const ValueKey('other_annual_income'),
              label: '그 밖의 연 소득 (사업·임대)',
              value: input.otherAnnualIncome,
              helperText: '사업·임대 소득 합계 (근로소득·직장 월급은 넣지 않아요)',
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(otherAnnualIncome: v)),
            ),
            if (showProperty) ...[
              SwitchListTile(
                key: const Key('business_registered'),
                contentPadding: EdgeInsets.zero,
                title: Text('사업자등록이 있어요', style: AppTextStyles.body),
                subtitle: Text(
                  '피부양자는 사업자등록이 있으면 사업소득이 조금만 있어도 빠져요',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.gray500,
                  ),
                ),
                value: input.businessRegistered,
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(businessRegistered: v)),
              ),
              const SizedBox(height: 4),
              AmountInputField(
                key: const ValueKey('property_tax_base'),
                label: '재산 (재산세 과세표준)',
                value: input.propertyTaxBase,
                helperText: '재산세 고지서의 과세표준 합계. 모르면 아래에서 시세로 계산',
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(propertyTaxBase: v)),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('property_from_price'),
                  onPressed: () async {
                    final v = await _showPropertySheet(context, ref);
                    if (v != null) {
                      notifier.update((s) => s.copyWith(propertyTaxBase: v));
                    }
                  },
                  child: const Text('주택 시세로 계산하기'),
                ),
              ),
            ],
            const SizedBox(height: 4),
            AmountInputField(
              key: const ValueKey('last_monthly_salary'),
              label: '퇴직 전 월급 (선택)',
              value: input.lastMonthlySalary,
              helperText: '넣으면 경보 탭에서 퇴직 후 임의계속가입·지역가입을 비교해요',
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(lastMonthlySalary: v)),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _showPropertySheet(BuildContext context, WidgetRef ref) async {
    final params = await ref.read(healthParamsProvider.future);
    if (!context.mounted) return null;
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => KeyboardSafeBack(child: _PropertySheet(params: params)),
    );
  }
}

/// 주택 시세 → 재산세 과세표준 추정 (건보료나침반 간편 모드).
class _PropertySheet extends StatefulWidget {
  const _PropertySheet({required this.params});

  final HealthParams params;

  @override
  State<_PropertySheet> createState() => _PropertySheetState();
}

class _PropertySheetState extends State<_PropertySheet> {
  int _price = 0;
  bool _singleHome = true;

  @override
  Widget build(BuildContext context) {
    final r = _price > 0
        ? SimplePropertyEstimator(
            widget.params,
          ).estimate(marketPrice: _price, singleHome: _singleHome)
        : null;
    final bottom =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('주택 시세로 재산 계산', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text(
            '시세 → 공시가격 → 과세표준 순서로 추정해요. 실제 재산세 고지서 금액과 다를 수 있어요.',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 16),
          AmountInputField(
            key: const ValueKey('property_price'),
            label: '주택 시세',
            value: _price,
            onChanged: (v) => setState(() => _price = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('1세대 1주택이에요', style: AppTextStyles.body),
            value: _singleHome,
            onChanged: (v) => setState(() => _singleHome = v),
          ),
          if (r != null)
            Text(
              '추정 과세표준 ${CurrencyFormat.eokMan(r.taxBase)} '
              '(공시가격 약 ${CurrencyFormat.eokMan(r.officialPrice)})',
              key: const Key('property_estimate'),
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.navy),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('property_apply'),
              onPressed: r == null
                  ? null
                  : () => Navigator.of(context).pop(r.taxBase),
              child: const Text('이 값 쓰기'),
            ),
          ),
        ],
      ),
    );
  }
}
