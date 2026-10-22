import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 리뷰 요청 (연금나침반 InAppReviewService 이식, v2.2).
///
/// 계획 결과를 3번째 볼 때부터, 절감액이 10만원 이상이면 평생 한 번만 요청한다.
/// Play 가 실제로 띄울지는 Play 정책이 정한다(빈도 제한).
class ReviewPrompt {
  ReviewPrompt._();

  static const _countKey = 'plan_view_count';
  static const _doneKey = 'review_requested';
  static const minViews = 3;
  static const minSavings = 100000;

  /// 조건 판정만 (테스트용 순수 함수).
  static bool shouldAsk({
    required int views,
    required bool alreadyAsked,
    required int savings,
  }) => !alreadyAsked && views >= minViews && savings >= minSavings;

  static Future<void> onPlanViewed(int savings) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final views = (prefs.getInt(_countKey) ?? 0) + 1;
      await prefs.setInt(_countKey, views);
      final asked = prefs.getBool(_doneKey) ?? false;
      if (!shouldAsk(views: views, alreadyAsked: asked, savings: savings)) {
        return;
      }
      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;
      await review.requestReview();
      await prefs.setBool(_doneKey, true);
    } catch (_) {
      // 리뷰 요청 실패는 앱 동작과 무관 — 조용히 넘긴다.
    }
  }
}
