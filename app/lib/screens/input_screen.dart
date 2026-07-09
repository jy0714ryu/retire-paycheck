import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/input_widgets.dart';

/// 화면1 — 자산 입력.
///
/// 카드 4개: ①보유 종목(검색·수량) ②연금 계좌 ③월 인출 2필드 ④(선택) 연 이자소득.
/// 모든 값은 provider 를 통해 SharedPreferences 에 즉시 영속된다.
class InputScreen extends ConsumerWidget {
  const InputScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);
    final input = ref.watch(retirementInputProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('자산 입력'),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 자동 저장 안내 — 별도 저장 버튼 없이 입력 즉시 기기에 저장됨을 알린다.
            const _AutoSaveNotice(),
            const SizedBox(height: 12),
            // 카드 1: 보유 종목
            InputSectionCard(
              title: '보유 종목',
              icon: Icons.pie_chart_outline,
              children: [
                if (holdings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '아직 등록한 종목이 없습니다.\n아래 버튼으로 보유 종목을 추가하세요.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.gray500),
                    ),
                  )
                else
                  ...List.generate(holdings.length, (i) {
                    final h = holdings[i];
                    return Dismissible(
                      key: ValueKey('holding_${h.corpCode}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) =>
                          ref.read(holdingsProvider.notifier).removeAt(i),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.gray50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.gray200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(h.corpName,
                                  style: AppTextStyles.bodyLarge),
                            ),
                            Text('${h.shares}주',
                                style: AppTextStyles.captionBold),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => _openAddHoldingSheet(context, ref),
                  icon: const Icon(Icons.add, color: AppColors.navy),
                  label: const Text('종목 추가',
                      style: TextStyle(color: AppColors.navy)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    side: const BorderSide(color: AppColors.navy),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 카드 2: 연금 계좌
            InputSectionCard(
              title: '연금 계좌',
              icon: Icons.account_balance,
              children: [
                AmountInputField(
                  label: '연금저축 잔액',
                  value: input.pensionSavings,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updatePensionSavings(v),
                ),
                const SizedBox(height: 16),
                AmountInputField(
                  label: 'IRP 잔액',
                  value: input.irpBalance,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateIrpBalance(v),
                ),
                const SizedBox(height: 16),
                AmountInputField(
                  label: 'ISA 잔액',
                  value: input.isaBalance,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateIsaBalance(v),
                ),
                const SizedBox(height: 16),
                NumberInputField(
                  label: '현재 나이',
                  value: input.currentAge,
                  suffix: '세',
                  min: 20,
                  max: 100,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateCurrentAge(v),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 카드 3: 월 인출 계획
            InputSectionCard(
              title: '월 인출 계획',
              icon: Icons.payments_outlined,
              children: [
                AmountInputField(
                  label: '연금저축·IRP 월 인출',
                  value: input.monthlyPensionWithdrawal,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateMonthlyPensionWithdrawal(v),
                  helperText: '과세 대상 — 나이별 연금소득세(5.5~3.3%)가 붙습니다',
                ),
                const SizedBox(height: 16),
                AmountInputField(
                  label: 'ISA·기타 월 인출',
                  value: input.monthlyOtherWithdrawal,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateMonthlyOtherWithdrawal(v),
                  helperText: '비과세 취급 — 세금 없이 그대로 수령합니다',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: AppColors.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '공제·비공제 정밀 구분은 연금나침반에서 확인하세요.',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.gray600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 카드 4: (선택) 연 이자소득
            InputSectionCard(
              title: '(선택) 연 이자소득',
              icon: Icons.savings_outlined,
              children: [
                AmountInputField(
                  label: '연 이자·배당 외 소득',
                  value: input.annualInterestIncome,
                  onChanged: (v) => ref
                      .read(retirementInputProvider.notifier)
                      .updateAnnualInterestIncome(v),
                  helperText: '예금 이자 등 — 금융소득종합과세 게이지에 합산됩니다',
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _openAddHoldingSheet(BuildContext context, WidgetRef ref) {
    // 배당 목록은 시트 내부에서 provider 를 watch 한다(로딩→데이터 자동 반영).
    // 여기서 ref.read 스냅샷을 잡으면 provider 가 아직 로딩(AsyncLoading)일 때
    // 항상 빈 목록으로 굳어 "불러오지 못했습니다" 가 계속 뜬다.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddHoldingSheet(
        onAdd: (holding) => ref.read(holdingsProvider.notifier).add(holding),
      ),
    );
  }
}

/// 자동 저장 안내 배너 — 입력값은 변경 즉시 SharedPreferences 에 영속되므로
/// 별도 저장 버튼이 없다. 사용자 불안(저장됐나?)을 없애기 위한 상시 고지.
class _AutoSaveNotice extends StatelessWidget {
  const _AutoSaveNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined,
              size: 18, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '입력한 내용은 자동으로 저장됩니다. 앱을 닫아도 값이 유지돼요.',
              style: AppTextStyles.caption.copyWith(color: AppColors.gray700),
            ),
          ),
        ],
      ),
    );
  }
}

/// 종목 추가 바텀시트 — corp_name contains 필터 + 수량 입력.
///
/// `dividendEventsProvider` 를 직접 watch 하여 로딩/에러/데이터 3-상태를 렌더한다.
/// (ConsumerStatefulWidget: ProviderScope 는 Navigator 를 가로질러 상속되므로
///  별도 위젯 트리인 바텀시트에서도 정상 접근된다.)
class _AddHoldingSheet extends ConsumerStatefulWidget {
  final void Function(Holding) onAdd;

  const _AddHoldingSheet({required this.onAdd});

  @override
  ConsumerState<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends ConsumerState<_AddHoldingSheet> {
  String _query = '';
  DividendEvent? _selected;
  final _sharesController = TextEditingController();

  @override
  void dispose() {
    _sharesController.dispose();
    super.dispose();
  }

  /// corp_name dedupe(corpCode 기준 최초 1건) + 이름순 정렬 — 검색 소스.
  List<DividendEvent> _candidatesFrom(List<DividendEvent> events) {
    final Map<String, DividendEvent> byCode = {};
    for (final e in events) {
      byCode.putIfAbsent(e.corpCode, () => e);
    }
    return byCode.values.toList()
      ..sort((a, b) => a.corpName.compareTo(b.corpName));
  }

  List<DividendEvent> _filtered(List<DividendEvent> candidates) {
    if (_query.isEmpty) return candidates.take(30).toList();
    return candidates
        .where((e) => e.corpName.contains(_query))
        .take(30)
        .toList();
  }

  void _submit() {
    final sel = _selected;
    final shares = int.tryParse(_sharesController.text.trim()) ?? 0;
    if (sel == null || shares <= 0) return;
    widget.onAdd(Holding(
      corpCode: sel.corpCode,
      corpName: sel.corpName,
      shares: shares,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final asyncEvents = ref.watch(dividendEventsProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('종목 추가', style: AppTextStyles.h4),
          const SizedBox(height: 16),
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: '종목명 검색',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.gray50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.gray200),
              ),
            ),
            onChanged: (t) => setState(() {
              _query = t.trim();
              _selected = null;
            }),
          ),
          const SizedBox(height: 12),
          asyncEvents.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '배당 종목 목록을 아직 불러오지 못했습니다.\n잠시 후 다시 시도하세요.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.gray500),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(dividendEventsProvider),
                    child: const Text('다시 시도',
                        style: TextStyle(color: AppColors.navy)),
                  ),
                ],
              ),
            ),
            data: (result) {
              final candidates = _candidatesFrom(result.events);
              if (candidates.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '표시할 배당 종목이 없습니다.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.gray500),
                  ),
                );
              }
              final filtered = _filtered(candidates);
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    final selected = _selected?.corpCode == e.corpCode;
                    return ListTile(
                      dense: true,
                      title: Text(e.corpName, style: AppTextStyles.body),
                      trailing: selected
                          ? const Icon(Icons.check_circle,
                              color: AppColors.green)
                          : null,
                      onTap: () => setState(() => _selected = e),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sharesController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '보유 수량',
              suffixText: '주',
              filled: true,
              fillColor: AppColors.gray50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.gray200),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selected != null &&
                      (int.tryParse(_sharesController.text.trim()) ?? 0) > 0)
                  ? _submit
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                disabledBackgroundColor: AppColors.gray300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text('추가', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }
}
