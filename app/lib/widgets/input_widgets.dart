// pension-compass에서 이식 (2026-07-09) — InputSectionCard·AmountInputField·NumberInputField 재사용
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 금액 입력 필드
class AmountInputField extends StatefulWidget {
  final String label;
  final String? hint;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;
  final bool enabled;
  final String? helperText;

  const AmountInputField({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
    this.suffix = '만원',
    this.enabled = true,
    this.helperText,
  });

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  late TextEditingController _controller;
  final _formatter = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value > 0 ? _formatter.format(widget.value ~/ 10000) : '',
    );
  }

  @override
  void didUpdateWidget(AmountInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newText = widget.value > 0 ? _formatter.format(widget.value ~/ 10000) : '';
    if (_controller.text != newText && !_controller.text.contains(newText)) {
      _controller.text = newText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.label),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            _ThousandsSeparatorFormatter(),
          ],
          decoration: InputDecoration(
            hintText: widget.hint ?? '0',
            suffixText: widget.suffix,
            filled: true,
            fillColor: widget.enabled ? Colors.white : AppColors.gray100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gray200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gray200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.navy, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          style: AppTextStyles.bodyLarge.copyWith(
            color: AppColors.gray800,
          ),
          onChanged: (text) {
            final cleanText = text.replaceAll(',', '');
            final value = int.tryParse(cleanText) ?? 0;
            widget.onChanged(value * 10000); // 만원 단위 → 원 단위
          },
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
          ),
        ],
      ],
    );
  }
}

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  final _formatter = NumberFormat('#,###');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final cleanText = newValue.text.replaceAll(',', '');
    final value = int.tryParse(cleanText);
    
    if (value == null) {
      return oldValue;
    }

    final formatted = _formatter.format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// 숫자 입력 필드 (나이 등)
class NumberInputField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;
  final int min;
  final int max;

  const NumberInputField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix = '',
    this.min = 0,
    this.max = 100,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: value > min
                  ? () => onChanged(value - 1)
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.navy,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Text(
                  '$value$suffix',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h4,
                ),
              ),
            ),
            IconButton(
              onPressed: value < max
                  ? () => onChanged(value + 1)
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.navy,
            ),
          ],
        ),
      ],
    );
  }
}

/// 입력 섹션 카드
class InputSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const InputSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Icon(icon, color: AppColors.navy, size: 24),
              const SizedBox(width: 8),
              Text(title, style: AppTextStyles.h4),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

/// 주요 버튼
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          disabledBackgroundColor: AppColors.gray300,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(text, style: AppTextStyles.button),
      ),
    );
  }
}
