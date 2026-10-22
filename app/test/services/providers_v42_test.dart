import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.4.2 — 같은 종목을 두 계좌에 나눠 보유 가능(계좌 단위 중복 판정).
///
/// 기존엔 corpCode 만으로 전역 중복 판정 → 두 번째 add 가 첫 번째를 덮어써
/// 일반계좌 보유분이 사라지고 배당이 비과세(ISA)로 새어 게이지가 과소집계됐다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('같은 corpCode 를 일반+ISA 두 계좌에 add → 둘 다 보존', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(holdingsProvider.notifier);
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 10,
        accountId: 'default_general',
      ),
    );
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 5,
        accountId: 'default_isa',
      ),
    );

    final holdings = container.read(holdingsProvider);
    expect(holdings.length, 2);
    expect(
      holdings.firstWhere((h) => h.accountId == 'default_general').shares,
      10,
    );
    expect(holdings.firstWhere((h) => h.accountId == 'default_isa').shares, 5);
  });

  test('같은 계좌 내 같은 종목 재추가 → 수량 갱신(중복 행 없음)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(holdingsProvider.notifier);
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 10,
        accountId: 'default_general',
      ),
    );
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 30,
        accountId: 'default_general',
      ),
    );

    final holdings = container.read(holdingsProvider);
    expect(holdings.length, 1);
    expect(holdings.single.shares, 30);
  });

  test('두 계좌에 나눠 보유 후 한 계좌 삭제 → 올바른 종목만 제거', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(holdingsProvider.notifier);
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 10,
        accountId: 'default_general',
      ),
    );
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 5,
        accountId: 'default_isa',
      ),
    );

    // 일반계좌 보유분(index 0) 삭제.
    final before = container.read(holdingsProvider);
    final generalIdx = before.indexWhere(
      (h) => h.accountId == 'default_general',
    );
    notifier.removeAt(generalIdx);

    final holdings = container.read(holdingsProvider);
    expect(holdings.length, 1);
    expect(holdings.single.accountId, 'default_isa');
    expect(holdings.single.shares, 5);
  });

  test('reassignAccount — 유저 연금계좌 삭제 후 default_pension 에 동일 corpCode 가 '
      '이미 있으면 병합(키 충돌 방지 — (corpCode,accountId) 유일성 유지)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(accountsProvider.notifier)
        .add(
          const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension),
        );
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(holdingsProvider.notifier);
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 10,
        accountId: 'default_pension_savings',
      ),
    );
    notifier.add(
      const Holding(
        corpCode: '005930',
        corpName: '삼성전자',
        shares: 7,
        accountId: 'u1',
      ),
    );

    // 유저 계좌 삭제 → u1 소속이 default_pension_savings 로 재배정.
    container.read(accountsProvider.notifier).remove('u1');
    await Future<void>.delayed(Duration.zero);

    final holdings = container.read(holdingsProvider);
    // 재배정 후 동일 (corpCode, accountId) 가 두 개 → 병합해 유일성 유지.
    // calendar_screen 의 sharesByAccount(Map) 가 (corpName|accountId) 유일성을
    // 전제하므로 병합하지 않으면 수량이 잘못 표시된다.
    expect(holdings.length, 1);
    expect(holdings.single.accountId, 'default_pension_savings');
    expect(holdings.single.shares, 17);
  });

  test('reassignAccount — 충돌 없는 재배정은 그대로 이동(수량 보존)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(accountsProvider.notifier)
        .add(
          const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension),
        );
    await Future<void>.delayed(Duration.zero);

    container
        .read(holdingsProvider.notifier)
        .add(
          const Holding(
            corpCode: '005930',
            corpName: '삼성전자',
            shares: 7,
            accountId: 'u1',
          ),
        );
    await Future<void>.delayed(Duration.zero);

    container.read(accountsProvider.notifier).remove('u1');
    await Future<void>.delayed(Duration.zero);

    final holdings = container.read(holdingsProvider);
    expect(holdings.single.accountId, 'default_pension_savings');
    expect(holdings.single.shares, 7);
  });
}
