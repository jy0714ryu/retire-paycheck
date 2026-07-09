// pension-compass에서 이식 (2026-07-09)
import 'package:flutter/material.dart';

/// 은퇴월급 컬러 시스템 (연금나침반 팔레트 재사용)
class AppColors {
  AppColors._();

  // Primary - 네이비 (신뢰)
  static const Color navy = Color(0xFF1A365D);
  static const Color navyLight = Color(0xFF2C5282);
  static const Color navyDark = Color(0xFF1A202C);

  // Accent - 그린 (절약/성장)
  static const Color green = Color(0xFF38A169);
  static const Color greenLight = Color(0xFF68D391);
  static const Color greenDark = Color(0xFF276749);

  // Neutral
  static const Color gray50 = Color(0xFFF7FAFC);
  static const Color gray100 = Color(0xFFEDF2F7);
  static const Color gray200 = Color(0xFFE2E8F0);
  static const Color gray300 = Color(0xFFCBD5E0);
  static const Color gray400 = Color(0xFFA0AEC0);
  static const Color gray500 = Color(0xFF718096);
  static const Color gray600 = Color(0xFF4A5568);
  static const Color gray700 = Color(0xFF2D3748);
  static const Color gray800 = Color(0xFF1A202C);
  static const Color gray900 = Color(0xFF171923);

  // Semantic
  static const Color success = Color(0xFF38A169);
  static const Color warning = Color(0xFFDD6B20);
  static const Color error = Color(0xFFE53E3E);
  static const Color info = Color(0xFF3182CE);

  // Background
  static const Color background = Color(0xFFF7FAFC);
  static const Color surface = Colors.white;
  static const Color cardBackground = Colors.white;

  // Chart colors
  static const Color chartOptimal = Color(0xFF3182CE);
  static const Color chartBaseline = Color(0xFFA0AEC0);
  static const Color chartSavings = Color(0xFF38A169);
}
