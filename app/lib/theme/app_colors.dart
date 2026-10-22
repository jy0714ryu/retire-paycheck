import 'package:flutter/material.dart';

/// 은퇴월급 컬러 시스템 — v2 프라이빗 뱅킹 테마 (2026-10-22)
///
/// 아이보리 종이 바탕 · 잉크 네이비 · 샴페인 골드. 증권사 리서치 보고서·PB 운용보고서 톤.
/// 기존 상수 이름(navy·green·gray*)은 화면 코드 호환을 위해 유지하고 값만 교체했다.
/// - navy  = 잉크 네이비(주 색, 제목·금액·헤더)
/// - green = 짙은 샴페인 골드(강조·주요 버튼). 흰 글씨 대비 4.5:1 이상이 되도록 짙게 잡았다.
/// - success/warning/error 는 의미 색이라 골드와 분리.
class AppColors {
  AppColors._();

  // Primary — 잉크 네이비
  static const Color navy = Color(0xFF0F1E33);
  static const Color navyLight = Color(0xFF24395A);
  static const Color navyDark = Color(0xFF0A1422);

  // Accent — 샴페인 골드 (이름은 하위호환상 green 유지)
  static const Color green = Color(0xFF8C6D3F);
  static const Color greenLight = Color(0xFFC9AE7E);
  static const Color greenDark = Color(0xFF6E552F);
  static const Color gold = Color(0xFFA8854F); // 장식용(가는 선·작은 강조 텍스트) — 버튼 바탕엔 green 사용
  static const Color goldSoft = Color(0xFFEFE5D2);

  // Neutral — 아이보리 쪽으로 살짝 데운 회색
  static const Color gray50 = Color(0xFFFAF8F3);
  static const Color gray100 = Color(0xFFF1EDE4);
  static const Color gray200 = Color(0xFFE4DDCF);
  static const Color gray300 = Color(0xFFCFC6B5);
  static const Color gray400 = Color(0xFFA39C8F);
  static const Color gray500 = Color(0xFF6F6A60);
  static const Color gray600 = Color(0xFF555148);
  static const Color gray700 = Color(0xFF3A3731);
  static const Color gray800 = Color(0xFF24221E);
  static const Color gray900 = Color(0xFF16130F);

  // Semantic
  static const Color success = Color(0xFF3E7B5C);
  static const Color warning = Color(0xFFB5651D);
  static const Color error = Color(0xFFB03A2E);
  static const Color info = Color(0xFF2F5D8A);

  // Background
  static const Color background = Color(0xFFF6F3EC);
  static const Color surface = Color(0xFFFFFDF8);
  static const Color cardBackground = Color(0xFFFFFDF8);

  // Chart colors
  static const Color chartOptimal = Color(0xFF0F1E33);
  static const Color chartBaseline = Color(0xFFCFC6B5);
  static const Color chartSavings = Color(0xFFA8854F);
}
