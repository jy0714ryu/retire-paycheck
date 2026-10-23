import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/cashflow_engine.dart';
import '../services/excel_export.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/disclaimer_dialog.dart';

const String kSupportEmail = 'golmok.support@gmail.com';
const String kStoreUrl =
    'https://play.google.com/store/apps/details?id=com.quantlog.retirepaycheck';
const String kPrivacyUrl =
    'https://jy0714ryu.github.io/retire-paycheck/privacy-policy.html';

/// 앱 공유 문구 — 개인 자산 정보는 넣지 않는다.
const String kAppShareText =
    '배당·연금이 매달 얼마 들어오는지 달력으로 보여주는 앱이에요.\n'
    '로그인·계좌 연동 없이 무료 — 은퇴월급\n$kStoreUrl';

/// 설정(v2.3) — 엑셀 내보내기 · 앱 공유 · 문의 · 리뷰 · 정보.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportExcel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final year = DateTime.now().year;
      final events = await ref.read(combinedEventsProvider(year).future);
      final holdings = ref.read(holdingsProvider);
      final accounts = ref.read(effectiveAccountsProvider);
      final months = CashflowEngine.buildMonths(
        holdings: holdings,
        events: events,
        input: ref.read(retirementInputProvider),
        from: DateTime(year, 1, 1),
        monthCount: 12,
        accounts: accounts,
        interestItems: ref.read(interestItemsProvider),
      );
      final bytes = buildExportXlsx(
        year: year,
        months: months,
        holdings: holdings,
        accounts: accounts,
      );
      final name = '은퇴월급_$year.xlsx';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: name,
            ),
          ],
          fileNameOverrides: [name],
        ),
      );
    } catch (_) {
      _snack('내보내기에 실패했어요. 잠시 후 다시 시도하세요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mailDeveloper() async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=${Uri.encodeComponent('[은퇴월급] 문의')}',
    );
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok) _snack('메일 앱을 열 수 없어요 — $kSupportEmail');
  }

  Future<void> _openUrl(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok) _snack('링크를 열 수 없어요');
  }

  void _showDisclaimer() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          DisclaimerDialog(onAccept: () => Navigator.of(dialogContext).pop()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          _section('내 자료'),
          _tile(
            key: 'settings_export',
            icon: Icons.table_view_outlined,
            title: '엑셀로 내보내기',
            subtitle: '올해 월별 금액·배당 내역·보유 종목',
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _exportExcel,
          ),
          _section('알리기·문의'),
          _tile(
            key: 'settings_share',
            icon: Icons.share_outlined,
            title: '앱 공유하기',
            subtitle: '카카오톡·문자로 보내기',
            onTap: () =>
                SharePlus.instance.share(ShareParams(text: kAppShareText)),
          ),
          _tile(
            key: 'settings_mail',
            icon: Icons.mail_outline,
            title: '개발자에게 메일',
            subtitle: kSupportEmail,
            onTap: _mailDeveloper,
          ),
          _tile(
            key: 'settings_review',
            icon: Icons.star_outline,
            title: '리뷰 남기기',
            onTap: () => InAppReview.instance.openStoreListing().catchError(
              (_) => _openUrl(kStoreUrl),
            ),
          ),
          _section('정보'),
          _tile(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보처리방침',
            subtitle: '자산 정보는 이 폰에만 저장돼요',
            onTap: () => _openUrl(kPrivacyUrl),
          ),
          _tile(
            icon: Icons.gavel_outlined,
            title: '이용 전 확인사항',
            onTap: _showDisclaimer,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
    child: Text(
      title,
      style: AppTextStyles.label.copyWith(color: AppColors.gray500),
    ),
  );

  Widget _tile({
    String? key,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) => ListTile(
    key: key == null ? null : ValueKey(key),
    leading: Icon(icon, color: AppColors.navy),
    title: Text(title, style: AppTextStyles.bodyLarge),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
    trailing: trailing ?? const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
