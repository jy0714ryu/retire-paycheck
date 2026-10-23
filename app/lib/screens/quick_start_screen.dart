import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 첫 실행 완료 표시 키.
const String kQuickStartDoneKey = 'quick_start_done_v2';

/// 사용자 데이터가 저장되는 키 — 하나라도 있으면 기존 사용자로 보고 첫 실행 화면을 건너뛴다.
/// (retirement_input 은 첫 로드 때 기본값이 저장될 수 있어 판단에서 뺀다.)
const List<String> kUserDataKeys = [
  'holdings',
  'accounts',
  'interest_items',
  'default_account_overrides',
];

/// 첫 실행 화면을 보여 줄지 (순수 함수).
bool needsQuickStart({required Set<String> storedKeys, required bool done}) =>
    !done && !kUserDataKeys.any(storedKeys.contains);

/// 첫 실행 — 세 칸만 받고 바로 이번 달 은퇴 월급을 보여 준다 (v2, 2026-10-22).
class QuickStartScreen extends ConsumerStatefulWidget {
  const QuickStartScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends ConsumerState<QuickStartScreen> {
  final _age = TextEditingController();
  final _balance = TextEditingController();
  final _monthly = TextEditingController();

  @override
  void dispose() {
    _age.dispose();
    _balance.dispose();
    _monthly.dispose();
    super.dispose();
  }

  int _int(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  bool get _ready =>
      _int(_age) >= 20 && _int(_age) <= 100 && _int(_balance) > 0;

  void _submit() {
    final age = _int(_age);
    final balance = _int(_balance) * 10000;
    final monthly = _int(_monthly) * 10000;
    ref.read(retirementInputProvider.notifier).updateCurrentAge(age);
    ref
        .read(accountsProvider.notifier)
        .updateDefaults(
          'default_pension_savings',
          balance: balance,
          monthlyWithdrawal: monthly,
          isWithdrawing: monthly > 0,
        );
    widget.onDone();
  }

  Widget _field(
    String label,
    String suffix,
    TextEditingController c,
    Key key,
  ) => TextField(
    key: key,
    controller: c,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(7),
    ],
    style: const TextStyle(
      fontFamily: AppTextStyles.mono,
      fontFamilyFallback: [AppTextStyles.sans],
      fontSize: 17,
    ),
    decoration: InputDecoration(labelText: label, suffixText: suffix),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('은퇴월급'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: widget.onDone, child: const Text('건너뛰기')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(width: 28, height: 2, color: AppColors.gold),
            const SizedBox(height: 14),
            Text(
              '세 가지만 알려 주시면\n은퇴 월급을 바로 계산해요',
              style: AppTextStyles.h2.copyWith(
                color: AppColors.navy,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 22),
            _field('나이', '세', _age, const Key('qs_age')),
            const SizedBox(height: 14),
            _field('연금저축 잔액', '만원', _balance, const Key('qs_balance')),
            const SizedBox(height: 14),
            _field('매달 꺼내 쓸 금액 (선택)', '만원', _monthly, const Key('qs_monthly')),
            const SizedBox(height: 14),
            Text(
              'IRP·ISA·종목은 나중에 내 자산 탭에서 · 입력값은 이 폰에만 저장',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
            ),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('qs_submit'),
              onPressed: _ready ? _submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('은퇴 월급 계산하기'),
            ),
          ],
        ),
      ),
    );
  }
}
