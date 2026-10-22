import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/nps_estimator.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_format.dart';
import 'keyboard_safe_back.dart';

/// 국민연금 간이 추정 — 결과(월액 원·개시 나이)를 돌려준다. 취소면 null.
Future<({int monthly, int startAge})?> showNpsEstimateSheet(
  BuildContext context,
) => showModalBottomSheet<({int monthly, int startAge})>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => const KeyboardSafeBack(child: _NpsEstimateSheet()),
);

class _NpsEstimateSheet extends StatefulWidget {
  const _NpsEstimateSheet();

  @override
  State<_NpsEstimateSheet> createState() => _NpsEstimateSheetState();
}

class _NpsEstimateSheetState extends State<_NpsEstimateSheet> {
  final _income = TextEditingController();
  final _years = TextEditingController();
  final _birth = TextEditingController();

  @override
  void dispose() {
    _income.dispose();
    _years.dispose();
    _birth.dispose();
    super.dispose();
  }

  NpsEstimateResult? get _result {
    final income = int.tryParse(_income.text.trim());
    final years = int.tryParse(_years.text.trim());
    final birth = int.tryParse(_birth.text.trim());
    if (income == null || income <= 0) return null;
    if (years == null || years <= 0 || years > 45) return null;
    if (birth == null || birth < 1940 || birth > DateTime.now().year - 18) {
      return null;
    }
    return NpsEstimator.estimate(
      NpsEstimateInput(
        monthlyIncome: income * 10000,
        enrollmentMonths: years * 12,
        birthYear: birth,
        receiptType: NpsReceiptType.normal,
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String suffix,
    Key k,
    int maxLen,
  ) => TextField(
    key: k,
    controller: c,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(maxLen),
    ],
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final bottom =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('국민연금 예상액 추정', style: AppTextStyles.h4),
          const SizedBox(height: 4),
          Text(
            '공개된 산식으로 계산한 간이 추정이에요. 정확한 금액은 국민연금공단 '
            '"내 연금 알아보기"에서 확인하세요.',
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
          const SizedBox(height: 16),
          _field(_income, '가입 기간 평균 월소득', '만원', const Key('nps_income'), 5),
          const SizedBox(height: 12),
          _field(_years, '가입 기간', '년', const Key('nps_years'), 2),
          const SizedBox(height: 12),
          _field(_birth, '출생연도', '년', const Key('nps_birth'), 4),
          const SizedBox(height: 16),
          if (r != null)
            Text(
              r.eligibility == NpsEligibility.eligible
                  ? '예상 월 ${CurrencyFormat.man(r.monthlyPensionAmount)}만원 · '
                        '${r.actualStartAge}세부터 (추정)'
                  : '가입 기간이 10년이 안 되면 연금 대신 일시금으로 받아요.',
              key: const Key('nps_result'),
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.navy),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('nps_apply'),
              onPressed: r != null && r.eligibility == NpsEligibility.eligible
                  ? () => Navigator.of(context).pop((
                      monthly: r.monthlyPensionAmount,
                      startAge: r.actualStartAge,
                    ))
                  : null,
              child: const Text('이 값 쓰기'),
            ),
          ),
        ],
      ),
    );
  }
}
