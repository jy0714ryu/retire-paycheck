# 은퇴월급 v3 — 계좌 중심 IA 재설계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 계좌를 최상위 컨테이너로 올려 종목·잔액·월 인출을 계좌 카드 안으로 통합하고, ISA·연금 정보의 3중 중복을 제거한다.

**Architecture:** `Account` 모델이 balance·monthlyWithdrawal 을 흡수하고, 기본 계좌가 3→4개(연금저축·IRP 분리)가 된다. 엔진은 인출 소스만 계좌 합산으로 재배선(계산 규칙·표시값 불변). 입력 탭은 계좌 카드 리스트로 전면 재구성. 스펙: `docs/2026-07-12-v3-account-centric-design.md` (SSOT).

**Tech Stack:** Flutter/Dart, flutter_riverpod, SharedPreferences, flutter_test.

## Global Constraints

- 금액 전부 `int` 원 단위, 세율 결과 `.round()`. 세금 분기 규칙은 v2 그대로 (일반 15.4%/ISA 0/연금 재투자, 게이지 동일 집계값).
- 기본 계좌 id 는 정확히 `default_general` / `default_isa` / `default_pension_savings` / `default_irp`. **구 id `default_pension` 을 참조하는 저장분은 마이그레이션에서 `default_pension_savings` 로 이관** (dangling → general 폴백으로 세금이 틀어지는 것 방지).
- 마이그레이션은 `schema_version` < 3 에서 1회 실행(멱등). 구 flat 필드(`pension_savings`·`irp_balance`·`isa_balance`·`monthly_pension_withdrawal`·`monthly_other_withdrawal`)는 **삭제·수정 금지**(v2 롤백 안전). `RetirementInput` 모델은 손대지 않는다 — UI·엔진이 참조를 끊을 뿐.
- 기존 테스트는 **의도 변경이 있는 것만** 스펙에 맞게 수정하고(엔진 인출 소스, 입력 탭 구조), 계산 기대값은 불변이어야 한다.
- 작업 브랜치 `feat/v3-account-centric` (main 직접 커밋 금지). 커밋 메시지 끝: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 신규 문구 한국어·기존 톤. `dart analyze lib test` clean (flutter analyze 는 한글 경로 LSP 크래시 있음 — 사용 금지).
- 자산 정보 기기 밖 전송 금지.

## File Structure

| 파일 | 책임 |
|---|---|
| Modify `app/lib/models/account.dart` | balance·monthlyWithdrawal 필드, 기본 계좌 4개 |
| Modify `app/lib/providers/app_providers.dart` | 기본 계좌 오버라이드 스토어 + `effectiveAccountsProvider` |
| Modify `app/lib/services/migration.dart` | schema 3 단계 (잔액·인출 이관 + default_pension 종목 이관) |
| Modify `app/lib/services/cashflow_engine.dart` | 인출 소스를 계좌 합산으로 재배선 |
| Modify `app/lib/screens/input_screen.dart` | 계좌 카드 리스트 전면 재구성 |
| Modify `app/lib/screens/calendar_screen.dart` | `_AddHoldingSheet` 계좌 선택 제거(계좌 컨텍스트 주입), effectiveAccounts 배선 |
| Modify `app/lib/screens/gauge_screen.dart` | effectiveAccounts 배선 |

---

### Task 0: 브랜치 생성

- [ ] `cd ~/Workspace/retire-paycheck && git checkout -b feat/v3-account-centric`

---

### Task 1: Account 모델 확장 + 기본 계좌 4개

**Files:**
- Modify: `app/lib/models/account.dart`
- Test: `app/test/models/account_test.dart` (기존 파일에 케이스 추가·수정)

**Interfaces:**
- Produces: `Account{id, name, type, int balance = 0, int monthlyWithdrawal = 0}` (json 키 `balance`/`monthly_withdrawal`, 없으면 0), `Account copyWith(...)`, `kDefaultAccounts` 4개 (id: default_general/default_isa/default_pension_savings/default_irp, 이름: 일반계좌/ISA/연금저축/IRP), `resolveAccount` 시그니처 불변.

- [ ] **Step 1: 실패 테스트** — account_test.dart 의 "기본 계좌 3개" 테스트를 교체 + 신규 케이스:

```dart
test('기본 계좌 4개 — id·유형 고정 (연금저축·IRP 분리)', () {
  expect(kDefaultAccounts.map((a) => a.id), [
    'default_general', 'default_isa', 'default_pension_savings', 'default_irp',
  ]);
  expect(
    kDefaultAccounts.map((a) => a.type),
    [AccountType.general, AccountType.isa, AccountType.pension, AccountType.pension],
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
```

- [ ] **Step 2:** `cd app && flutter test test/models/account_test.dart` → FAIL
- [ ] **Step 3: 구현** — account.dart:

```dart
class Account {
  final String id;
  final String name;
  final AccountType type;

  /// 현금성 잔액(원) — ISA·연금 계좌 전용, 일반계좌는 항상 0 (UI 미노출).
  final int balance;

  /// 월 인출액(원) — 인출 모드 ON 일 때 달력·세금에 반영. 일반계좌는 항상 0.
  final int monthlyWithdrawal;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.monthlyWithdrawal = 0,
  });

  Account copyWith({String? name, int? balance, int? monthlyWithdrawal}) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type,
        balance: balance ?? this.balance,
        monthlyWithdrawal: monthlyWithdrawal ?? this.monthlyWithdrawal,
      );

  // toJson 에 'balance': balance, 'monthly_withdrawal': monthlyWithdrawal 추가.
  // fromJson 에 (json['balance'] as num?)?.toInt() ?? 0 패턴으로 추가.
  // ==·hashCode 에 두 필드 반영.
}

const List<Account> kDefaultAccounts = [
  Account(id: 'default_general', name: '일반계좌', type: AccountType.general),
  Account(id: 'default_isa', name: 'ISA', type: AccountType.isa),
  Account(id: 'default_pension_savings', name: '연금저축', type: AccountType.pension),
  Account(id: 'default_irp', name: 'IRP', type: AccountType.pension),
];
```

- [ ] **Step 4:** `flutter test test/models/` → PASS. **주의**: 다른 테스트가 `default_pension` id 나 "기본 3개"를 전제하면 이 태스크에서 함께 갱신(기대값 의미는 유지).
- [ ] **Step 5:** `git commit -am "feat(v3): Account 잔액·인출 흡수 + 기본 계좌 4개(연금저축·IRP 분리)"`

---

### Task 2: 기본 계좌 오버라이드 스토어 + effectiveAccountsProvider

**Files:**
- Modify: `app/lib/providers/app_providers.dart`
- Test: `app/test/services/providers_v3_test.dart`

**Interfaces:**
- Consumes: Task 1 의 Account.copyWith·kDefaultAccounts.
- Produces:
  - `AccountsNotifier.updateDefaults(String id, {int? balance, int? monthlyWithdrawal})` — 기본 계좌의 잔액·인출을 prefs `default_account_overrides` (jsonEncode `{id: {"balance":.., "monthly_withdrawal":..}}`) 에 영속. 유저 계좌는 기존 add/remove 로 balance 포함 통째 저장(기존 'accounts' 키, Account.toJson 이 이미 확장됨).
  - `AccountsNotifier.updateUser(String id, {int? balance, int? monthlyWithdrawal})` — 유저 계좌 잔액·인출 갱신.
  - `defaultOverridesProvider` 는 별도 노출하지 않고, **`effectiveAccountsProvider = Provider<List<Account>>`** — `[...kDefaultAccounts(오버라이드 적용), ...유저 계좌]` 를 반환. 달력·게이지·엔진 호출부가 이것 하나만 소비.
  - `AccountsNotifier` state 는 유저 계좌 리스트 유지(기존 계약 보존) + 내부에 오버라이드 맵 `Map<String, Account>` 를 두고 `effective` getter 제공. effectiveAccountsProvider 는 accountsProvider 를 watch 하고 notifier.effective 를 반환하되, 오버라이드 변경도 state 갱신(오버라이드 맵 변경 시 `state = [...state]` 로 리스너 트리거)으로 전파.

- [ ] **Step 1: 실패 테스트**:

```dart
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
```

- [ ] **Step 2:** FAIL 확인 → **Step 3:** 구현 (기존 AccountsNotifier persist 패턴 답습, 오버라이드 로드는 생성자 `_load()` 에서 'accounts' 와 함께) → **Step 4:** `flutter test` 전체 PASS → **Step 5:** `git commit -am "feat(v3): 기본 계좌 오버라이드 스토어 + effectiveAccountsProvider"`

---

### Task 3: 마이그레이션 schema 3

**Files:**
- Modify: `app/lib/services/migration.dart`
- Test: `app/test/services/migration_test.dart` (케이스 추가)

**Interfaces:**
- Consumes: prefs 키 `retirement_input`(flat 필드)·`holdings`·`default_account_overrides`.
- Produces: `runMigrations` 가 version<3 에서 아래를 수행 후 `schema_version=3` 기록. **v1(버전 없음)→3 직행도 정상 동작** (기존 v2 단계 후 v3 단계 연속 실행).

v3 단계:
1. `retirement_input` 의 flat 필드 → `default_account_overrides`:
   - `pension_savings` → default_pension_savings.balance
   - `irp_balance` → default_irp.balance
   - `isa_balance` → default_isa.balance
   - `monthly_pension_withdrawal` → default_pension_savings.monthlyWithdrawal
   - `monthly_other_withdrawal` → default_isa.monthlyWithdrawal
   - 이미 `default_account_overrides` 가 존재하면 이 단계 스킵(멱등 이중 안전망).
2. `holdings` 의 `account_id == 'default_pension'` → `'default_pension_savings'` 로 재기록.
3. flat 필드는 **그대로 보존**.

- [ ] **Step 1: 실패 테스트** (migration_test.dart 에 추가):

```dart
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
  // 위와 동일 시드 → runMigrations 2회 → 오버라이드에 유저가 이후 수정했다고
  // 가정한 값을 흉내내기 위해, 1회 실행 후 오버라이드를 직접 변경하고 2회째
  // 실행이 덮어쓰지 않는지 확인.
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
```

- [ ] **Step 2:** FAIL → **Step 3:** 구현 (기존 v2 블록 뒤에 `if (version < 3)` 블록, `_kCurrentSchema = 3`) → **Step 4:** 기존 마이그레이션 테스트의 `schema_version == 2` 기대값을 3으로 갱신하며 전체 PASS → **Step 5:** `git commit -am "feat(v3): 마이그레이션 schema 3 — 잔액·인출 계좌 이관 + default_pension 종목 이관"`

---

### Task 4: 엔진 재배선 — 인출 소스를 계좌 합산으로

**Files:**
- Modify: `app/lib/services/cashflow_engine.dart`
- Test: `app/test/services/cashflow_engine_v3_test.dart` (신규) + 기존 엔진 테스트 조정

**Interfaces:**
- Consumes: `Account.monthlyWithdrawal` (Task 1).
- Produces: `buildMonths`/`buildGauges` 가 `input.monthlyPensionWithdrawal`/`monthlyOtherWithdrawal` 를 **더 이상 읽지 않고** `accounts` 파라미터에서 합산:
  - 과세 연금 인출(월) = `accounts.where(type==pension).fold(monthlyWithdrawal 합)` (isWithdrawing 시, 아니면 0)
  - 비과세 인출(월) = `accounts.where(type==isa).fold(...)` (동일 게이트)
  - 절벽·나이세율·게이지 규칙 불변 (연 과세 인출 = 월 합 × 12).

- [ ] **Step 1: 실패 테스트**:

```dart
test('연금 인출 = pension 계좌들 합산 (연금저축+IRP+유저 IRP)', () {
  final accounts = [
    kDefaultAccounts[2].copyWith(monthlyWithdrawal: 800000),  // 연금저축
    kDefaultAccounts[3].copyWith(monthlyWithdrawal: 400000),  // IRP
    const Account(id: 'u1', name: '미래에셋 IRP', type: AccountType.pension,
        monthlyWithdrawal: 100000),
  ];
  final m = CashflowEngine.buildMonths(
      holdings: const [], events: const [],
      input: _inputWithdrawingAge60, // isWithdrawing: true, 인출 flat 필드 0
      from: DateTime(2026, 1, 1), monthCount: 1, accounts: accounts).first;
  // 월 130만 → 연 1,560만 > 1,500만 절벽 → 전액 16.5%.
  expect(m.pensionGross, 1300000);
  expect(m.pensionNet, (1300000 * (1 - 0.165)).round());
});

test('ISA 인출은 비과세 그대로 + flat 필드는 더 이상 읽지 않음', () {
  final accounts = [kDefaultAccounts[1].copyWith(monthlyWithdrawal: 300000)];
  final input = _inputWithdrawingAge60.copyWith(
      monthlyPensionWithdrawal: 9999999); // 엔진이 읽으면 안 되는 값
  final m = CashflowEngine.buildMonths(
      holdings: const [], events: const [], input: input,
      from: DateTime(2026, 1, 1), monthCount: 1, accounts: accounts).first;
  expect(m.pensionGross, 300000);
  expect(m.pensionNet, 300000);
});

test('buildGauges 절벽 게이지 = 계좌 합산 연 인출', () {
  final accounts = [
    kDefaultAccounts[2].copyWith(monthlyWithdrawal: 700000),
    kDefaultAccounts[3].copyWith(monthlyWithdrawal: 500000),
  ];
  final g = CashflowEngine.buildGauges(
      holdings: const [], events: const [], input: _inputWithdrawingAge60,
      year: 2026, accounts: accounts);
  expect(g.pensionLowRate.current, 1200000 * 12);
});
```

- [ ] **Step 2:** FAIL → **Step 3:** 구현 — pensionGross/pensionNet 산출부와 buildGauges 의 `annualPensionTaxable` 을 계좌 합산으로 교체. `pensionNet` 은 (과세 인출 × (1−세율)) + 비과세 인출 구조 유지.
- [ ] **Step 4:** 기존 엔진·위젯 테스트 중 flat 인출 필드로 연금을 주입하던 것들을 계좌 합산 방식으로 수정 (기대 계산값은 동일해야 함 — 달라지면 버그). 전체 `flutter test` PASS.
- [ ] **Step 5:** `git commit -am "feat(v3): 엔진 인출 소스 계좌 합산 재배선 (계산 규칙 불변)"`

---

### Task 5: 입력 탭 전면 재구성 — 계좌 카드 리스트

**Files:**
- Modify: `app/lib/screens/input_screen.dart`
- Modify: `app/lib/screens/calendar_screen.dart` 의 `_AddHoldingSheet` (계좌 선택 제거, `accountId` 파라미터 주입)
- Test: `app/test/screens/input_v3_widget_test.dart`

**Interfaces:**
- Consumes: `effectiveAccountsProvider`·`AccountsNotifier.updateDefaults/updateUser` (Task 2), `holdingsProvider`.
- Produces: `_AddHoldingSheet({required String accountId})` — 시트는 종목·수량만 받고 소속 계좌는 고정.

구현 요구 (스펙 §4 목업이 기준):
1. **"계좌별 자산" 카드 리스트**: `effectiveAccountsProvider` 의 각 계좌를 카드로. 카드 내용:
   - 그 계좌 소속 종목 리스트(수량 표시·스와이프 삭제 기존 UX 유지) + "+ 종목 추가" → `_AddHoldingSheet(accountId: 계좌 id)`
   - 유형 isa/pension 이면: "잔액"(pension_savings/irp 는 라벨 "잔액", isa 는 "현금성 잔액") `AmountInputField` + (isWithdrawing ON 시) "월 인출" `AmountInputField` — `updateDefaults`/`updateUser` 로 저장.
   - 카드 헤더: 계좌명 + 유형 배지(일반/ISA/연금) + 유저 계좌면 삭제 아이콘(확인 다이얼로그 "소속 종목은 같은 유형 기본 계좌로 이동합니다").
2. **[+ 계좌 추가]** 버튼: 기존 계좌 추가 다이얼로그 재사용 (이름+유형).
3. **공통 설정 카드**: "연금 인출 중" SwitchListTile + 연금나침반 CTA(기존 그대로 이동) + "현재 나이" NumberInputField.
4. **제거**: "계좌 관리" ExpansionTile, "연금 계좌" 잔액 카드, "월 인출 계획" 카드 (인출 입력은 각 계좌 카드로 이동, `과세 대상/비과세` helperText 는 해당 계좌 카드의 월 인출 필드로 이동).
5. **이자소득 카드**: 기존 그대로 유지 (공통 설정 아래).
6. 기존 `input_v2_widget_test.dart` 중 옛 구조(월 인출 계획 카드 등)를 전제한 테스트는 새 구조 기준으로 수정 (검증 의도 유지: 토글 OFF 시 월 인출 필드 미노출 등).

- [ ] **Step 1: 위젯 테스트** (input_v3_widget_test.dart):

```dart
testWidgets('계좌 카드 4개 기본 렌더 + 일반계좌엔 잔액 필드 없음', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: InputScreen())));
  await tester.pumpAndSettle();
  expect(find.text('일반계좌'), findsOneWidget);
  expect(find.text('ISA'), findsWidgets);
  expect(find.text('연금저축'), findsOneWidget);
  expect(find.text('IRP'), findsOneWidget);
  // 일반계좌 카드 안에 잔액 입력 없음 — 잔액 필드 총 3개(ISA·연금저축·IRP).
});

testWidgets('인출 토글 ON 시 ISA·연금 계좌 카드에 월 인출 필드 노출', (tester) async { ... });

testWidgets('계좌 카드에서 종목 추가 → 그 계좌 소속으로 저장', (tester) async {
  // ISA 카드의 "+ 종목 추가" 탭 → 시트에 계좌 선택 SegmentedButton 이 없어야 함
  // → 종목 선택·수량 입력·추가 → holdingsProvider 의 accountId == 'default_isa'.
});
```

- [ ] **Step 2~4:** FAIL → 구현 → 전체 `flutter test` PASS + `dart analyze lib test` clean.
- [ ] **Step 5:** `git commit -am "feat(v3): 입력 탭 계좌 카드 재구성 + 종목 추가 계좌 컨텍스트 주입"`

---

### Task 6: 달력·게이지 배선 전환 + 전체 정합

**Files:**
- Modify: `app/lib/screens/calendar_screen.dart`, `app/lib/screens/gauge_screen.dart`
- Test: 기존 위젯 테스트 조정

**Interfaces:**
- Consumes: `effectiveAccountsProvider` (Task 2), 엔진 신규 계약 (Task 4).

- [ ] **Step 1:** 달력·게이지의 `buildMonths`/`buildGauges`/`isaAnnualSavings` 호출부가 `accountsProvider`(유저만) 대신 **`effectiveAccountsProvider`** 를 전달하도록 교체. 재투자·필터·ISA 카드 로직은 무변경.
- [ ] **Step 2:** 기존 calendar/gauge 위젯 테스트가 flat 인출 필드로 연금 값을 주입하던 부분을 계좌 오버라이드 주입으로 수정 (표시 기대값 불변).
- [ ] **Step 3:** 전체 `flutter test` PASS + `dart analyze lib test` clean.
- [ ] **Step 4:** `git commit -am "feat(v3): 달력·게이지 effectiveAccounts 배선"`

---

### Task 7: 마무리 — 버전·빌드

- [ ] `pubspec.yaml` 버전 `1.3.0+4`
- [ ] `dart analyze lib test` → No issues / `flutter test` 전체 PASS
- [ ] 릴리스 빌드 (aab+apk, RETIRE_* dart-define 은 docs/PUBLISH_CHECKLIST.md 커맨드)
- [ ] `git commit -am "chore(v3): v1.3.0+4 버전·릴리스 준비"`
- [ ] 실기기 E2E: v2 설치 상태에서 v3 APK 덮어 설치 — 잔액·인출·종목 계좌 배치·연금주(구 default_pension) 이관 확인

---

## Self-Review 기록

- 스펙 §2 모델(Task 1·2), §2.4 마이그레이션(Task 3, default_pension 이관은 컨트롤러가 스펙 누락을 발견해 플랜에 추가), §3 엔진(Task 4), §4 화면(Task 5·6), §6 검증(각 태스크+7), §7 버전(Task 7).
- 타입 일관성: `updateDefaults/updateUser`·`effectiveAccountsProvider`·`_AddHoldingSheet(accountId:)` 태스크 간 일치 확인.
- Task 5가 가장 큼 — 단 입력 탭이 한 파일이고 카드 위젯이 상호의존이라 분할 시 중간 상태가 빌드 불가라 한 태스크 유지.
