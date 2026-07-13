import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';

void main() {
  test('기본 계좌 4개 — id·유형 고정 (연금저축·IRP 분리)', () {
    expect(kDefaultAccounts.map((a) => a.id), [
      'default_general', 'default_isa', 'default_pension_savings',
      'default_irp',
    ]);
    expect(
      kDefaultAccounts.map((a) => a.type),
      [AccountType.general, AccountType.isa, AccountType.pension,
        AccountType.pension],
    );
    expect(kDefaultAccounts.every((a) => a.isDefault), isTrue);
  });

  test('balance·monthlyWithdrawal json 왕복 + 레거시 폴백 0', () {
    final a = Account(
        id: 'u1', name: '미래에셋 IRP', type: AccountType.pension,
        balance: 5000000, monthlyWithdrawal: 400000);
    expect(Account.fromJson(a.toJson()), a);
    final legacy = Account.fromJson({'id': 'x', 'name': 'y', 'type': 'isa'});
    expect(legacy.balance, 0);
    expect(legacy.monthlyWithdrawal, 0);
  });

  test('copyWith — 잔액·인출 갱신', () {
    const base = Account(id: 'default_isa', name: 'ISA', type: AccountType.isa);
    final updated = base.copyWith(balance: 10000000, monthlyWithdrawal: 1200000);
    expect(updated.balance, 10000000);
    expect(updated.id, 'default_isa');
  });

  test('resolveAccount — 기본 계좌·유저 계좌·미지 id 폴백', () {
    final user = Account(id: 'u1', name: '미래에셋 ISA', type: AccountType.isa);
    expect(resolveAccount('default_isa', [user])!.type, AccountType.isa);
    expect(resolveAccount('u1', [user])!.name, '미래에셋 ISA');
    // 삭제된 계좌 id → null (호출부가 default_general 로 폴백).
    expect(resolveAccount('ghost', [user]), isNull);
  });

  test('json 왕복', () {
    final a = Account(id: 'u1', name: '삼성 IRP', type: AccountType.pension);
    expect(Account.fromJson(a.toJson()), a);
  });

  test('fromJson — 미지 type 문자열은 general 폴백', () {
    final a = Account.fromJson({'id': 'x', 'name': 'y', 'type': 'weird'});
    expect(a.type, AccountType.general);
  });

  test('isWithdrawing json 왕복 + 레거시 폴백 false', () {
    final a = Account(
        id: 'default_isa', name: 'ISA', type: AccountType.isa,
        balance: 10000000, monthlyWithdrawal: 1200000, isWithdrawing: true);
    expect(Account.fromJson(a.toJson()).isWithdrawing, isTrue);
    final legacy = Account.fromJson(
        {'id': 'default_irp', 'name': 'IRP', 'type': 'pension'});
    expect(legacy.isWithdrawing, isFalse);
  });

  test('copyWith — isWithdrawing 갱신', () {
    const base = Account(id: 'default_isa', name: 'ISA', type: AccountType.isa);
    expect(base.copyWith(isWithdrawing: true).isWithdrawing, isTrue);
    expect(base.copyWith(balance: 100).isWithdrawing, isFalse); // 미지정 시 유지
  });
}
