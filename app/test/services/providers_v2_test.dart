import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('계좌 추가·영속·삭제 시 종목 기본계좌 이동', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(accountsProvider.notifier).add(
        const Account(id: 'u1', name: '미래에셋 ISA', type: AccountType.isa));
    container.read(holdingsProvider.notifier).add(const Holding(
        corpCode: 'c1', corpName: 'ISA주', shares: 1, accountId: 'u1'));
    await Future<void>.delayed(Duration.zero); // persist flush

    container.read(accountsProvider.notifier).remove('u1');
    await Future<void>.delayed(Duration.zero);
    expect(container.read(holdingsProvider).single.accountId, 'default_isa');
    expect(container.read(accountsProvider), isEmpty);
  });
}
