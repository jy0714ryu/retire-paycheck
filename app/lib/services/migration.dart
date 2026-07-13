import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/interest_item.dart';

const int _kCurrentSchema = 4;

/// v1→v2→v3→v4 스키마 마이그레이션 — schema_version 가드로 각 단계 1회만 실행(스펙 §1.5).
///
/// 구 필드(annual_interest_income 등 flat 잔액·인출 필드)는 지우지 않는다 —
/// 구버전 롤백 시 데이터 유실 방지. Holding.accountId 는 fromJson 폴백이
/// 처리하므로 여기서 손대지 않는다(단, v3 의 `default_pension` 재기록은 예외).
Future<void> runMigrations(SharedPreferences prefs) async {
  final version = prefs.getInt('schema_version') ?? 1;
  if (version >= _kCurrentSchema) return;

  if (version < 2) {
    try {
      final raw = prefs.getString('retirement_input');
      if (raw != null && raw.isNotEmpty) {
        final input = jsonDecode(raw) as Map<String, dynamic>;

        // 1) 연 이자소득 → InterestItem 1개 (월 균등).
        final interest =
            (input['annual_interest_income'] as num?)?.toInt() ?? 0;
        if (interest > 0 && prefs.getString('interest_items') == null) {
          final item = InterestItem(
              id: 'migrated_v1', name: '이자소득', annualAmount: interest);
          await prefs.setString('interest_items', jsonEncode([item.toJson()]));
        }

        // 2) isWithdrawing 판정 결과를 명시 키로 고정.
        final withdrawing = ((input['monthly_pension_withdrawal'] as num?)
                        ?.toInt() ??
                    0) >
                0 ||
            ((input['monthly_other_withdrawal'] as num?)?.toInt() ?? 0) > 0;
        input['is_withdrawing'] = withdrawing;
        await prefs.setString('retirement_input', jsonEncode(input));
      }
    } catch (_) {
      // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 마이그레이션은 종료.
    }
  }

  if (version < 3) {
    // 1) flat 잔액·인출 필드 → default_account_overrides.
    //    이미 오버라이드가 존재하면(유저가 계좌 화면에서 직접 수정했을 수
    //    있으므로) 이 단계는 건너뛴다 — 멱등 이중 안전망.
    // 2) 폐지된 default_pension → default_pension_savings 재기록.
    // (M3) 두 단계는 서로 독립적인 저장소(overrides / holdings)를 건드리므로
    // try/catch 를 분리한다 — 한쪽에서 예외가 나도 다른 쪽 재기록이 스킵된
    // 채 schema_version 이 올라가 재실행 기회를 잃는 것을 막는다.
    try {
      if (prefs.getString('default_account_overrides') == null) {
        final raw = prefs.getString('retirement_input');
        if (raw != null && raw.isNotEmpty) {
          final input = jsonDecode(raw) as Map<String, dynamic>;
          final overrides = <String, Map<String, int>>{};

          void setIfNonzero(String accountId, String key, num? value) {
            final v = value?.toInt() ?? 0;
            if (v == 0) return;
            overrides.putIfAbsent(accountId, () => {})[key] = v;
          }

          setIfNonzero('default_pension_savings', 'balance',
              input['pension_savings'] as num?);
          setIfNonzero(
              'default_irp', 'balance', input['irp_balance'] as num?);
          setIfNonzero(
              'default_isa', 'balance', input['isa_balance'] as num?);
          setIfNonzero('default_pension_savings', 'monthly_withdrawal',
              input['monthly_pension_withdrawal'] as num?);
          setIfNonzero('default_isa', 'monthly_withdrawal',
              input['monthly_other_withdrawal'] as num?);

          if (overrides.isNotEmpty) {
            await prefs.setString(
                'default_account_overrides', jsonEncode(overrides));
          }
        }
      }
    } catch (_) {
      // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 다음 단계로 진행.
    }

    try {
      final holdingsRaw = prefs.getString('holdings');
      if (holdingsRaw != null && holdingsRaw.isNotEmpty) {
        final holdings = jsonDecode(holdingsRaw) as List<dynamic>;
        var changed = false;
        for (final h in holdings) {
          if (h is Map<String, dynamic> &&
              h['account_id'] == 'default_pension') {
            h['account_id'] = 'default_pension_savings';
            changed = true;
          }
        }
        if (changed) {
          await prefs.setString('holdings', jsonEncode(holdings));
        }
      }
    } catch (_) {
      // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 마이그레이션은 종료.
    }
  }

  if (version < 4) {
    // 구 전역 `retirement_input.is_withdrawing` 을 계좌별 인출 개시 여부로 전파.
    // 전역 필드 자체는 지우지 않는다(롤백 안전). false 면 계좌별 기본값(false)을
    // 그대로 두고 아무것도 하지 않는다.
    // (M4) 오버라이드(default_account_overrides)와 유저 계좌(accounts)는 서로
    // 독립적인 저장소이므로 v3 패턴을 따라 try/catch 를 분리한다 — 한쪽 예외가
    // 다른 쪽 전파를 막지 않도록.
    try {
      final raw = prefs.getString('retirement_input');
      if (raw != null && raw.isNotEmpty) {
        final input = jsonDecode(raw) as Map<String, dynamic>;
        final globalWithdrawing = input['is_withdrawing'] as bool? ?? false;
        if (globalWithdrawing) {
          final overridesRaw = prefs.getString('default_account_overrides');
          final overrides = overridesRaw != null && overridesRaw.isNotEmpty
              ? jsonDecode(overridesRaw) as Map<String, dynamic>
              : <String, dynamic>{};

          // ISA·연금 기본 계좌만 대상 — default_general 은 인출 개념 없음.
          const targets = [
            'default_isa',
            'default_pension_savings',
            'default_irp',
          ];
          var changed = false;
          for (final id in targets) {
            final existing = overrides[id];
            final entry = existing is Map<String, dynamic>
                ? existing
                : <String, dynamic>{};
            // 이미 is_withdrawing 이 기록돼 있으면 유저 수정으로 보고 덮어쓰지
            // 않는다(v3 패턴 답습 — 멱등 이중 안전망).
            if (!entry.containsKey('is_withdrawing')) {
              entry['is_withdrawing'] = true;
              overrides[id] = entry;
              changed = true;
            }
          }
          if (changed) {
            await prefs.setString(
                'default_account_overrides', jsonEncode(overrides));
          }
        }
      }
    } catch (_) {
      // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 다음 단계로 진행.
    }

    try {
      final raw = prefs.getString('retirement_input');
      if (raw != null && raw.isNotEmpty) {
        final input = jsonDecode(raw) as Map<String, dynamic>;
        final globalWithdrawing = input['is_withdrawing'] as bool? ?? false;
        if (globalWithdrawing) {
          final accountsRaw = prefs.getString('accounts');
          if (accountsRaw != null && accountsRaw.isNotEmpty) {
            final accounts = jsonDecode(accountsRaw) as List<dynamic>;
            var changed = false;
            for (final a in accounts) {
              if (a is Map<String, dynamic> &&
                  (a['type'] == 'isa' || a['type'] == 'pension') &&
                  a['is_withdrawing'] != true) {
                a['is_withdrawing'] = true;
                changed = true;
              }
            }
            if (changed) {
              await prefs.setString('accounts', jsonEncode(accounts));
            }
          }
        }
      }
    } catch (_) {
      // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 마이그레이션은 종료.
    }
  }

  await prefs.setInt('schema_version', _kCurrentSchema);
}
