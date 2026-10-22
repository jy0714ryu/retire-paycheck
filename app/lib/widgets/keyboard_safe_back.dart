import 'package:flutter/material.dart';

/// 입력칸에 커서가 있으면 키보드만 내리고 true — 뒤로 가기를 소비했다는 뜻.
///
/// 삼성 키보드의 "키보드 내리기(▽)"는 안드로이드 뒤로 가기 신호로 전달된다.
/// 키보드가 이미 닫히는 중이면 그 신호가 앱까지 와서 시트·화면이 닫히거나 앱이 종료됐다.
bool dismissKeyboardIfFocused() {
  final focus = FocusManager.instance.primaryFocus;
  final ctx = focus?.context;
  if (focus == null || ctx == null) return false;
  final isText =
      ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  if (!isText) return false;
  focus.unfocus();
  return true;
}

/// 시트·전체화면 입력 화면용 — 뒤로 가기가 오면 먼저 키보드를 내리고,
/// 입력 중이 아닐 때만 실제로 닫는다([onBack] 미지정 시 pop).
class KeyboardSafeBack extends StatelessWidget {
  const KeyboardSafeBack({super.key, required this.child, this.onBack});

  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || dismissKeyboardIfFocused()) return;
        if (onBack != null) {
          onBack!();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}
