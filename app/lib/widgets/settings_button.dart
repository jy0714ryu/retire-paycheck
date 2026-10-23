import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// 앱바 우상단 톱니 — 설정 화면으로 이동.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('settingsButton'),
      icon: const Icon(Icons.settings_outlined),
      tooltip: '설정',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    );
  }
}
