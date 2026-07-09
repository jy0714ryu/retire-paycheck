// pension-compass에서 이식 (2026-07-09) — 문구를 "세금·현금흐름 추정치" 맥락으로 수정
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 면책조항 다이얼로그 위젯
class DisclaimerDialog extends StatelessWidget {
  final VoidCallback onAccept;

  const DisclaimerDialog({super.key, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(26),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.gavel,
                color: AppColors.warning,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),

            // 제목
            const Text(
              '이용 전 확인사항',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            // 면책조항 내용
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DisclaimerItem(
                    icon: Icons.info_outline,
                    text: '본 앱의 현금흐름·세금 계산은 현행 세법 기준의 추정치이며, 투자·세무 자문이 아닙니다.',
                  ),
                  SizedBox(height: 12),
                  _DisclaimerItem(
                    icon: Icons.calendar_month,
                    text: '배당 지급월은 예상이며 회사별로 다를 수 있습니다. 실제 지급액·시기와 차이가 날 수 있습니다.',
                  ),
                  SizedBox(height: 12),
                  _DisclaimerItem(
                    icon: Icons.account_balance,
                    text: '정확한 세금·건강보험료는 세무사 및 금융기관과 상담하시기 바랍니다.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 동의 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '확인했습니다',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DisclaimerItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.gray600),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.gray600,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
