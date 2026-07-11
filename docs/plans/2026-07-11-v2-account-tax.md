# 은퇴월급 v2 — 계좌 유형별 세금 정확도 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 종목을 계좌(일반/ISA/연금)에 소속시켜 배당 세금·게이지를 유형별로 정확히 분기하고, 연금 인출 모드·이자소득 리스트·ISA 절세효과 카드를 추가한다.

**Architecture:** 순수 함수 엔진(`CashflowEngine`)에 계좌 유형 분기를 넣고, UI는 Riverpod provider 로 accounts/interest 스토어를 추가해 소비한다. 마이그레이션은 `schema_version` 키로 1회만 실행. 스펙: `docs/2026-07-11-v2-account-tax-design.md` (승인 완료 — 모든 요구의 SSOT).

**Tech Stack:** Flutter/Dart, flutter_riverpod, SharedPreferences, flutter_test (`SharedPreferences.setMockInitialValues`).

## Global Constraints

- 자산 정보는 어떤 경로로도 기기 밖으로 전송하지 않는다 (API 요청에 보유 정보 포함 금지).
- 금액은 전부 `int` 원 단위. 세율 결과는 `.round()`.
- 배당 원천징수 15.4% = `kDividendWithholding`(기존 상수 재사용). ISA·연금계좌 배당 세금 0.
- ISA·연금계좌 배당은 금융소득 게이지 **및** 건보 게이지 양쪽 미산입 — 분기 지점 단일화.
- 기본 계좌 id 는 정확히 `default_general` / `default_isa` / `default_pension`.
- 구 필드(`annual_interest_income`)는 삭제하지 않는다(롤백 안전). 마이그레이션은 `schema_version` < 2 일 때만 실행.
- 기존 테스트 46개 전부 통과 유지. 작업 브랜치 `feat/v2-account-tax` (main 직접 커밋 금지).
- 모든 커밋 메시지 끝: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- 신규 UI 문구는 한국어, 기존 화면 톤(간결·존댓말 캡션) 답습.

## File Structure

| 파일 | 책임 |
|---|---|
| Create `app/lib/models/account.dart` | `AccountType` enum + `Account` 모델 + 기본 계좌 상수 |
| Create `app/lib/models/interest_item.dart` | 이자소득 항목 모델 |
| Create `app/lib/services/migration.dart` | schema_version 기반 v1→v2 마이그레이션 |
| Modify `app/lib/models/holding.dart` | `accountId` 필드 |
| Modify `app/lib/models/retirement_input.dart` | `isWithdrawing` 필드 |
| Modify `app/lib/services/cashflow_engine.dart` | 유형 분기·이자·재투자·ISA 절세효과 |
| Modify `app/lib/providers/app_providers.dart` | accounts/interest provider + 마이그레이션 훅 |
| Modify `app/lib/screens/input_screen.dart` | 계좌 선택·계좌 관리·인출 토글+CTA·이자 리스트 |
| Modify `app/lib/screens/calendar_screen.dart` | 합산 고정 카드·필터 칩·재투자 아코디언 |
| Modify `app/lib/screens/gauge_screen.dart` | 분기 게이지·ISA 절세 카드 |

---

### Task 0: 브랜치 생성

- [ ] **Step 1:**

```bash
cd ~/Workspace/retire-paycheck && git checkout -b feat/v2-account-tax
```

---

### Task 1: Account 모델 + 기본 계좌 상수

**Files:**
- Create: `app/lib/models/account.dart`
- Test: `app/test/models/account_test.dart`

**Interfaces:**
- Produces: `enum AccountType { general, isa, pension }`, `class Account {String id; String name; AccountType type; bool get isDefault;}`, `Account.fromJson/toJson`, `const List<Account> kDefaultAccounts`, `Account? resolveAccount(String id, List<Account> userAccounts)` — 이후 모든 태스크가 사용.

- [ ] **Step 1: 실패 테스트 작성** — `app/test/models/account_test.dart`

```dart
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
```

- [ ] **Step 2: 실패 확인** — `cd app && flutter test test/models/account_test.dart` → FAIL (account.dart 없음)

- [ ] **Step 3: 구현** — `app/lib/models/account.dart`

```dart
/// 계좌 유형 — 배당 세금 처리가 갈리는 3분류 (스펙 §2 분기표).
enum AccountType { general, isa, pension }

/// 계좌 — 유형(세금 엔진용) + 이름(보기용). 기본 계좌 3개는 저장소에 기록하지
/// 않는 코드 상수([kDefaultAccounts])로 항상 존재한다.
class Account {
  final String id;
  final String name;
  final AccountType type;

  const Account({required this.id, required this.name, required this.type});

  bool get isDefault => id.startsWith('default_');

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type.name};

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: AccountType.values.asNameMap()[json['type']] ??
            AccountType.general,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          id == other.id &&
          name == other.name &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

/// 기본 계좌 3개 — 삭제·이름변경 불가, 유형당 1개 암묵 존재.
const List<Account> kDefaultAccounts = [
  Account(id: 'default_general', name: '일반계좌', type: AccountType.general),
  Account(id: 'default_isa', name: 'ISA', type: AccountType.isa),
  Account(id: 'default_pension', name: '연금계좌', type: AccountType.pension),
];

/// id → 계좌 해석. 기본 계좌 우선, 유저 계좌 순회, 없으면 null
/// (호출부가 default_general 폴백 — 삭제된 계좌 참조 안전망).
Account? resolveAccount(String id, List<Account> userAccounts) {
  for (final a in kDefaultAccounts) {
    if (a.id == id) return a;
  }
  for (final a in userAccounts) {
    if (a.id == id) return a;
  }
  return null;
}
```

- [ ] **Step 4: 통과 확인** — `flutter test test/models/account_test.dart` → PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat(v2): Account 모델 + 기본 계좌 상수"`

---

### Task 2: Holding.accountId + RetirementInput.isWithdrawing + InterestItem

**Files:**
- Modify: `app/lib/models/holding.dart`
- Modify: `app/lib/models/retirement_input.dart`
- Create: `app/lib/models/interest_item.dart`
- Test: `app/test/models/v2_fields_test.dart`

**Interfaces:**
- Produces: `Holding.accountId` (String, json 키 `account_id`, 기본 `'default_general'`), `RetirementInput.isWithdrawing` (bool, json 키 `is_withdrawing`; fromJson 에서 키 없으면 인출액>0 판정), `class InterestItem {String id; String name; int annualAmount; List<int> months;}` (json 키 `id`/`name`/`annual_amount`/`months`, 빈 months = 월 균등).

- [ ] **Step 1: 실패 테스트 작성** — `app/test/models/v2_fields_test.dart`

```dart
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
```

- [ ] **Step 2: 실패 확인** — `flutter test test/models/v2_fields_test.dart` → FAIL

- [ ] **Step 3: 구현**

`holding.dart` — 필드·생성자·copyWith·==·hashCode 에 `accountId` 추가, 기본값 `'default_general'`:

```dart
// 생성자 파라미터에 추가:
this.accountId = 'default_general',
// 필드:
/// 소속 계좌 id — [kDefaultAccounts] 또는 유저 계좌. v1 저장분은 키가 없어
/// default_general 로 폴백된다(스펙 §1.2 마이그레이션).
final String accountId;
// toJson 에 추가:
'account_id': accountId,
// fromJson 에 추가:
accountId: json['account_id'] as String? ?? 'default_general',
```

(copyWith·==·hashCode 도 같은 패턴으로 accountId 반영 — 기존 필드와 동일 스타일.)

`retirement_input.dart` — `isWithdrawing` 추가:

```dart
// 필드:
/// 연금 인출 모드 — false(운용기)면 인출 입력을 숨기고 인출 0 취급 (스펙 §1.3).
final bool isWithdrawing;
// 생성자: this.isWithdrawing = true,  (기존 코드 경로 동작 불변)
// toJson: 'is_withdrawing': isWithdrawing,
// fromJson (명시 키 우선, 없으면 v1 판정):
isWithdrawing: json['is_withdrawing'] as bool? ??
    (((json['monthly_pension_withdrawal'] as num?)?.toInt() ?? 0) > 0 ||
        ((json['monthly_other_withdrawal'] as num?)?.toInt() ?? 0) > 0),
```

(copyWith·==·hashCode·`_defaultInput`(providers, isWithdrawing: false) 반영.)

`interest_item.dart` 신규:

```dart
/// 이자소득 항목 — 연 이자 금액(세전)과 지급월. 빈 [months]=월 균등 12분할.
/// 이자율×원금 계산은 지원하지 않는다(스펙 §1.4 — 입력 최소화).
class InterestItem {
  final String id;
  final String name;
  final int annualAmount;
  final List<int> months;

  const InterestItem({
    required this.id,
    required this.name,
    required this.annualAmount,
    this.months = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'annual_amount': annualAmount,
        'months': months,
      };

  factory InterestItem.fromJson(Map<String, dynamic> json) => InterestItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        annualAmount: (json['annual_amount'] as num?)?.toInt() ?? 0,
        months: (json['months'] is List)
            ? (json['months'] as List).map((e) => (e as num).toInt()).toList()
            : const [],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterestItem &&
          id == other.id &&
          name == other.name &&
          annualAmount == other.annualAmount &&
          _listEq(months, other.months);

  @override
  int get hashCode =>
      Object.hash(id, name, annualAmount, Object.hashAll(months));

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
```

- [ ] **Step 4: 통과 확인** — `flutter test test/models/` → PASS (기존 모델 테스트 포함)
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): Holding.accountId·isWithdrawing·InterestItem 모델"`

---

### Task 3: 마이그레이션 서비스 (schema_version)

**Files:**
- Create: `app/lib/services/migration.dart`
- Test: `app/test/services/migration_test.dart`

**Interfaces:**
- Consumes: `InterestItem` (Task 2).
- Produces: `Future<void> runMigrations(SharedPreferences prefs)` — 앱 기동 시 1회 호출(Task 5 에서 배선). prefs 키: `schema_version`(int), `interest_items`(String, jsonEncode 리스트), 기존 `retirement_input`/`holdings`.

- [ ] **Step 1: 실패 테스트 작성** — `app/test/services/migration_test.dart` (스펙 §5 시나리오 1·2·3·5; 4번 왕복은 Task 2 fromJson 폴백 테스트가 커버)

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/services/migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('시나리오1 신규 설치 — 스킵·버전만 기록', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 2);
    expect(prefs.getString('interest_items'), isNull);
  });

  test('시나리오2 v1→v2 — 이자 항목 1개 생성·isWithdrawing 판정', () async {
    SharedPreferences.setMockInitialValues({
      'retirement_input': jsonEncode({
        'annual_interest_income': 1200000,
        'monthly_pension_withdrawal': 1000000,
        'current_age': 60,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    final items = jsonDecode(prefs.getString('interest_items')!) as List;
    expect(items.length, 1);
    expect(items.first['annual_amount'], 1200000);
    expect(items.first['months'], isEmpty); // 월 균등
    final input =
        jsonDecode(prefs.getString('retirement_input')!) as Map<String, dynamic>;
    expect(input['is_withdrawing'], isTrue);
    // 구 필드 보존 (롤백 안전 — Global Constraints).
    expect(input['annual_interest_income'], 1200000);
    expect(prefs.getInt('schema_version'), 2);
  });

  test('시나리오3 멱등성 — 2회 실행해도 이자 항목 1개', () async {
    SharedPreferences.setMockInitialValues({
      'retirement_input': jsonEncode(
          {'annual_interest_income': 1200000, 'current_age': 60}),
    });
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    await runMigrations(prefs);
    final items = jsonDecode(prefs.getString('interest_items')!) as List;
    expect(items.length, 1);
  });

  test('시나리오5 손상 데이터 — 깨진 json 이면 크래시 없이 버전만 기록', () async {
    SharedPreferences.setMockInitialValues({'retirement_input': '{broken'});
    final prefs = await SharedPreferences.getInstance();
    await runMigrations(prefs);
    expect(prefs.getInt('schema_version'), 2);
  });
}
```

- [ ] **Step 2: 실패 확인** — `flutter test test/services/migration_test.dart` → FAIL

- [ ] **Step 3: 구현** — `app/lib/services/migration.dart`

```dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/interest_item.dart';

const int _kCurrentSchema = 2;

/// v1→v2 스키마 마이그레이션 — schema_version 가드로 1회만 실행(스펙 §1.5).
///
/// 구 필드(annual_interest_income)는 지우지 않는다 — 구버전 롤백 시 데이터
/// 유실 방지. Holding.accountId 는 fromJson 폴백이 처리하므로 여기서 손대지
/// 않는다.
Future<void> runMigrations(SharedPreferences prefs) async {
  final version = prefs.getInt('schema_version') ?? 1;
  if (version >= _kCurrentSchema) return;

  try {
    final raw = prefs.getString('retirement_input');
    if (raw != null && raw.isNotEmpty) {
      final input = jsonDecode(raw) as Map<String, dynamic>;

      // 1) 연 이자소득 → InterestItem 1개 (월 균등).
      final interest = (input['annual_interest_income'] as num?)?.toInt() ?? 0;
      if (interest > 0 && prefs.getString('interest_items') == null) {
        final item = InterestItem(
            id: 'migrated_v1', name: '이자소득', annualAmount: interest);
        await prefs.setString('interest_items', jsonEncode([item.toJson()]));
      }

      // 2) isWithdrawing 판정 결과를 명시 키로 고정.
      final withdrawing =
          ((input['monthly_pension_withdrawal'] as num?)?.toInt() ?? 0) > 0 ||
              ((input['monthly_other_withdrawal'] as num?)?.toInt() ?? 0) > 0;
      input['is_withdrawing'] = withdrawing;
      await prefs.setString('retirement_input', jsonEncode(input));
    }
  } catch (_) {
    // 손상 데이터 — 각 스토어의 fromJson 폴백에 맡기고 마이그레이션은 종료.
  }

  await prefs.setInt('schema_version', _kCurrentSchema);
}
```

- [ ] **Step 4: 통과 확인** — `flutter test test/services/migration_test.dart` → PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): schema_version 마이그레이션 (멱등·롤백 안전)"`

---

### Task 4: 엔진 — 유형 분기·이자·재투자·모드·ISA 절세효과

**Files:**
- Modify: `app/lib/services/cashflow_engine.dart`
- Test: `app/test/services/cashflow_engine_v2_test.dart`

**Interfaces:**
- Consumes: `Account`/`AccountType`/`resolveAccount`/`kDefaultAccounts` (Task 1), `Holding.accountId`·`isWithdrawing`·`InterestItem` (Task 2).
- Produces (UI 태스크 6·7·8이 소비):
  - `buildMonths({holdings, events, input, from, monthCount, List<Account> accounts = const [], List<InterestItem> interestItems = const []})`
  - `MonthlyCashflow` 확장: `int interestGross`, `int interestNet`, `int reinvestGross`, `List<DividendLine> reinvestLines`; `totalNet = dividendNet + pensionNet + interestNet` (재투자 미포함)
  - `DividendLine` 확장: `int amountNet`, `String accountId`, `AccountType accountType`
  - `buildGauges({..., List<Account> accounts = const [], List<InterestItem> interestItems = const []})`
  - `static int isaAnnualSavings({required List<Holding> holdings, required List<DividendEvent> events, required List<Account> accounts, required int year})`
  - `yearlyDividendSummary` 는 실수령 대상(일반+ISA)만 집계하도록 `accounts` 파라미터 추가

- [ ] **Step 1: 실패 테스트 작성** — `app/test/services/cashflow_engine_v2_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/interest_item.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

DividendEvent ev(String code, String name, int perShare, DateTime pay) =>
    DividendEvent(
        corpCode: code,
        corpName: name,
        perShare: perShare,
        paymentDate: pay,
        isConfirmed: true,
        source: 'api');

const input0 = RetirementInput(
    pensionSavings: 0,
    irpBalance: 0,
    isaBalance: 0,
    currentAge: 60,
    monthlyPensionWithdrawal: 0,
    monthlyOtherWithdrawal: 0,
    isWithdrawing: false);

void main() {
  final apr = DateTime(2026, 4, 1);
  final events = [ev('c1', '일반주', 10000, apr), ev('c2', 'ISA주', 10000, apr),
      ev('c3', '연금주', 10000, apr)];
  final holdings = [
    const Holding(corpCode: 'c1', corpName: '일반주', shares: 1),
    const Holding(
        corpCode: 'c2', corpName: 'ISA주', shares: 1, accountId: 'default_isa'),
    const Holding(
        corpCode: 'c3', corpName: '연금주', shares: 1,
        accountId: 'default_pension'),
  ];

  test('유형 분기 — 일반 15.4%·ISA 0%·연금은 재투자 분리', () {
    final months = CashflowEngine.buildMonths(
        holdings: holdings, events: events, input: input0, from: apr,
        monthCount: 1);
    final m = months.first;
    // 실수령 배당 = 일반(8460) + ISA(10000). 연금주는 미포함.
    expect(m.dividendGross, 20000);
    expect(m.dividendNet, 8460 + 10000);
    expect(m.reinvestGross, 10000);
    expect(m.reinvestLines.single.corpName, '연금주');
    expect(m.lines.length, 2);
    expect(
        m.lines.firstWhere((l) => l.corpName == '일반주').amountNet, 8460);
    expect(m.lines.firstWhere((l) => l.corpName == 'ISA주').accountType,
        AccountType.isa);
  });

  test('이자소득 — 특정월·월 균등 반영, totalNet 합산', () {
    final months = CashflowEngine.buildMonths(
        holdings: const [], events: const [], input: input0,
        from: DateTime(2026, 1, 1), monthCount: 12,
        interestItems: const [
          InterestItem(id: 'i1', name: '예금', annualAmount: 1200000,
              months: [6]),
          InterestItem(id: 'i2', name: '파킹', annualAmount: 120000),
        ]);
    // 6월 = 예금 전액 + 파킹 1/12. net = gross × (1-0.154).
    final june = months[5];
    expect(june.interestGross, 1200000 + 10000);
    expect(june.interestNet, ((1200000 + 10000) * 0.846).round());
    expect(months[0].interestGross, 10000);
    expect(june.totalNet, june.dividendNet + june.pensionNet + june.interestNet);
  });

  test('연금 모드 OFF — 인출 입력이 있어도 연금 0', () {
    final off = RetirementInput(
        pensionSavings: 0, irpBalance: 0, isaBalance: 0, currentAge: 60,
        monthlyPensionWithdrawal: 1000000, monthlyOtherWithdrawal: 0,
        isWithdrawing: false);
    final m = CashflowEngine.buildMonths(
        holdings: const [], events: const [], input: off, from: apr,
        monthCount: 1).first;
    expect(m.pensionGross, 0);
    expect(m.pensionNet, 0);
  });

  test('게이지 — 일반계좌 배당+이자만 산입 (금융소득·건보 동일 분기)', () {
    // 일반 1,500만 + ISA 900만 + 이자 600만: 산입은 일반+이자 = 2,100만.
    final bigHoldings = [
      const Holding(corpCode: 'c1', corpName: '일반주', shares: 1500),
      const Holding(corpCode: 'c2', corpName: 'ISA주', shares: 900,
          accountId: 'default_isa'),
    ];
    final g = CashflowEngine.buildGauges(
        holdings: bigHoldings, events: events, input: input0, year: 2026,
        interestItems: const [
          InterestItem(id: 'i', name: '예', annualAmount: 6000000)
        ]);
    expect(g.financialIncome.current, 15000000 + 6000000);
    // 1,000만 초과 → 건보도 전액 산입, ISA 는 여기도 미산입.
    expect(g.healthInsurance.current, 21000000);
  });

  test('연금 모드 OFF — 절벽 게이지 0', () {
    final off = RetirementInput(
        pensionSavings: 0, irpBalance: 0, isaBalance: 0, currentAge: 60,
        monthlyPensionWithdrawal: 2000000, monthlyOtherWithdrawal: 0,
        isWithdrawing: false);
    final g = CashflowEngine.buildGauges(
        holdings: const [], events: const [], input: off, year: 2026);
    expect(g.pensionLowRate.current, 0);
  });

  test('ISA 절세효과 = ISA 배당 gross × 15.4%', () {
    final saved = CashflowEngine.isaAnnualSavings(
        holdings: holdings, events: events, accounts: const [], year: 2026);
    expect(saved, (10000 * 0.154).round());
  });
}
```

(주: `DividendEvent` 생성자 시그니처는 기존 `app/lib/models/dividend_event.dart` 를 열어 실제 파라미터명에 맞출 것 — 위 `ev` 헬퍼의 `paymentDate` 부분은 실제 모델의 지급월 결정 필드(`expectedPaymentMonth` 산출 근거)에 맞춰 조정한다. 기존 `cashflow_engine` 테스트 파일의 이벤트 생성 패턴을 재사용하면 된다.)

- [ ] **Step 2: 실패 확인** — `flutter test test/services/cashflow_engine_v2_test.dart` → FAIL (컴파일 에러 포함)

- [ ] **Step 3: 구현** — `cashflow_engine.dart` 수정 핵심

```dart
// import 추가:
import '../models/account.dart';
import '../models/interest_item.dart';

// DividendLine 에 필드 3개 추가 (생성자 기본값: amountNet 필수,
// accountId = 'default_general', accountType = AccountType.general):
final int amountNet;
final String accountId;
final AccountType accountType;

// MonthlyCashflow 에 필드 추가 (생성자 기본값 0·const []):
final int interestGross;
final int interestNet;
final int reinvestGross;          // 연금계좌 배당 — 실수령 아님(과세이연 재투자)
final List<DividendLine> reinvestLines;
// totalNet/totalGross 에 interest 포함 (reinvest 는 미포함 — 스펙 §2):
int get totalNet => dividendNet + pensionNet + interestNet;
int get totalGross => dividendGross + pensionGross + interestGross;

// buildMonths 파라미터 추가:
List<Account> accounts = const [],
List<InterestItem> interestItems = const [],

// 연금 인출 모드 (기존 pensionGross/Net 계산을 감싼다):
final withdrawing = input.isWithdrawing;
final pensionGross = withdrawing
    ? input.monthlyPensionWithdrawal + input.monthlyOtherWithdrawal
    : 0;
// (pensionNet 도 withdrawing ? 기존식 : 0)

// 월 루프 안 배당 집계를 계좌 유형 분기로 교체:
final lines = <DividendLine>[];
final reinvestLines = <DividendLine>[];
var dividendGross = 0;
var dividendNet = 0;
var reinvestGross = 0;
for (final e in events) {
  // (기존 shares·지급월 매칭 로직 유지)
  final holding = holdingByCorp[e.corpCode]!; // _sharesByCorp 대신 holding 맵
  final type = (resolveAccount(holding.accountId, accounts) ??
          kDefaultAccounts.first)
      .type;
  final amount = e.perShare * shares;
  final line = DividendLine(
    corpName: e.corpName,
    amountGross: amount,
    amountNet: type == AccountType.general
        ? (amount * (1 - kDividendWithholding)).round()
        : amount, // ISA·연금 세금 0 (과세이연 — 스펙 §2)
    isConfirmed: e.isConfirmed,
    source: e.source,
    accountId: holding.accountId,
    accountType: type,
  );
  if (type == AccountType.pension) {
    reinvestGross += amount;
    reinvestLines.add(line);
  } else {
    dividendGross += amount;
    dividendNet += line.amountNet;
    lines.add(line);
  }
}

// 이자 (월 루프 안):
var interestGross = 0;
for (final item in interestItems) {
  if (item.months.isEmpty) {
    interestGross += (item.annualAmount / 12).round();
  } else if (item.months.contains(month.month)) {
    interestGross += (item.annualAmount / item.months.length).round();
  }
}
final interestNet = (interestGross * (1 - kDividendWithholding)).round();
```

주의: 기존 `_sharesByCorp` 는 corpCode→shares 합산이라 계좌 정보가 사라진다. **같은 corpCode 가 여러 계좌에 있을 수 있으므로** holdings 를 직접 순회하는 구조로 바꾼다 — 이벤트 매칭을 `for (final h in holdings) { for (final e in events where e.corpCode == h.corpCode) ... }` 로 뒤집으면 계좌별 라인이 자연스럽다 (이벤트→종목 인덱스 `Map<String, List<DividendEvent>>` 를 미리 만들어 O(n+m) 유지).

`buildGauges` 분기:

```dart
// 일반계좌 배당만 산입 (분기 지점 단일화 — 금융소득·건보 공용):
var generalDividendGross = 0;
// (holdings 순회 — 위와 동일한 계좌 해석, type == AccountType.general 만 합산)
final interestAnnual =
    interestItems.fold<int>(0, (s, i) => s + i.annualAmount);
final financialIncomeTotal = generalDividendGross + interestAnnual;
// (input.annualInterestIncome 은 더 이상 사용하지 않는다 — 마이그레이션이
//  interest_items 로 이관. 구 필드는 저장소 보존용일 뿐.)
final annualPensionTaxable =
    input.isWithdrawing ? input.monthlyPensionWithdrawal * 12 : 0;
```

`yearlyDividendSummary` — 동일 계좌 해석 추가, 일반+ISA(실수령)만 집계, `net` 은 라인별 amountNet 합.

`isaAnnualSavings` 신규:

```dart
/// ISA 절세효과 — ISA 계좌 배당 gross × 15.4% (일반계좌였다면 낼 세금).
/// 캡션 "(비과세 한도 내 기준)" 는 UI 책임 (스펙 §2).
static int isaAnnualSavings({
  required List<Holding> holdings,
  required List<DividendEvent> events,
  required List<Account> accounts,
  required int year,
}) { /* 위 순회 패턴으로 ISA 유형 gross 합 × kDividendWithholding round */ }
```

- [ ] **Step 4: 기존 엔진 테스트 컴파일 수정** — 기존 `cashflow_engine` 테스트의 `RetirementInput` 생성부에 `isWithdrawing: true` 추가(동작 불변 확인용), `flutter test` 전체 → PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): 엔진 계좌 유형 분기·이자·재투자·모드·ISA 절세효과"`

---

### Task 5: Provider — accounts/interest 스토어 + 마이그레이션 배선

**Files:**
- Modify: `app/lib/providers/app_providers.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/services/providers_v2_test.dart`

**Interfaces:**
- Consumes: Task 1~3 산출 전부.
- Produces: `accountsProvider` (StateNotifierProvider<AccountsNotifier, List<Account>> — 유저 계좌만, 기본 계좌 미포함), `interestItemsProvider` (StateNotifierProvider<InterestItemsNotifier, List<InterestItem>>), `AccountsNotifier.add/rename/remove(String id)` — remove 시 소속 종목을 같은 유형 기본 계좌로 이동, `InterestItemsNotifier.add/removeAt`. `main.dart` 에서 `runApp` 전 `runMigrations` 호출.

- [ ] **Step 1: 실패 테스트** — `app/test/services/providers_v2_test.dart`

```dart
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
```

- [ ] **Step 2: 실패 확인** → FAIL
- [ ] **Step 3: 구현** — `app_providers.dart` 에 기존 `HoldingsNotifier` 패턴 그대로 `AccountsNotifier`(키 `accounts`)·`InterestItemsNotifier`(키 `interest_items`) 추가. `AccountsNotifier.remove` 는 `ref` 로 `holdingsProvider.notifier` 에 접근해 소속 종목 accountId 를 `default_<type>` 으로 일괄 갱신하는 `reassignAccount(String from, String to)` 메서드(HoldingsNotifier 에 신설) 호출. `holdingsProvider` 생성부를 `(ref) => HoldingsNotifier()` 유지, `accountsProvider = StateNotifierProvider((ref) => AccountsNotifier(ref))`. `main.dart` 의 `main()` 에서 `WidgetsFlutterBinding.ensureInitialized()` 후 `runMigrations(await SharedPreferences.getInstance())` 를 `runApp` 전에 await.
- [ ] **Step 4: 통과 확인** — `flutter test` 전체 PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): accounts·interest provider + 기동 마이그레이션 배선"`

---

### Task 6: 입력 탭 — 계좌 선택·계좌 관리·인출 토글+CTA·이자 리스트

**Files:**
- Modify: `app/lib/screens/input_screen.dart`
- Modify: 종목 추가 바텀시트(`calendar_screen.dart` 의 `_AddHoldingSheet` — 실제 위치는 grep 으로 확인)
- Test: `app/test/screens/input_v2_widget_test.dart`

**Interfaces:**
- Consumes: `accountsProvider`·`interestItemsProvider`·`isWithdrawing`(Task 2·5).

구현 요구 (기존 화면 스타일·위젯(`input_widgets.dart`) 답습):
1. **종목 추가 시트**: 종목·수량 아래 계좌 선택 — `SegmentedButton`(또는 기존 칩 스타일)으로 [일반/ISA/연금] 3버튼, 기본 일반. 해당 유형에 유저 계좌가 있으면 버튼 아래 드롭다운으로 계좌 선택(기본 = 기본 계좌).
2. **계좌 관리**: 입력 탭에 `ExpansionTile` "계좌 관리" — 기본 계좌 3개 + 유저 계좌 목록, [+ 계좌 추가](이름 TextField + 유형 SegmentedButton 다이얼로그), 유저 계좌만 삭제 아이콘(확인 다이얼로그: "소속 종목은 기본 계좌로 이동합니다").
3. **연금 인출 토글**: 연금 섹션 상단 `SwitchListTile` "연금 인출 중" = `input.isWithdrawing`. OFF 면 인출 입력 2필드 숨김(`Visibility`). 토글 아래 한 줄 텍스트 링크: `"어떤 순서로 빼야 세금을 아낄까? → 연금나침반"` — `url_launcher` 로 `https://play.google.com/store/apps/details?id=com.quantlog.pensioncompass` 열기 (pubspec 에 `url_launcher: ^6.3.0` 추가; 이미 있으면 생략).
4. **이자소득**: 기존 단일 필드 제거 → InterestItem 리스트 (이름·연 금액·지급 방식 [월 균등|특정월 선택]) + [+ 항목 추가]. 특정월 선택은 1~12 `FilterChip` 12개.

- [ ] **Step 1: 위젯 테스트 작성** (토글 OFF 시 인출 필드 숨김 + 이자 항목 추가 흐름):

```dart
testWidgets('인출 토글 OFF 시 인출 입력 숨김', (tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: InputScreen())));
  await tester.pumpAndSettle();
  expect(find.text('연금 인출 중'), findsOneWidget);
  // 기본 OFF(신규 유저) → 인출 필드 없음
  expect(find.text('월 연금 인출액'), findsNothing);
  await tester.tap(find.byType(Switch).first);
  await tester.pumpAndSettle();
  expect(find.text('월 연금 인출액'), findsOneWidget);
});
```

(라벨 문자열은 실제 input_screen.dart 의 기존 라벨을 확인해 맞출 것.)

- [ ] **Step 2~4:** 실패 확인 → 구현 → `flutter test` 전체 PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): 입력 탭 계좌·인출 토글·이자 리스트 UI"`

---

### Task 7: 달력 탭 — 최종 합산 고정·필터 칩·재투자 아코디언

**Files:**
- Modify: `app/lib/screens/calendar_screen.dart`
- Test: `app/test/screens/calendar_v2_widget_test.dart`

**Interfaces:**
- Consumes: `MonthlyCashflow.interestNet/reinvestGross/reinvestLines`, `DividendLine.accountId/accountType` (Task 4), `accountsProvider` (Task 5).

구현 요구:
1. **상단 요약 카드 = 항상 전체 합산 고정** — `buildMonths` 를 전체 holdings 로 1회 호출한 결과로 렌더. 서브라인에 이자 추가: `'세전 X만원 · 배당 a만 + 연금 b만 + 이자 c만'` (이자 0이면 기존 형식 유지).
2. **필터 칩**: 요약 카드 아래 가로 스크롤 `ChoiceChip` 행 `[전체 | 일반 | ISA | 연금 | <유저 계좌명…>]` (유저 계좌는 2개 이상 유형에만 노출해도 되고 전부 노출해도 됨 — 전부 노출로 단순화). 선택 상태는 화면 로컬 `StateProvider<String>`(값: 'all' | 'type:<name>' | 'acct:<id>'). 필터는 **월별 상세 리스트·연간 차트에만** 적용 — `lines`/`reinvestLines` 를 accountType/accountId 로 걸러 월 합계를 라인 amountNet 합으로 재계산.
3. **재투자 아코디언**: 월 상세 하단 `ExpansionTile`(기본 접힘, 제목 보조 톤 `AppColors` 의 muted 계열) — `"계좌 내 재투자 +X원"`, 펼치면 reinvestLines + 캡션 `"연금계좌 배당은 인출 전까지 계좌 안에서 재투자됩니다 (과세이연)"`. reinvestGross 0 이면 타일 자체 미노출.
4. 연간 12개월 미니 차트(v1.1 `_YearlyBarChart`)는 실수령(dividendNet+pensionNet+interestNet) 기준 유지.

- [ ] **Step 1: 위젯 테스트** — 필터 칩 탭 시 상세 리스트가 갈리는지 + 요약 카드는 불변인지:

```dart
testWidgets('필터를 ISA 로 바꿔도 상단 합산 카드는 불변', (tester) async {
  // setMockInitialValues 로 일반+ISA 종목·캐시 시드 후:
  // 1) 카드의 실수령 텍스트 캡처 → 2) 'ISA' 칩 탭 → 3) 동일 텍스트 존재 확인
  //    + 상세 리스트에 일반주 라인 사라짐 확인.
});
```

(시드 데이터는 기존 calendar 위젯 테스트의 mock 패턴 재사용 — `dividends_cache_body` 캐시 키에 이벤트 JSON 주입.)

- [ ] **Step 2~4:** 실패 → 구현 → `flutter test` 전체 PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): 달력 필터 칩·합산 고정·재투자 아코디언"`

---

### Task 8: 게이지 탭 — 분기 반영 + ISA 절세효과 카드

**Files:**
- Modify: `app/lib/screens/gauge_screen.dart`
- Test: `app/test/screens/gauge_v2_widget_test.dart`

**Interfaces:**
- Consumes: `buildGauges(accounts:, interestItems:)`·`isaAnnualSavings` (Task 4), providers (Task 5).

구현 요구:
1. `buildGauges` 호출부에 `accounts`·`interestItems` 전달 (기존 `input.annualInterestIncome` 인자 제거).
2. **ISA 절세효과 카드**: `isaAnnualSavings > 0` 일 때만 게이지 목록 위에 노출 — `"ISA 덕분에 연 XX만원 절세 중"` + 캡션 `"(일반계좌 대비 · 비과세 한도 내 기준)"`. 0이면 미노출.
3. 연금 모드 OFF 시 절벽 게이지에 캡션 `"연금 인출 전 (참고용)"` 표시(기존 건보 참고용 배지 패턴 재사용).

- [ ] **Step 1: 위젯 테스트** — ISA 종목 있으면 절세 카드 노출, 없으면 미노출.
- [ ] **Step 2~4:** 실패 → 구현 → `flutter test` 전체 PASS
- [ ] **Step 5: Commit** — `git commit -am "feat(v2): 게이지 분기·ISA 절세효과 카드"`

---

### Task 9: 마무리 — analyze·전체 테스트·버전·릴리스 빌드

- [ ] **Step 1:** `flutter analyze` → No issues
- [ ] **Step 2:** `flutter test` 전체 → PASS (기존 46 + 신규 전부)
- [ ] **Step 3:** `pubspec.yaml` 버전 `1.2.0+3` (v1.1.0+2 다음. 심사 지연으로 v1.1 미배포 시 v2 를 묶어 최종본으로 제출 — 대장님 결정 2026-07-11)
- [ ] **Step 4:** 릴리스 빌드 — `flutter build appbundle --release --dart-define=...` (기존 릴리스 커맨드는 `docs/PUBLISH_CHECKLIST.md` 참조, RETIRE_* 광고 ID dart-define 유지)
- [ ] **Step 5: Commit** — `git commit -am "chore(v2): v1.2.0+3 버전·릴리스 준비"`
- [ ] **Step 6:** 실기기 E2E (마이그레이션 확인: v1.1 APK 설치·데이터 입력 → v2 APK 덮어 설치 → 데이터 보존·이자 항목 변환 확인) — **릴리스 빌드로** (v1 교훈: debug 로는 릴리스 전용 결함을 못 잡는다)

---

## Self-Review 기록

- 스펙 커버리지: §1 모델(Task 1·2), §1.5 마이그레이션(Task 3), §2 엔진(Task 4), §3 화면(Task 6·7·8), §4 마케팅은 코드 외(플랜 제외 — Phase 1 에서 스토어 텍스트로), §5 검증(각 태스크 + Task 9), §6 릴리스 순서(Task 9 버전 결정 반영).
- 타입 일관성: `accountId`(String)·`AccountType`·`InterestItem.months`(List<int>)·엔진 시그니처 태스크 간 일치 확인.
- UI 태스크(6·7·8)는 기존 화면 스타일 답습이 요구라 전체 코드 대신 요구+테스트 골격 제공 — 구현자는 해당 파일을 먼저 읽고 패턴을 따를 것.
