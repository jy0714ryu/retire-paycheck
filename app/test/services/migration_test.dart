import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('시나리오1 신규 설치 — 스킵·버전만 기록', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 2);
    expect(prefs.getString('interest_items'), isNull);
  });

  test('시나리오2 v1→v2 — 이자 항목 1개 생성·isWithdrawing 판정', () async {
    SharedPreferences.setMockInitialValues({
      'retirement_input': jsonEncode({
        'annual_interest_income': 1200000,
        'monthly_pension_withdrawal': 1000000,
        'current_age': 60,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    final items = jsonDecode(prefs.getString('interest_items')!) as List;
    expect(items.length, 1);
    expect(items.first['annual_amount'], 1200000);
    expect(items.first['months'], isEmpty); // 월 균등
    final input =
        jsonDecode(prefs.getString('retirement_input')!) as Map<String, dynamic>;
    expect(input['is_withdrawing'], isTrue);
    // 구 필드 보존 (롤백 안전 — Global Constraints).
    expect(input['annual_interest_income'], 1200000);
    expect(prefs.getInt('schema_version'), 2);
  });

  test('시나리오3 멱등성 — 2회 실행해도 이자 항목 1개', () async {
    SharedPreferences.setMockInitialValues({
      'retirement_input': jsonEncode(
          {'annual_interest_income': 1200000, 'current_age': 60}),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    await runMigrations(prefs);
    final items = jsonDecode(prefs.getString('interest_items')!) as List;
    expect(items.length, 1);
  });

  test('시나리오4 왕복 호환 — v2→v1 파서 재직렬화→v2 재로드 시 크래시·중복 없음, '
      'account_id 는 default_general 폴백', () async {
    // v2 로 이미 마이그레이션 완료된 상태에서, v1 파서가 모르는 키
    // (is_withdrawing·account_id)를 모른 채 재직렬화했다고 가정
    // (설계 문서 §1.5: "구버전 fromJson 은 모르는 키를 무시하므로 신→구→신 왕복 안전").
    SharedPreferences.setMockInitialValues({
      'schema_version': 2,
      'retirement_input': jsonEncode({
        'pension_savings': 100000000,
        'irp_balance': 0,
        'isa_balance': 0,
        'current_age': 60,
        'monthly_pension_withdrawal': 1000000,
        'monthly_other_withdrawal': 0,
        'annual_interest_income': 1200000,
        // is_withdrawing 키 없음 — v1 파서가 모르는 키라 재직렬화 시 탈락.
      }),
      'interest_items': jsonEncode([
        {
          'id': 'migrated_v1',
          'name': '이자소득',
          'annual_amount': 1200000,
          'months': [],
        },
      ]),
      'holdings': jsonEncode([
        {'corp_code': 'A', 'corp_name': 'A사', 'shares': 1000},
        // account_id 키 없음 — v1 파서가 모르는 키라 재직렬화 시 탈락.
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    // schema_version 이 이미 2 이므로 재실행해도 no-op(가드) — 크래시 없이 통과해야 한다.
    await runMigrations(prefs);

    expect(prefs.getInt('schema_version'), 2);

    // 이자 항목 중복 생성 없음(여전히 1개 — 재마이그레이션 스킵 확인).
    final items = jsonDecode(prefs.getString('interest_items')!) as List;
    expect(items.length, 1);

    // retirement_input 은 is_withdrawing 키 부재 상태 그대로 보존(migration.dart 가
    // schema_version 가드로 손대지 않음) — 모델 레벨 fromJson 폴백이 인출액>0 규칙으로
    // 재판정한다.
    final input =
        jsonDecode(prefs.getString('retirement_input')!) as Map<String, dynamic>;
    expect(input.containsKey('is_withdrawing'), isFalse);
    expect(RetirementInput.fromJson(input).isWithdrawing, isTrue);

    // holdings 도 account_id 키 부재 상태 그대로 보존 — 모델 레벨에서
    // default_general 로 안전 폴백(크래시·유실 없음).
    final holdings = jsonDecode(prefs.getString('holdings')!) as List;
    expect((holdings.first as Map).containsKey('account_id'), isFalse);
    final holding = Holding.fromJson(holdings.first as Map<String, dynamic>);
    expect(holding.accountId, 'default_general');
  });

  test('시나리오5 손상 데이터 — 깨진 json 이면 크래시 없이 버전만 기록', () async {
    SharedPreferences.setMockInitialValues({'retirement_input': '{broken'});
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 2);
  });
}
