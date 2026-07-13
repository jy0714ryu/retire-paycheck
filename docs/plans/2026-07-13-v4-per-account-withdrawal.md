# 은퇴월급 v4 — 계좌별 인출 개시 + 현금 재원 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 전역 하나였던 "연금 인출 중" 토글을 계좌별 인출 개시 스위치로 바꾸고, 월 인출 재원=현금성 잔액 개념·잔액 소진 캡션을 더한다.

**Architecture:** `Account.isWithdrawing`(계좌별) 필드를 추가하고, 엔진의 인출 소스를 전역 `input.isWithdrawing` 게이트에서 계좌별 `a.isWithdrawing` 게이트로 전환한다. 1,500만 절벽 판정은 인출 켠 pension 계좌 합산(사람 단위)으로 유지. 입력 탭은 v3 계좌 카드에 인출 스위치·소진 캡션·재원 안내를 얹는다. 스펙: `docs/2026-07-12-v4-per-account-withdrawal-design.md` (SSOT).

**Tech Stack:** Flutter/Dart, flutter_riverpod, SharedPreferences, flutter_test.

## Global Constraints

- 금액 전부 `int` 원 단위, 세율 결과 `.round()`. 세금 규칙 v3 그대로 (절벽 1,500만=`kPensionLowRateLimit`, 전액 `kPensionCliffRate`=0.165, 나이별 세율, ISA 비과세, 재투자 분리, 게이지 동일 집계값).
- **1,500만 절벽은 인출 켠 모든 pension 계좌 monthlyWithdrawal 합산 × 12** (사람 단위 — 계좌별 판정 아님). 이 합산 규칙을 어기면 정확도 defect.
- 인출 개시 토글은 **자유롭게 껐다 켜기 가능** (일방향 잠금 금지) — 대상이 자유수령형.
- 마이그레이션은 `schema_version` < 4 에서 1회(멱등). 구 필드(전역 `is_withdrawing`·flat 필드)는 **삭제·수정 금지**(롤백 안전). `RetirementInput` 모델은 손대지 않는다 — 엔진·UI가 참조를 끊을 뿐.
- 기존 override 저장 형식은 `{id: {balance:int, monthly_withdrawal:int}}` — 여기에 `is_withdrawing:bool` 을 더한다(로드·저장·병합 3곳 모두).
- 작업 브랜치 `feat/v4-per-account-withdrawal` (main 직접 커밋 금지). 커밋 끝: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 신규 문구 한국어·기존 톤. `dart analyze lib test` clean (flutter analyze 금지 — 한글 경로 LSP 크래시).

## File Structure

| 파일 | 책임 |
|---|---|
| Modify `app/lib/models/account.dart` | `isWithdrawing` 필드 |
| Modify `app/lib/providers/app_providers.dart` | override 로드·저장·병합에 is_withdrawing, `updateDefaults/updateUser` 에 isWithdrawing 파라미터 |
| Modify `app/lib/services/migration.dart` | schema 4 — 전역 is_withdrawing → 계좌별 전파 |
| Modify `app/lib/services/cashflow_engine.dart` | 인출 소스를 계좌별 게이트로, 전역 게이트 제거 |
| Modify `app/lib/screens/input_screen.dart` | 계좌 카드 인출 스위치·소진 캡션·재원 안내·라벨 통일, 전역 토글 제거 |
| Modify `app/lib/screens/gauge_screen.dart` | 절벽 게이지 참고용 캡션 기준을 계좌별로 |

---

### Task 0: 브랜치 생성

- [ ] `cd ~/Workspace/retire-paycheck && git checkout -b feat/v4-per-account-withdrawal`

---

### Task 1: Account.isWithdrawing 필드

**Files:**
- Modify: `app/lib/models/account.dart`
- Test: `app/test/models/account_test.dart` (케이스 추가)

**Interfaces:**
- Produces: `Account{..., bool isWithdrawing = false}` (json 키 `is_withdrawing`, 없으면 false), `copyWith({..., bool? isWithdrawing})`, `defaultAccountIdFor` 시그니처 불변.

- [ ] **Step 1: 실패 테스트**:

```dart
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
```

- [ ] **Step 2:** `cd app && flutter test test/models/account_test.dart` → FAIL
- [ ] **Step 3: 구현** — `isWithdrawing` 필드(생성자 기본 false), copyWith 파라미터 추가, toJson 에 `'is_withdrawing': isWithdrawing`, fromJson 에 `isWithdrawing: json['is_withdrawing'] as bool? ?? false`, ==·hashCode 반영.
- [ ] **Step 4:** `flutter test` 전체 PASS
- [ ] **Step 5:** `git commit -am "feat(v4): Account.isWithdrawing 계좌별 인출 상태 필드"`

---

### Task 2: Provider — override 에 is_withdrawing 반영

**Files:**
- Modify: `app/lib/providers/app_providers.dart`
- Test: `app/test/services/providers_v4_test.dart`

**Interfaces:**
- Consumes: Task 1 의 Account.copyWith(isWithdrawing:).
- Produces: `AccountsNotifier.updateDefaults(String id, {int? balance, int? monthlyWithdrawal, bool? isWithdrawing})` · `updateUser(String id, {int? balance, int? monthlyWithdrawal, bool? isWithdrawing})` — effectiveAccountsProvider 에 반영·영속. override 저장 형식에 `is_withdrawing` 추가.

- [ ] **Step 1: 실패 테스트**:

```dart
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
```

- [ ] **Step 2:** FAIL → **Step 3:** 구현:
  - `_mergeOverrideJson`: `isWithdrawing: json['is_withdrawing'] as bool?` 추가.
  - `_persistOverrides`: 각 항목에 `'is_withdrawing': entry.value.isWithdrawing` 추가.
  - `updateDefaults`/`updateUser`: `bool? isWithdrawing` 파라미터를 copyWith 로 전달.
- [ ] **Step 4:** `flutter test` 전체 PASS → **Step 5:** `git commit -am "feat(v4): provider override 에 is_withdrawing 계좌별 인출 반영"`

---

### Task 3: 마이그레이션 schema 4

**Files:**
- Modify: `app/lib/services/migration.dart`
- Test: `app/test/services/migration_test.dart` (케이스 추가)

**Interfaces:**
- Produces: `runMigrations` 가 version<4 에서 전역 인출 상태를 계좌별로 전파 후 `schema_version=4`. `_kCurrentSchema = 4`.

v4 단계 (`if (version < 4)`, v3 블록 뒤):
- `retirement_input.is_withdrawing` 이 true 면 → `default_account_overrides` 의 각 항목 중 **ISA·pension 기본 계좌**(default_isa/default_pension_savings/default_irp)에 `is_withdrawing = true` 기록. false 면 아무것도 안 함(기본 false).
- `accounts`(유저 계좌)도 동일: 전역 true 이고 계좌 type 이 isa/pension 이면 `is_withdrawing=true` 로 재기록.
- **멱등**: schema_version 가드. 이미 override 에 is_withdrawing 이 있으면 유저 수정으로 보고 덮어쓰지 않음(v3 패턴 답습).

- [ ] **Step 1: 실패 테스트**:

```dart
test('v3→v4 — 전역 인출 ON 이 ISA·연금 기본 계좌로 전파', () async {
  SharedPreferences.setMockInitialValues({
    'schema_version': 3,
    'retirement_input': jsonEncode({'is_withdrawing': true, 'current_age': 60}),
    'default_account_overrides': jsonEncode({
      'default_pension_savings': {'balance': 10000000, 'monthly_withdrawal': 1200000},
      'default_isa': {'balance': 5000000, 'monthly_withdrawal': 300000},
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  await runMigrations(prefs);
  final ov = jsonDecode(prefs.getString('default_account_overrides')!) as Map<String, dynamic>;
  expect(ov['default_pension_savings']['is_withdrawing'], isTrue);
  expect(ov['default_isa']['is_withdrawing'], isTrue);
  expect(prefs.getInt('schema_version'), 4);
  // 구 전역 필드 보존.
  expect((jsonDecode(prefs.getString('retirement_input')!) as Map)['is_withdrawing'], isTrue);
});

test('v3→v4 — 전역 인출 OFF 면 전파 없음', () async {
  SharedPreferences.setMockInitialValues({
    'schema_version': 3,
    'retirement_input': jsonEncode({'is_withdrawing': false, 'current_age': 60}),
    'default_account_overrides': jsonEncode({
      'default_pension_savings': {'balance': 10000000, 'monthly_withdrawal': 1200000},
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  await runMigrations(prefs);
  final ov = jsonDecode(prefs.getString('default_account_overrides')!) as Map<String, dynamic>;
  expect(ov['default_pension_savings']['is_withdrawing'], anyOf(isNull, isFalse));
  expect(prefs.getInt('schema_version'), 4);
});
```

- [ ] **Step 2:** FAIL → **Step 3:** 구현 (`_kCurrentSchema=4`, v3 뒤 `if (version < 4)` 블록, try/catch 로 감싸 안전). 유저 계좌 전파는 `accounts` 키를 로드해 type isa/pension 인 것에 is_withdrawing=true 재기록.
- [ ] **Step 4:** 기존 migration 테스트의 `schema_version == 3` 기대값을 4로 갱신하며 전체 PASS → **Step 5:** `git commit -am "feat(v4): 마이그레이션 schema 4 — 전역 인출→계좌별 전파"`

---

### Task 4: 엔진 — 계좌별 인출 게이트

**Files:**
- Modify: `app/lib/services/cashflow_engine.dart`
- Test: `app/test/services/cashflow_engine_v4_test.dart` + 기존 엔진 테스트 조정

**Interfaces:**
- Consumes: `Account.isWithdrawing` (Task 1).
- Produces: `buildMonths`/`buildGauges` 가 `input.isWithdrawing` 를 **더 이상 읽지 않고** 계좌별 게이트:
  - 과세 연금 인출(월) = `accounts.where(type==pension && isWithdrawing).fold(monthlyWithdrawal 합)`
  - 비과세 인출(월) = `accounts.where(type==isa && isWithdrawing).fold(...)`
  - `pensionMonthlyWithdrawal(accounts)` 공용 헬퍼에 `&& a.isWithdrawing` 조건 추가.
  - 절벽 = 위 pension 합 × 12 (인출 켠 계좌만 합산). 나이세율·pensionNet·게이지 규칙 불변.

- [ ] **Step 1: 실패 테스트**:

```dart
const _input60 = RetirementInput(
    pensionSavings: 0, irpBalance: 0, isaBalance: 0, currentAge: 60,
    monthlyPensionWithdrawal: 0, monthlyOtherWithdrawal: 0);

test('계좌별 게이트 — 인출 ON 계좌만 산입', () {
  final accounts = [
    kDefaultAccounts[2].copyWith(monthlyWithdrawal: 800000, isWithdrawing: true),  // 연금저축 ON
    kDefaultAccounts[3].copyWith(monthlyWithdrawal: 400000, isWithdrawing: false), // IRP OFF
  ];
  final m = CashflowEngine.buildMonths(
      holdings: const [], events: const [], input: _input60,
      from: DateTime(2026, 1, 1), monthCount: 1, accounts: accounts).first;
  expect(m.pensionGross, 800000); // IRP OFF 라 제외
});

test('절벽 = 인출 켠 pension 계좌 합산 × 12 (사람 단위)', () {
  final accounts = [
    kDefaultAccounts[2].copyWith(monthlyWithdrawal: 700000, isWithdrawing: true),
    kDefaultAccounts[3].copyWith(monthlyWithdrawal: 600000, isWithdrawing: true),
  ];
  // 합 130만 × 12 = 1,560만 > 1,500만 → 전액 16.5%.
  final m = CashflowEngine.buildMonths(
      holdings: const [], events: const [], input: _input60,
      from: DateTime(2026, 1, 1), monthCount: 1, accounts: accounts).first;
  expect(m.pensionNet, (1300000 * (1 - 0.165)).round());
});

test('ISA 인출도 계좌별 게이트', () {
  final accounts = [
    kDefaultAccounts[1].copyWith(monthlyWithdrawal: 300000, isWithdrawing: false),
  ];
  final m = CashflowEngine.buildMonths(
      holdings: const [], events: const [], input: _input60,
      from: DateTime(2026, 1, 1), monthCount: 1, accounts: accounts).first;
  expect(m.pensionGross, 0); // ISA OFF
});
```

- [ ] **Step 2:** FAIL → **Step 3:** 구현 — `withdrawing = input.isWithdrawing` 게이트 제거, `_monthlyWithdrawalByType`/`pensionMonthlyWithdrawal` 에 `&& a.isWithdrawing` 추가, buildMonths·buildGauges 의 인출 계산이 이 헬퍼를 쓰도록.
- [ ] **Step 4:** 기존 엔진·위젯 테스트가 전역 isWithdrawing 로 인출을 켜던 것을 **계좌 isWithdrawing:true 주입**으로 수정(기대 계산값 불변). 전체 `flutter test` PASS.
- [ ] **Step 5:** `git commit -am "feat(v4): 엔진 계좌별 인출 게이트 (절벽은 켠 계좌 합산 유지)"`

---

### Task 5: 입력 탭 — 계좌 카드 인출 스위치·소진 캡션·재원 안내

**Files:**
- Modify: `app/lib/screens/input_screen.dart`
- Test: `app/test/screens/input_v4_widget_test.dart`

**Interfaces:**
- Consumes: `effectiveAccountsProvider`·`AccountsNotifier.updateDefaults/updateUser(isWithdrawing:)` (Task 2), `Account.isWithdrawing/balance/monthlyWithdrawal`.

구현 요구 (v3 계좌 카드 구조에 얹기 — 기존 위젯·톤 답습):
1. **각 ISA·연금 계좌 카드에 "인출 개시" SwitchListTile** (일반계좌 제외). 값=`account.isWithdrawing`, onChanged→ 기본 계좌면 updateDefaults, 유저 계좌면 updateUser 로 isWithdrawing 갱신. 자유롭게 껐다 켜기 가능(잠금 없음).
2. **잔액 라벨 통일**: ISA·연금·IRP 카드 전부 **"현금성 잔액"** (v3의 "잔액"/"현금성 잔액" 혼용 제거).
3. **인출 ON 시에만** "월 인출" 필드 노출(기존 잔액 필드는 항상). 인출 OFF 면 월 인출 숨김.
4. **잔액 소진 캡션** (인출 ON + 월 인출>0): `현금성 잔액 ÷ (월 인출 × 12)` 로 년·개월 환산 →
   `"이 속도면 약 N년 M개월분"` (12개월 미만이면 "약 M개월분"). 월 인출 필드 아래.
5. **재원 안내** (인출 ON + 그 계좌에 종목 보유): `"월 지급액은 현금성 잔액에서 나갑니다 (ETF·종목은 매달 자동 매도되지 않아요)"` 캡션.
6. **공통 설정 카드의 전역 "연금 인출 중" SwitchListTile 제거** (연금나침반 CTA·현재 나이는 유지).
7. helperText: 연금 월 인출="과세 대상 — 나이별 연금소득세(5.5~3.3%)가 붙습니다", ISA="비과세 취급 — 세금 없이 그대로 수령합니다" (v3 그대로 이동).

위젯 테스트 (input_v4_widget_test.dart):

```dart
testWidgets('연금 계좌 인출 스위치 OFF→ON 시 월 인출 필드 노출', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: InputScreen())));
  await tester.pumpAndSettle();
  // 기본 전부 인출 OFF → "월 인출" 필드 없음
  expect(find.text('월 인출'), findsNothing);
  // 첫 인출 스위치 켜기
  await tester.tap(find.byType(Switch).first);
  await tester.pumpAndSettle();
  expect(find.text('월 인출'), findsWidgets);
});

testWidgets('전역 연금 인출 중 토글이 공통 설정에서 제거됨', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: InputScreen())));
  await tester.pumpAndSettle();
  expect(find.text('연금 인출 중'), findsNothing);
});
```

- [ ] **Step 1~4:** 위 테스트 작성 → FAIL → 구현 → 전체 `flutter test` PASS + `dart analyze lib test` clean.
- [ ] **Step 5:** `git commit -am "feat(v4): 입력 탭 계좌별 인출 스위치·소진 캡션·재원 안내"`

---

### Task 6: 게이지 절벽 캡션 기준 정합

**Files:**
- Modify: `app/lib/screens/gauge_screen.dart`
- Test: 기존 gauge 위젯 테스트 조정

**Interfaces:**
- Consumes: 엔진 신규 계약 (Task 4), `effectiveAccountsProvider`.

- [ ] **Step 1:** gauge_screen 의 `pensionIsReference`(연금 인출 전 참고용 캡션) 판정을 전역 `input.isWithdrawing` 에서 **"인출 켠 pension 계좌가 하나도 없으면 참고용"**(`!accounts.any((a)=>a.type==pension && a.isWithdrawing)`)으로 교체. buildGauges/buildMonths 호출은 이미 effectiveAccountsProvider 전달(v3) — 무변경.
- [ ] **Step 2:** 기존 gauge 위젯 테스트가 전역 토글로 참고용 캡션을 검증하던 부분을 계좌 isWithdrawing 주입으로 수정(표시 기대값 불변). 필요 시 1건 추가.
- [ ] **Step 3:** 전체 `flutter test` PASS + `dart analyze lib test` clean.
- [ ] **Step 4:** `git commit -am "feat(v4): 게이지 절벽 참고용 캡션 계좌별 기준"`

---

### Task 7: 마무리 — 버전·빌드

- [ ] `pubspec.yaml` 버전 `1.4.0+5`
- [ ] `dart analyze lib test` → No issues / `flutter test` 전체 PASS
- [ ] 릴리스 빌드 (aab+apk, RETIRE_* dart-define 은 docs/PUBLISH_CHECKLIST.md)
- [ ] `git commit -am "chore(v4): v1.4.0+5 버전·릴리스 준비"`
- [ ] 실기기 E2E: v3 설치 상태에서 v4 APK 덮어 설치 — 인출 상태 계좌별 전파·달력값 불변 확인

---

## Self-Review 기록

- 스펙 §1(토글 자유·모델 B), §2 모델·마이그레이션(Task 1·2·3), §3 엔진 합산(Task 4), §4 화면(Task 5·6), §5 검증(각 태스크+7), §6 버전(Task 7).
- 타입 일관성: `isWithdrawing`(bool)·`updateDefaults/updateUser(isWithdrawing:)`·override json 키 `is_withdrawing` 태스크 간 일치.
- 절벽 합산(사람 단위)은 Task 4 헬퍼 한 곳(`pensionMonthlyWithdrawal`)에서 계좌별 게이트+합산을 동시에 처리 — 달력 캡션·게이지·엔진이 같은 소스.
