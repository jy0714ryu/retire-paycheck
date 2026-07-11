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
    expect(prefs.getInt('schema_version'), 3);
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
    expect(prefs.getInt('schema_version'), 3);
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

    // schema_version 이 이미 2 이므로 v2 블록은 재실행되지 않는다(가드) — 다만
    // v3 블록은 version<3 이라 이번에 처음 수행된다. 크래시 없이 통과해야 한다.
    await runMigrations(prefs);

    expect(prefs.getInt('schema_version'), 3);

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
    expect(prefs.getInt('schema_version'), 3);
  });

  test('v2→v3 — flat 잔액·인출이 기본 계좌 오버라이드로 이관', () async {
    SharedPreferences.setMockInitialValues({
      'schema_version': 2,
      'retirement_input': jsonEncode({
        'pension_savings': 10000000, 'irp_balance': 5000000, 'isa_balance': 3000000,
        'monthly_pension_withdrawal': 1200000, 'monthly_other_withdrawal': 300000,
        'current_age': 60, 'is_withdrawing': true,
      }),
      'holdings': jsonEncode([
        {'corp_code': 'c1', 'corp_name': '연금주', 'shares': 5, 'account_id': 'default_pension'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);

    final ov = jsonDecode(prefs.getString('default_account_overrides')!) as Map<String, dynamic>;
    expect(ov['default_pension_savings']['balance'], 10000000);
    expect(ov['default_pension_savings']['monthly_withdrawal'], 1200000);
    expect(ov['default_irp']['balance'], 5000000);
    expect(ov['default_isa']['balance'], 3000000);
    expect(ov['default_isa']['monthly_withdrawal'], 300000);

    final holdings = jsonDecode(prefs.getString('holdings')!) as List;
    expect(holdings.first['account_id'], 'default_pension_savings');

    // flat 필드 보존 (v2 롤백 안전).
    final input = jsonDecode(prefs.getString('retirement_input')!) as Map<String, dynamic>;
    expect(input['pension_savings'], 10000000);
    expect(prefs.getInt('schema_version'), 3);
  });

  test('v3 멱등 — 재실행해도 오버라이드 불변', () async {
    SharedPreferences.setMockInitialValues({
      'schema_version': 2,
      'retirement_input': jsonEncode({
        'pension_savings': 10000000, 'irp_balance': 5000000, 'isa_balance': 3000000,
        'monthly_pension_withdrawal': 1200000, 'monthly_other_withdrawal': 300000,
        'current_age': 60, 'is_withdrawing': true,
      }),
      'holdings': jsonEncode([
        {'corp_code': 'c1', 'corp_name': '연금주', 'shares': 5, 'account_id': 'default_pension'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);

    // 유저가 이후 앱에서 오버라이드를 직접 수정했다고 가정 — 마이그레이션 재실행이
    // 이를 덮어쓰면 안 된다(스펙: default_account_overrides 존재 시 1단계 스킵).
    // schema_version 을 다시 2로 되돌려 v3 블록 내부의 멱등 가드(존재 시 스킵)
    // 자체를 직접 검증한다(단순 상단 version>=schema 가드에 기대지 않음).
    await prefs.setString(
      'default_account_overrides',
      jsonEncode({
        'default_pension_savings': {'balance': 99999999, 'monthly_withdrawal': 1200000},
        'default_irp': {'balance': 5000000, 'monthly_withdrawal': 0},
        'default_isa': {'balance': 3000000, 'monthly_withdrawal': 300000},
      }),
    );
    await prefs.setInt('schema_version', 2);

    await runMigrations(prefs);

    final ov = jsonDecode(prefs.getString('default_account_overrides')!) as Map<String, dynamic>;
    expect(ov['default_pension_savings']['balance'], 99999999);
  });

  test('v1(버전 없음)→3 직행 — v2 단계(이자·isWithdrawing)와 v3 단계 모두 수행', () async {
    SharedPreferences.setMockInitialValues({
      'retirement_input': jsonEncode({
        'annual_interest_income': 1200000, 'monthly_pension_withdrawal': 500000,
        'current_age': 60,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 3);
    expect(jsonDecode(prefs.getString('interest_items')!), hasLength(1));
    final ov = jsonDecode(prefs.getString('default_account_overrides')!) as Map<String, dynamic>;
    expect(ov['default_pension_savings']['monthly_withdrawal'], 500000);
  });
}
