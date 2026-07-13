import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기본 계좌 인출 개시 토글 — effective 반영·영속', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(accountsProvider.notifier)
        .updateDefaults('default_pension_savings', isWithdrawing: true);
    await Future<void>.delayed(Duration.zero);

    final eff = container.read(effectiveAccountsProvider);
    expect(eff.firstWhere((a) => a.id == 'default_pension_savings').isWithdrawing,
        isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_account_overrides'),
        contains('is_withdrawing'));
  });

  test('유저 계좌 인출 토글 갱신', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(accountsProvider.notifier).add(
        const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension));
    container.read(accountsProvider.notifier).updateUser('u1', isWithdrawing: true);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(effectiveAccountsProvider)
        .firstWhere((a) => a.id == 'u1').isWithdrawing, isTrue);
  });
}
