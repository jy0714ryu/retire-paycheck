import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기본 계좌 잔액 오버라이드 — effective 반영·영속', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(accountsProvider.notifier)
        .updateDefaults('default_isa', balance: 10000000, monthlyWithdrawal: 1200000);
    await Future<void>.delayed(Duration.zero);

    final effective = container.read(effectiveAccountsProvider);
    final isa = effective.firstWhere((a) => a.id == 'default_isa');
    expect(isa.balance, 10000000);
    expect(isa.monthlyWithdrawal, 1200000);
    expect(effective.length, 4); // 기본 4개, 유저 0

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_account_overrides'), contains('default_isa'));
  });

  test('유저 계좌 잔액 갱신 + effective 에 기본4+유저 순서로 노출', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(accountsProvider.notifier).add(
        const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension));
    container.read(accountsProvider.notifier).updateUser('u1', monthlyWithdrawal: 400000);
    await Future<void>.delayed(Duration.zero);

    final effective = container.read(effectiveAccountsProvider);
    expect(effective.length, 5);
    expect(effective.last.monthlyWithdrawal, 400000);
  });

  test(
      '연금 유저계좌 삭제 → 소속 종목이 default_pension_savings 로 재배정 '
      '(C1 회귀 — dangling default_pension 금지)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(accountsProvider.notifier).add(
        const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension));
    await Future<void>.delayed(Duration.zero);

    container.read(holdingsProvider.notifier).add(
        const Holding(corpCode: '005930', corpName: '삼성전자', shares: 10, accountId: 'u1'));
    await Future<void>.delayed(Duration.zero);

    container.read(accountsProvider.notifier).remove('u1');
    await Future<void>.delayed(Duration.zero);

    final holdings = container.read(holdingsProvider);
    expect(holdings.single.accountId, 'default_pension_savings');

    final accounts = container.read(accountsProvider);
    final resolved = resolveAccount('default_pension_savings', accounts);
    expect(resolved, isNotNull);
    expect(resolved!.type, AccountType.pension);
  });
}
