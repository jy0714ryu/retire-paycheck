import 'package:flutter/material.dart';
import 'app_colors.dart';

/// 은퇴월급 타이포그래피 — v2 프라이빗 뱅킹 (2026-10-22)
///
/// 본문 글꼴(IBM Plex Sans KR)은 ThemeData.fontFamily 로 전역 적용.
/// 큰 제목·큰 금액 = 명조(Noto Serif KR), 표·목록 숫자 = 고정폭 숫자(tabular figures).
class AppTextStyles {
  AppTextStyles._();

  static const String serif = 'NotoSerifKR';
  static const String sans = 'PlexSansKR';
  static const String mono = 'PlexMono';
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  // Headings
  static const TextStyle h1 = TextStyle(
    fontFamily: serif,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.gray900,
    height: 1.3,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: serif,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppColors.gray900,
    height: 1.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.gray800,
    height: 1.4,
  );

  static const TextStyle h4 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: AppColors.gray800,
    height: 1.4,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.gray700,
    height: 1.5,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.gray600,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.gray500,
    height: 1.5,
  );

  // Caption
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.gray500,
    height: 1.4,
  );

  static const TextStyle captionBold = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.gray600,
    height: 1.4,
  );

  // Numbers (금액 표시용)
  static const TextStyle numberLarge = TextStyle(
    fontFamily: serif,
    fontFeatures: tabular,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
    height: 1.2,
  );

  static const TextStyle number = TextStyle(
    fontFamily: serif,
    fontFeatures: tabular,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.navy,
    height: 1.2,
  );

  static const TextStyle numberSmall = TextStyle(
    fontFamily: serif,
    fontFeatures: tabular,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.gray800,
    height: 1.3,
  );

  // Labels
  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.gray700,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.gray500,
    height: 1.4,
  );

  // Button
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.4,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.4,
  );

  /// 목록·표 금액 — 화면 공통 규칙(v2.3.1): 큰 핵심 숫자만 명조, 목록 금액은 이 스타일
  /// (본문 글꼴 + 숫자 폭 고정)으로 통일한다.
  static const TextStyle amount = TextStyle(
    fontFamily: sans,
    fontFeatures: tabular,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.navy,
  );
}
