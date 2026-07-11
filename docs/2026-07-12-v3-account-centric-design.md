# 은퇴월급 v3 설계 — 계좌 중심 정보구조(IA) 재설계

- 작성: 2026-07-12 (대장님 실기기 피드백 — v2 IA 결함 지적)
- 상태: 스펙 확정 대기 (구현 착수 타이밍은 대장님 결정)
- 선행: v2 "계좌 유형별 세금 정확도"(1.2.0+3, main 머지·실기기 검증 완료)

## 0. 문제 (대장님 지적, 2026-07-12)

v2는 계좌를 **종목의 꼬리표**로만 붙였고, 잔액·인출은 v1의 flat 필드를 그대로 뒀다.
그 결과 두 축이 따로 놀며 같은 개념이 세 군데에 중복된다.

| 개념 | ①계좌 관리 섹션 | ②연금 계좌 섹션 | ③월 인출 계획 |
|---|---|---|---|
| ISA | ISA 유형 계좌 | "ISA 잔액" | "ISA·기타 월 인출" |
| 연금 | 연금 유형 계좌 | "연금저축·IRP 잔액" | "연금저축·IRP 월 인출" |

- **계층이 뒤집힘**: 종목을 만든 뒤 계좌를 태그로 붙임 → 실제 증권 계좌는 "계좌가 먼저,
  그 안에 종목"인 계층. 대장님: "보유 종목을 계좌 안에서 선택해야 하는 것 아닌가."
- **중복**: "계좌 관리"와 "연금 계좌"가 개념적으로 겹침. 대장님: "서로 중복되면 안 될 것 같다."

## 1. 해결 원칙 — 계좌를 화면의 뼈대로

**계좌 = 최상위 컨테이너.** 종목·현금성 잔액·월 인출을 전부 그 계좌 카드 안으로 흡수한다.
"계좌 관리" 섹션과 "연금 계좌" 잔액 섹션과 "월 인출 계획" 섹션이 사라지고, 계좌 카드들이
그 자리를 대신한다. 각 계좌는 유형(일반/ISA/연금)에 따라 필요한 입력만 노출한다.

- **3분 입력 철학 유지**: 기본 계좌 4개가 항상 존재 → 계좌를 안 만들어도 바로 종목·잔액 입력.
- **세금 분기는 v2 그대로**: 유형 3종(일반/ISA/연금). 계좌는 표시 단위, 유형은 세금 단위.

## 2. 데이터 모델

### 2.1 `Account` 확장 (잔액·인출 흡수)

```dart
class Account {
  final String id;
  final String name;
  final AccountType type;      // general / isa / pension (세금 분기 — v2 그대로)
  final int balance;           // 현금성 잔액(원). 일반계좌는 미사용(0).
  final int monthlyWithdrawal; // 월 인출액(원). 일반계좌는 미사용(0).
}
```

- 일반계좌(general)는 balance·monthlyWithdrawal 을 UI에 노출하지 않는다(종목만).
- ISA·연금(isa/pension)은 잔액 + (인출 모드 ON 시) 월 인출 노출.

### 2.2 기본 계좌 4개 (연금저축·IRP 분리 — 실제 증권 계좌 구조)

```dart
const List<Account> kDefaultAccounts = [
  Account(id: 'default_general',        name: '일반계좌', type: AccountType.general),
  Account(id: 'default_isa',            name: 'ISA',      type: AccountType.isa),
  Account(id: 'default_pension_savings',name: '연금저축', type: AccountType.pension),
  Account(id: 'default_irp',            name: 'IRP',      type: AccountType.pension),
];
```

- 연금저축·IRP 는 **둘 다 type=pension** — 세금(사적연금 저율·1,500만 절벽·나이별)은 동일,
  잔액만 별개로 입력. 세금 엔진은 두 계좌 인출을 **합산**해 절벽을 판정한다.
- 기본 계좌는 삭제·유형변경 불가. 유저는 "미래에셋 IRP" 등 같은 유형의 계좌를 추가할 수 있고,
  추가 계좌도 balance·monthlyWithdrawal 을 가진다.

### 2.3 `RetirementInput` 축소

- 남는 필드: `currentAge`, `isWithdrawing`(연금 계좌 공통 인출 토글), `annualInterestIncome`(레거시 보존).
- 제거(계좌로 이관): `pensionSavings`, `irpBalance`, `isaBalance`, `monthlyPensionWithdrawal`,
  `monthlyOtherWithdrawal`. **fromJson/toJson 은 레거시 키를 계속 읽고 쓰되**(롤백 안전),
  엔진은 더 이상 참조하지 않는다.

### 2.4 마이그레이션 v2→v3 (`schema_version` 2 → 3)

기존 멱등 마이그레이션 뒤에 v3 단계 추가:

- `pensionSavings > 0` → `default_pension_savings.balance`
- `irpBalance > 0` → `default_irp.balance`
- `isaBalance > 0` → `default_isa.balance`
- `monthlyPensionWithdrawal > 0` → `default_pension_savings.monthlyWithdrawal`
  (전액을 연금저축 계좌에 이관. v2는 연금저축·IRP 인출을 한 필드로 합산했으므로 분리 불가 —
  유저가 화면에서 IRP 쪽으로 조정 가능. 세금은 합산이라 **총액·세금은 불변**.)
- `monthlyOtherWithdrawal > 0` → `default_isa.monthlyWithdrawal`
- 기본 계좌는 코드 상수라 저장소엔 잔액·인출을 가진 계좌만 유저 계좌 저장소와 별도로
  `default_account_overrides` 키(id→{balance, monthlyWithdrawal})에 저장한다
  (기본 계좌의 잔액·인출만 담는 오버라이드 맵 — 기본 계좌 3정체성은 상수 유지).
- **멱등**: schema_version 가드로 1회만. 구 필드(`pension_savings` 등)는 **삭제하지 않는다**.
- **왕복 안전**: v2로 롤백 시 구 필드가 그대로 있어 동작. v3 재로드 시 override 맵이 우선.

## 3. 세금 엔진 (v2 로직 재배선 — 값 불변)

`buildMonths`/`buildGauges` 의 연금·비과세 인출 계산을 계좌 집계로 교체:

```dart
// 과세 연금 인출(월) = pension 유형 계좌들의 monthlyWithdrawal 합 (isWithdrawing 시).
final pensionMonthly = withdrawing
    ? accounts.where((a) => a.type == AccountType.pension)
        .fold(0, (s, a) => s + a.monthlyWithdrawal)
    : 0;
// 비과세 인출(월) = isa 유형 계좌들의 monthlyWithdrawal 합.
final isaMonthly = withdrawing
    ? accounts.where((a) => a.type == AccountType.isa)
        .fold(0, (s, a) => s + a.monthlyWithdrawal)
    : 0;
// 절벽 판정 = pensionMonthly*12 vs 1,500만 (v2와 동일 규칙, 소스만 계좌 합산).
```

- 배당 분기(일반 15.4%/ISA 0/연금 재투자)·ISA 절세효과·게이지 산입 규칙은 **v2 그대로**.
- 잔액(balance)은 현재 세금·현금흐름 계산에 쓰이지 않는다(v2도 미사용) — 표시·미래 확장용.
  단 입력 UX상 계좌 정체성을 위해 유지(대장님 IA 의도).
- 엔진에 `accounts` 파라미터는 v2에서 이미 전달 중 — 시그니처 변경 최소.

## 4. 화면 (입력 탭 전면 재구성)

```
[자산 입력]
──────────────────────────
계좌별 자산

┌ 일반계좌 ────────────────┐   (기본, 삭제 불가)
│ 삼성전자           12주   │
│ + 종목 추가              │
└──────────────────────────┘

┌ ISA ─────────────────────┐   (기본)
│ 배당ETF           100주   │
│ 현금성 잔액   [ 1,000 ]만원│
│ 월 인출       [   120 ]만원│  ← 인출 모드 ON 시만
│ + 종목 추가              │
└──────────────────────────┘

┌ 연금저축 ─────────────────┐   (기본, type=pension)
│ (종목 없음)               │
│ 잔액          [ 1,000 ]만원│
│ 월 인출       [    80 ]만원│
│ + 종목 추가              │
└──────────────────────────┘

┌ IRP ─────────────────────┐   (기본, type=pension)
│ 잔액          [   500 ]만원│
│ 월 인출       [    40 ]만원│
│ + 종목 추가              │
└──────────────────────────┘

[ + 계좌 추가 ]   (이름 + 유형 → 예: "미래에셋 IRP")

─ 공통 설정 ─
연금 인출 중          [ ● ]   ← 연금 계좌 공통 토글
  어떤 순서로 빼야 세금을 아낄까? → 연금나침반
현재 나이            [ 60 세]
(선택) 연 이자소득    [ + 항목 추가 ]
```

- **종목 추가 시트에서 계좌 선택 SegmentedButton 제거** — 각 계좌 카드의 "+ 종목 추가"로
  들어오므로 소속 계좌가 이미 정해진다(시트는 종목·수량만).
- 계좌 카드 헤더: 계좌명 + 유형 배지. 유저 계좌는 우측에 삭제 아이콘(확인 다이얼로그:
  "소속 종목은 같은 유형 기본 계좌로 이동합니다").
- "연금 인출 중" 토글 OFF: 모든 계좌의 월 인출 필드 숨김 + 달력 연금 타일 없음(v2 규칙).
- 달력·게이지 탭: 데이터 소스가 계좌 집계로 바뀌지만 **표시는 v2와 동일**. 필터 칩은 이제
  계좌가 실제 컨테이너라 더 자연스럽다(변경 최소).

## 5. 제외 (YAGNI)

- 계좌별 인출 모드(계좌마다 토글) — 연금 공통 토글 하나로 충분.
- 잔액 기반 고갈 시뮬레이션 — 별도 기능(v4 후보), 이번 범위 아님.
- ISA 일반형/서민형 구분 — v2 유지(비과세 한도 내 기준 캡션).
- 매입가·수익률 — v2에서 이미 제외 확정.

## 6. 검증

- 단위테스트: 엔진 계좌 합산(연금 2계좌 인출 합→절벽), 마이그레이션 v2→v3(잔액·인출 이관·멱등·
  왕복), 계좌 삭제 시 종목·잔액 처리.
- 위젯테스트: 계좌 카드별 종목 추가(소속 자동), 인출 토글 OFF 시 전 계좌 인출 필드 숨김,
  유저 계좌 추가·삭제.
- **릴리스 빌드 실기기 E2E 필수** — v2→v3 덮어 설치 시 잔액·인출·종목 계좌 배치 보존 확인
  (v2 교훈: debug·위젯테스트로 못 잡는 마이그레이션·표시 결함 존재).

## 7. 릴리스 순서

v2(1.2.0+3)가 심사 대기 중. v3는 그 위 다음 버전(1.3.0+4). 심사가 길어지는 상황이라
**v3까지 묶어 최종본으로 제출**할지, v2를 먼저 내보내고 v3를 후속 업데이트로 낼지는
대장님 결정(§ 확인 필요).
