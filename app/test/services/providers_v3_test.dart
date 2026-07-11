import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
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
}
