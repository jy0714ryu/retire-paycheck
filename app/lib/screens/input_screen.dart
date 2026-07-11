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

/// 화면1 — 자산 입력 (v3: 계좌 중심 IA).
///
/// 계좌가 최상위 컨테이너다. 위→아래 구성:
/// ①자동 저장 안내 → ②계좌 카드들(effectiveAccounts) → ③[+ 계좌 추가]
/// → ④공통 설정(인출 토글·연금나침반 CTA·현재 나이) → ⑤(선택) 연 이자소득.
/// 모든 값은 provider 를 통해 SharedPreferences 에 즉시 영속된다.
class InputScreen extends ConsumerWidget {
  const InputScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(effectiveAccountsProvider);
    final isWithdrawing = ref.watch(
      retirementInputProvider.select((s) => s.isWithdrawing),
    );

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
            const SizedBox(height: 16),

            // 계좌 카드들 — effectiveAccounts 순서(기본 4개 + 유저 계좌).
            for (final account in accounts) ...[
              _AccountCard(account: account, isWithdrawing: isWithdrawing),
              const SizedBox(height: 16),
            ],

            // [+ 계좌 추가] — 이름 + 유형 다이얼로그.
            OutlinedButton.icon(
              key: const ValueKey('addAccountButton'),
              onPressed: () => _openAddAccountDialog(context, ref),
              icon: const Icon(Icons.add, color: AppColors.navy),
              label: const Text('계좌 추가',
                  style: TextStyle(color: AppColors.navy)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                side: const BorderSide(color: AppColors.navy),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 공통 설정 — 연금 인출 토글 + 연금나침반 CTA + 현재 나이.
            const _CommonSettingsCard(),
            const SizedBox(height: 16),

            // (선택) 연 이자소득 — InterestItem 리스트.
            const _InterestItemsSection(),
            const SizedBox(height: 80),
          ],
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

/// 연금나침반 Play 스토어 페이지로 이동 — 공통 설정 카드 CTA.
Future<void> _openPensionCompass() async {
  final uri = Uri.parse(_kPensionCompassUrl);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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

/// 계좌 카드 — 계좌 중심 IA 의 최상위 컨테이너(스펙 §4 목업).
///
/// 헤더(계좌명 + 유형 배지 + 유저 계좌 삭제) / 소속 종목 리스트(수량·스와이프
/// 삭제) / "+ 종목 추가" / 유형이 isa·pension 이면 잔액 + (인출 모드 ON 시)
/// 월 인출 필드. 일반계좌는 종목만 노출한다.
class _AccountCard extends ConsumerWidget {
  final Account account;
  final bool isWithdrawing;

  const _AccountCard({required this.account, required this.isWithdrawing});

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

  bool get _hasBalance => account.type != AccountType.general;

  /// 잔액 필드 라벨 — ISA 는 "현금성 잔액", 연금(연금저축·IRP)은 "잔액".
  String get _balanceLabel =>
      account.type == AccountType.isa ? '현금성 잔액' : '잔액';

  /// 월 인출 helperText — 연금은 과세, ISA 는 비과세 취급.
  String get _withdrawalHelper => account.type == AccountType.pension
      ? '과세 대상 — 나이별 연금소득세(5.5~3.3%)가 붙습니다'
      : '비과세 취급 — 세금 없이 그대로 수령합니다';

  void _updateBalance(WidgetRef ref, int v) {
    final notifier = ref.read(accountsProvider.notifier);
    if (account.isDefault) {
      notifier.updateDefaults(account.id, balance: v);
    } else {
      notifier.updateUser(account.id, balance: v);
    }
  }

  void _updateWithdrawal(WidgetRef ref, int v) {
    final notifier = ref.read(accountsProvider.notifier);
    if (account.isDefault) {
      notifier.updateDefaults(account.id, monthlyWithdrawal: v);
    } else {
      notifier.updateUser(account.id, monthlyWithdrawal: v);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);
    // 소속 종목 — 전역 인덱스를 유지해 스와이프 삭제(removeAt) 에 재사용.
    final entries = <MapEntry<int, Holding>>[];
    for (var i = 0; i < holdings.length; i++) {
      if (holdings[i].accountId == account.id) {
        entries.add(MapEntry(i, holdings[i]));
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gray200.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 계좌명 + 유형 배지 + (유저 계좌) 삭제 아이콘.
          Row(
            children: [
              Flexible(
                child: Text(account.name,
                    style: AppTextStyles.h4, overflow: TextOverflow.ellipsis),
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
              const Spacer(),
              if (!account.isDefault)
                IconButton(
                  key: ValueKey('deleteAccount_${account.id}'),
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDelete(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 소속 종목 리스트.
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '아직 종목이 없습니다.',
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            )
          else
            ...entries.map((e) => _HoldingRow(index: e.key, holding: e.value)),

          // 유형 isa·pension: 잔액 + (인출 모드) 월 인출.
          if (_hasBalance) ...[
            const SizedBox(height: 8),
            AmountInputField(
              key: ValueKey('balance_${account.id}'),
              label: _balanceLabel,
              value: account.balance,
              onChanged: (v) => _updateBalance(ref, v),
            ),
            if (isWithdrawing) ...[
              const SizedBox(height: 16),
              AmountInputField(
                key: ValueKey('withdrawal_${account.id}'),
                label: '월 인출',
                value: account.monthlyWithdrawal,
                onChanged: (v) => _updateWithdrawal(ref, v),
                helperText: _withdrawalHelper,
              ),
            ],
          ],
          const SizedBox(height: 12),

          // + 종목 추가 — 소속 계좌 고정(시트는 종목·수량만 받는다).
          OutlinedButton.icon(
            key: ValueKey('addHolding_${account.id}'),
            onPressed: () => _openAddHoldingSheet(context, ref),
            icon: const Icon(Icons.add, color: AppColors.navy),
            label: const Text('종목 추가',
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
        accountId: account.id,
        onAdd: (holding) => ref.read(holdingsProvider.notifier).add(holding),
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
          '\'${account.name}\' 계좌를 삭제하시겠습니까?\n소속 종목은 같은 유형 기본 계좌로 이동합니다',
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

/// 계좌 카드 안의 종목 행 — 수량 표시 + 스와이프(→←) 삭제.
class _HoldingRow extends ConsumerWidget {
  final int index;
  final Holding holding;

  const _HoldingRow({required this.index, required this.holding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('holding_${holding.corpCode}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) =>
          ref.read(holdingsProvider.notifier).removeAt(index),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                    child: Text(holding.corpName,
                        style: AppTextStyles.bodyLarge,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (holding.isManual) ...[
                    const SizedBox(width: 8),
                    const _ManualBadge(),
                  ],
                ],
              ),
            ),
            Text('${holding.shares}주', style: AppTextStyles.captionBold),
          ],
        ),
      ),
    );
  }
}

/// 종목 추가 바텀시트 — corp_name contains 필터 + 수량 입력.
///
/// 소속 계좌는 호출한 계좌 카드가 [accountId] 로 고정 주입한다(시트 안에서
/// 계좌를 고르지 않는다 — 계층은 "계좌가 먼저, 그 안에 종목").
///
/// `dividendEventsProvider` 를 직접 watch 하여 로딩/에러/데이터 3-상태를 렌더한다.
class _AddHoldingSheet extends ConsumerStatefulWidget {
  final String accountId;
  final void Function(Holding) onAdd;

  const _AddHoldingSheet({required this.accountId, required this.onAdd});

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
      accountId: widget.accountId,
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
      accountId: widget.accountId,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // 내용이 길어질 수 있어(직접 입력 폼) SingleChildScrollView 로 스크롤 허용.
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

/// 공통 설정 카드 — 연금 인출 토글 + 연금나침반 CTA + 현재 나이.
///
/// 인출 토글 OFF: 모든 계좌 카드의 월 인출 필드가 숨겨진다(스펙 §4).
class _CommonSettingsCard extends ConsumerWidget {
  const _CommonSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = ref.watch(retirementInputProvider);
    return InputSectionCard(
      title: '공통 설정',
      icon: Icons.tune,
      children: [
        // Material 래핑 — SwitchListTile 은 가장 가까운 Material 조상에
        // 배경/잉크를 그리는데, InputSectionCard 의 흰 배경 Container 가
        // 바로 그 조상이면 프레임워크 경고가 발생한다.
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
              style: AppTextStyles.captionBold.copyWith(color: AppColors.navy),
            ),
          ),
        ),
        const SizedBox(height: 16),
        NumberInputField(
          label: '현재 나이',
          value: input.currentAge,
          suffix: '세',
          min: 20,
          max: 100,
          onChanged: (v) =>
              ref.read(retirementInputProvider.notifier).updateCurrentAge(v),
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
  // 원 단위 저장(다른 금액 필드와 동일 관례) — 입력 UI 는 AmountInputField 로 만원 표시.
  int _annualAmountWon = 0;
  bool _isSpecificMonths = false;
  final Set<int> _months = {};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _valid {
    final name = _nameController.text.trim();
    if (name.isEmpty || _annualAmountWon <= 0) return false;
    if (_isSpecificMonths && _months.isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_valid) return;
    widget.onAdd(InterestItem(
      id: 'interest_${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      annualAmount: _annualAmountWon,
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
          AmountInputField(
            key: const ValueKey('interestItemAmount'),
            label: '연 금액',
            value: _annualAmountWon,
            onChanged: (v) => setState(() => _annualAmountWon = v),
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
