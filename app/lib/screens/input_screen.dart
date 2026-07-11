import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/input_widgets.dart';

/// 연금나침반 Play 스토어 페이지 — 인출 순서 최적화 CTA.
const String _kPensionCompassUrl =
    'https://play.google.com/store/apps/details?id=com.quantlog.pensioncompass';

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
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(h.corpName,
                                        style: AppTextStyles.bodyLarge,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (h.isManual) ...[
                                    const SizedBox(width: 8),
                                    const _ManualBadge(),
                                  ],
                                ],
                              ),
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

            // 계좌 관리 — 기본 계좌 3개 + 유저 계좌, 추가/삭제.
            const _AccountManagementSection(),
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
                // Material 래핑 — SwitchListTile 은 가장 가까운 Material 조상에
                // 배경/잉크를 그리는데, InputSectionCard 의 흰 배경 Container 가
                // 바로 그 조상이면 프레임워크 경고가 발생한다(색 있는 DecoratedBox
                // 가 ListTile 잉크 효과를 가림).
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('연금 인출 중', style: AppTextStyles.label),
                    value: input.isWithdrawing,
                    activeThumbColor: AppColors.navy,
                    onChanged: (v) => ref
                        .read(retirementInputProvider.notifier)
                        .update((s) => s.copyWith(isWithdrawing: v)),
                  ),
                ),
                InkWell(
                  onTap: _openPensionCompass,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '어떤 순서로 빼야 세금을 아낄까? → 연금나침반',
                      style: AppTextStyles.captionBold
                          .copyWith(color: AppColors.navy),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Visibility(
                  visible: input.isWithdrawing,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 카드 4: (선택) 연 이자소득 — InterestItem 리스트.
            const _InterestItemsSection(),
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

  Future<void> _openPensionCompass() async {
    final uri = Uri.parse(_kPensionCompassUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  // 직접 입력 모드 (배당 API 미커버 종목 폴백).
  bool _manualMode = false;
  final _manualNameController = TextEditingController();
  final _manualSharesController = TextEditingController();
  final _manualAnnualController = TextEditingController();
  final Set<int> _manualMonths = {4}; // 기본 4월(국내 결산배당 지급월).

  // 계좌 선택 — 기본 일반, 유형 변경 시 해당 유형 기본 계좌로 리셋.
  AccountType _accountType = AccountType.general;
  String _accountId = 'default_general';

  @override
  void dispose() {
    _sharesController.dispose();
    _manualNameController.dispose();
    _manualSharesController.dispose();
    _manualAnnualController.dispose();
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
      accountId: _accountId,
    ));
    Navigator.of(context).pop();
  }

  bool get _manualValid {
    final name = _manualNameController.text.trim();
    final shares = int.tryParse(_manualSharesController.text.trim()) ?? 0;
    final annual = int.tryParse(_manualAnnualController.text.trim()) ?? 0;
    return name.isNotEmpty && shares > 0 && annual > 0 && _manualMonths.isNotEmpty;
  }

  void _submitManual() {
    if (!_manualValid) return;
    widget.onAdd(Holding(
      // API corp_code(8자리 숫자)와 충돌하지 않는 고유 코드.
      corpCode: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      corpName: _manualNameController.text.trim(),
      shares: int.parse(_manualSharesController.text.trim()),
      manualPerShareAnnual: int.parse(_manualAnnualController.text.trim()),
      manualPaymentMonths: _manualMonths.toList()..sort(),
      accountId: _accountId,
    ));
    Navigator.of(context).pop();
  }

  /// 계좌 선택 — [일반/ISA/연금] SegmentedButton + (유저 계좌 존재 시) 드롭다운.
  /// 유형 전환 시 선택 계좌는 항상 해당 유형 기본 계좌로 리셋된다.
  Widget _buildAccountSelector() {
    final userAccounts = ref.watch(accountsProvider);
    final matching =
        userAccounts.where((a) => a.type == _accountType).toList();
    final defaultAccount =
        kDefaultAccounts.firstWhere((a) => a.type == _accountType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('계좌 선택', style: AppTextStyles.captionBold),
        const SizedBox(height: 8),
        SegmentedButton<AccountType>(
          segments: const [
            ButtonSegment(value: AccountType.general, label: Text('일반')),
            ButtonSegment(value: AccountType.isa, label: Text('ISA')),
            ButtonSegment(value: AccountType.pension, label: Text('연금')),
          ],
          selected: {_accountType},
          onSelectionChanged: (s) => setState(() {
            _accountType = s.first;
            _accountId = 'default_${_accountType.name}';
          }),
        ),
        if (matching.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gray200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('accountDropdown'),
                isExpanded: true,
                value: _accountId,
                items: [
                  DropdownMenuItem(
                    value: defaultAccount.id,
                    child: Text(defaultAccount.name),
                  ),
                  for (final a in matching)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) =>
                    setState(() => _accountId = v ?? defaultAccount.id),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // 계좌 선택(SegmentedButton+드롭다운)이 추가되며 내용이 길어져 고정 높이
    // Padding 만으로는 시트가 넘칠 수 있다 — SingleChildScrollView 로 스크롤 허용.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      child: _manualMode ? _buildManualForm() : _buildSearchForm(),
    );
  }

  /// 직접 입력 폼 — 종목명 / 수량 / 주당 연간 배당금 / 지급월 FilterChip 다중선택.
  Widget _buildManualForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _manualMode = false),
              icon: const Icon(Icons.arrow_back),
              tooltip: '검색으로 돌아가기',
              color: AppColors.navy,
            ),
            Text('직접 입력', style: AppTextStyles.h4),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '배당 목록에 없는 종목·ETF를 직접 등록합니다.\n'
          '지급월엔 예상 배당이 균등 분할되어 표시돼요.',
          style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('manualName'),
          controller: _manualNameController,
          decoration: _manualFieldDecoration(labelText: '종목명'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('manualShares'),
          controller: _manualSharesController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _manualFieldDecoration(labelText: '보유 수량', suffixText: '주'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        _buildAccountSelector(),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('manualAnnual'),
          controller: _manualAnnualController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _manualFieldDecoration(
            labelText: '주당 연간 배당금',
            suffixText: '원',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('지급월 (여러 개 선택 가능)', style: AppTextStyles.captionBold),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var m = 1; m <= 12; m++)
              FilterChip(
                key: ValueKey('manualMonth_$m'),
                label: Text('$m월'),
                selected: _manualMonths.contains(m),
                selectedColor: AppColors.navy.withValues(alpha: 0.12),
                checkmarkColor: AppColors.navy,
                onSelected: (on) => setState(() {
                  on ? _manualMonths.add(m) : _manualMonths.remove(m);
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const ValueKey('manualSubmit'),
            onPressed: _manualValid ? _submitManual : null,
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
    );
  }

  InputDecoration _manualFieldDecoration({
    required String labelText,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: labelText,
      suffixText: suffixText,
      filled: true,
      fillColor: AppColors.gray50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gray200),
      ),
    );
  }

  Widget _buildSearchForm() {
    final asyncEvents = ref.watch(dividendEventsProvider);
    return Column(
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
          _buildAccountSelector(),
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
          const SizedBox(height: 4),
          // 배당 API 미커버 종목 폴백 — 직접 입력 폼으로 전환.
          Center(
            child: TextButton(
              key: const ValueKey('manualEntryButton'),
              onPressed: () => setState(() => _manualMode = true),
              child: Text.rich(
                TextSpan(
                  text: '찾는 종목이 없나요? ',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.gray500),
                  children: [
                    TextSpan(
                      text: '직접 입력',
                      style: AppTextStyles.captionBold.copyWith(
                        color: AppColors.navy,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
    );
  }
}

/// "직접 입력" 미니 배지 — 수동 등록 종목 구분 표기.
class _ManualBadge extends StatelessWidget {
  const _ManualBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '직접 입력',
        style: AppTextStyles.labelSmall.copyWith(color: AppColors.navy),
      ),
    );
  }
}

/// 계좌 관리 — 기본 계좌 3개(고정, 삭제 불가) + 유저 계좌(추가/삭제) ExpansionTile.
class _AccountManagementSection extends ConsumerWidget {
  const _AccountManagementSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAccounts = ref.watch(accountsProvider);
    // ExpansionTile 은 내부 ListTile 이 가장 가까운 Material 조상에 배경/잉크를
    // 그린다 — 색이 있는 Container 로 바로 감싸면 프레임워크 경고(위젯 테스트에서
    // 예외로 처리됨)가 발생하므로 Material 로 카드 배경을 준다.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gray200.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: ExpansionTile(
            leading: const Icon(Icons.account_balance_wallet_outlined,
                color: AppColors.navy),
            title: const Text('계좌 관리', style: AppTextStyles.h4),
            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              for (final a in kDefaultAccounts)
                _AccountRow(account: a, deletable: false),
              for (final a in userAccounts)
                _AccountRow(account: a, deletable: true),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('addAccountButton'),
                onPressed: () => _openAddAccountDialog(context, ref),
                icon: const Icon(Icons.add, color: AppColors.navy),
                label: const Text('계좌 추가',
                    style: TextStyle(color: AppColors.navy)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  side: const BorderSide(color: AppColors.navy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _AddAccountDialog(
        onAdd: (name, type) => ref.read(accountsProvider.notifier).add(
              Account(
                id: 'user_${DateTime.now().microsecondsSinceEpoch}',
                name: name,
                type: type,
              ),
            ),
      ),
    );
  }
}

/// 계좌 관리 리스트의 행 하나 — 유저 계좌만 삭제 아이콘 노출.
class _AccountRow extends ConsumerWidget {
  final Account account;
  final bool deletable;

  const _AccountRow({required this.account, required this.deletable});

  String get _typeLabel {
    switch (account.type) {
      case AccountType.general:
        return '일반';
      case AccountType.isa:
        return 'ISA';
      case AccountType.pension:
        return '연금';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(account.name,
                      style: AppTextStyles.body,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_typeLabel, style: AppTextStyles.labelSmall),
                ),
              ],
            ),
          ),
          if (deletable)
            IconButton(
              key: ValueKey('deleteAccount_${account.id}'),
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('계좌 삭제'),
        content: Text(
          '\'${account.name}\' 계좌를 삭제하시겠습니까?\n소속 종목은 기본 계좌로 이동합니다',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            key: const ValueKey('confirmDeleteAccount'),
            onPressed: () {
              ref.read(accountsProvider.notifier).remove(account.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// 계좌 추가 다이얼로그 — 이름 TextField + 유형 SegmentedButton.
class _AddAccountDialog extends StatefulWidget {
  final void Function(String name, AccountType type) onAdd;

  const _AddAccountDialog({required this.onAdd});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _nameController = TextEditingController();
  AccountType _type = AccountType.general;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _nameController.text.trim().isNotEmpty;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('계좌 추가'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('newAccountName'),
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '계좌 이름',
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
          SegmentedButton<AccountType>(
            segments: const [
              ButtonSegment(value: AccountType.general, label: Text('일반')),
              ButtonSegment(value: AccountType.isa, label: Text('ISA')),
              ButtonSegment(value: AccountType.pension, label: Text('연금')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          key: const ValueKey('confirmAddAccount'),
          onPressed: valid
              ? () {
                  widget.onAdd(_nameController.text.trim(), _type);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('추가'),
        ),
      ],
    );
  }
}

/// (선택) 연 이자소득 카드 — InterestItem 리스트 + 항목 추가 시트.
class _InterestItemsSection extends ConsumerWidget {
  const _InterestItemsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(interestItemsProvider);
    return InputSectionCard(
      title: '(선택) 연 이자소득',
      icon: Icons.savings_outlined,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '등록한 이자소득 항목이 없습니다.\n예금 이자 등을 추가하면 금융소득종합과세 게이지에 합산됩니다.',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.gray500),
            ),
          )
        else
          ...List.generate(
            items.length,
            (i) => _InterestItemRow(item: items[i], index: i),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const ValueKey('addInterestItemButton'),
          onPressed: () => _openAddItemSheet(context, ref),
          icon: const Icon(Icons.add, color: AppColors.navy),
          label:
              const Text('항목 추가', style: TextStyle(color: AppColors.navy)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: const BorderSide(color: AppColors.navy),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  void _openAddItemSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddInterestItemSheet(
        onAdd: (item) => ref.read(interestItemsProvider.notifier).add(item),
      ),
    );
  }
}

/// 이자소득 항목 행 — 이름·연 금액·지급 방식 표시 + 삭제.
class _InterestItemRow extends ConsumerWidget {
  final InterestItem item;
  final int index;

  const _InterestItemRow({required this.item, required this.index});

  String get _scheduleLabel =>
      item.months.isEmpty ? '월 균등' : '${item.months.join(", ")}월';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  '연 ${NumberFormat('#,###').format(item.annualAmount)}원 · $_scheduleLabel',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.gray500),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('deleteInterestItem_$index'),
            icon: const Icon(Icons.delete_outline,
                color: AppColors.error, size: 20),
            onPressed: () =>
                ref.read(interestItemsProvider.notifier).removeAt(index),
          ),
        ],
      ),
    );
  }
}

/// 이자소득 항목 추가 바텀시트 — 이름·연 금액·지급방식[월균등|특정월]+월 선택.
class _AddInterestItemSheet extends StatefulWidget {
  final void Function(InterestItem) onAdd;

  const _AddInterestItemSheet({required this.onAdd});

  @override
  State<_AddInterestItemSheet> createState() => _AddInterestItemSheetState();
}

class _AddInterestItemSheetState extends State<_AddInterestItemSheet> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isSpecificMonths = false;
  final Set<int> _months = {};

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  bool get _valid {
    final name = _nameController.text.trim();
    final amount =
        int.tryParse(_amountController.text.replaceAll(',', '').trim()) ?? 0;
    if (name.isEmpty || amount <= 0) return false;
    if (_isSpecificMonths && _months.isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_valid) return;
    widget.onAdd(InterestItem(
      id: 'interest_${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      annualAmount:
          int.parse(_amountController.text.replaceAll(',', '').trim()),
      months: _isSpecificMonths ? (_months.toList()..sort()) : const [],
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
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
          Text('이자소득 항목 추가', style: AppTextStyles.h4),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('interestItemName'),
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '이름',
              filled: true,
              fillColor: AppColors.gray50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.gray200),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('interestItemAmount'),
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '연 금액',
              suffixText: '원',
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
          Text('지급 방식', style: AppTextStyles.captionBold),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('월 균등')),
              ButtonSegment(value: true, label: Text('특정월')),
            ],
            selected: {_isSpecificMonths},
            onSelectionChanged: (s) =>
                setState(() => _isSpecificMonths = s.first),
          ),
          if (_isSpecificMonths) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var m = 1; m <= 12; m++)
                  FilterChip(
                    key: ValueKey('interestMonth_$m'),
                    label: Text('$m월'),
                    selected: _months.contains(m),
                    selectedColor: AppColors.navy.withValues(alpha: 0.12),
                    checkmarkColor: AppColors.navy,
                    onSelected: (on) => setState(() {
                      on ? _months.add(m) : _months.remove(m);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const ValueKey('interestItemSubmit'),
              onPressed: _valid ? _submit : null,
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
