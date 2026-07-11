import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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

  test('시나리오5 손상 데이터 — 깨진 json 이면 크래시 없이 버전만 기록', () async {
    SharedPreferences.setMockInitialValues({'retirement_input': '{broken'});
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 2);
  });
}
