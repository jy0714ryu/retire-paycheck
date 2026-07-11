import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/interest_item.dart';

const int _kCurrentSchema = 2;

/// v1→v2 스키마 마이그레이션 — schema_version 가드로 1회만 실행(스펙 §1.5).
///
/// 구 필드(annual_interest_income)는 지우지 않는다 — 구버전 롤백 시 데이터
/// 유실 방지. Holding.accountId 는 fromJson 폴백이 처리하므로 여기서 손대지
/// 않는다.
Future<void> runMigrations(SharedPreferences prefs) async {
  final version = prefs.getInt('schema_version') ?? 1;
  if (version >= _kCurrentSchema) return;

  try {
    final raw = prefs.getString('retirement_input');
    if (raw != null && raw.isNotEmpty) {
      final input = jsonDecode(raw) as Map<String, dynamic>;

      // 1) 연 이자소득 → InterestItem 1개 (월 균등).
      final interest = (input['annual_interest_income'] as num?)?.toInt() ?? 0;
      if (interest > 0 && prefs.getString('interest_items') == null) {
        final item = InterestItem(
            id: 'migrated_v1', name: '이자소득', annualAmount: interest);
        await prefs.setString('interest_items', jsonEncode([item.toJson()]));
      }

      // 2) isWithdrawing 판정 결과를 명시 키로 고정.
      final withdrawing =
          ((input['monthly_pension_withdrawal'] as num?)?.toInt() ?? 0) > 0 ||
              ((input['monthly_other_withdrawal'] as num?)?.toInt() ?? 0) > 0;
      input['is_withdrawing'] = withdrawing;
      await prefs.setString('retirement_input', jsonEncode(input));
    }
  } catch (_) {
    // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 마이그레이션은 종료.
  }

  await prefs.setInt('schema_version', _kCurrentSchema);
}
