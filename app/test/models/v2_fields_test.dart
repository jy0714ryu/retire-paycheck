import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/interest_item.dart';
import 'package:retire_paycheck/models/retirement_input.dart';

void main() {
  test('Holding — v1 json(account_id 없음)은 default_general', () {
    final h = Holding.fromJson(
        {'corp_code': 'c1', 'corp_name': '삼성전자', 'shares': 12});
    expect(h.accountId, 'default_general');
  });

  test('Holding — accountId json 왕복', () {
    final h = Holding(
        corpCode: 'c1', corpName: '삼성전자', shares: 12, accountId: 'u1');
    expect(Holding.fromJson(h.toJson()).accountId, 'u1');
  });

  test('RetirementInput — v1 json: 인출액>0 이면 isWithdrawing=true', () {
    final on = RetirementInput.fromJson(
        {'monthly_pension_withdrawal': 1000000, 'current_age': 60});
    final off = RetirementInput.fromJson({'current_age': 60});
    expect(on.isWithdrawing, isTrue);
    expect(off.isWithdrawing, isFalse);
  });

  test('RetirementInput — is_withdrawing 명시 키가 판정보다 우선', () {
    final r = RetirementInput.fromJson({
      'monthly_pension_withdrawal': 1000000,
      'current_age': 60,
      'is_withdrawing': false,
    });
    expect(r.isWithdrawing, isFalse);
  });

  test('InterestItem — json 왕복 + 빈 months=월 균등', () {
    final i = InterestItem(
        id: 'i1', name: '정기예금', annualAmount: 1200000, months: const [6]);
    expect(InterestItem.fromJson(i.toJson()), i);
    final even = InterestItem.fromJson(
        {'id': 'i2', 'name': '파킹', 'annual_amount': 360000});
    expect(even.months, isEmpty);
  });
}
