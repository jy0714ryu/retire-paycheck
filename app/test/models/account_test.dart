import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';

void main() {
  test('기본 계좌 3개 — id·유형 고정', () {
    expect(kDefaultAccounts.length, 3);
    expect(kDefaultAccounts.map((a) => a.id),
        ['default_general', 'default_isa', 'default_pension']);
    expect(kDefaultAccounts.every((a) => a.isDefault), isTrue);
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
}
