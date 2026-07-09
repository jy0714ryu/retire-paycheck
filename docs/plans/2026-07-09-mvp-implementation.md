# 은퇴월급 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> 스펙 SSOT: `docs/2026-07-09-은퇴월급-design.md` (347e53d) — 이 플랜과 충돌 시 스펙 우선.

**Goal:** 배당+연금 합산 월별 현금흐름 달력 + 세금 임계치 게이지 3종을 가진 Flutter 앱 MVP (Android, 무료+광고).

**Architecture:** 하이브리드 — 자산 온디바이스(SharedPreferences), 배당은 `api.quant-view.co.kr/dividends` 읽기전용(24h 캐시·오프라인 폴백). 로직 3레이어: 모델/상수 → API·캐시 → CashflowEngine(월별 합산·게이지). UI 3화면은 pension-compass 패턴 복제.

**Tech Stack:** Flutter 3.44, Riverpod, SharedPreferences, http, google_mobile_ads ^9.0.0. pension-compass 구조·테마 복제.

## Global Constraints

- **금액 전부 `int` 원 단위**, 세율 곱 직후 `.round()`.
- 커밋 전 `flutter test` 통과 (app/ 디렉토리에서). TDD 필수 태스크는 RED→GREEN 순서.
- **온디바이스 원칙**: 자산 정보는 어떤 네트워크 요청에도 포함 금지. API 요청은 무파라미터 or 종목코드만.
- **단정 표기 금지**: 예측 배당은 항상 "예상" 배지, 지급월은 "예상 지급월", 건보 게이지는 "참고용" 배지.
- **세후 통일**: 대표 숫자는 실수령(배당 15.4% 원천징수, 연금 나이별 연금소득세). 세전·세후 혼합 금지.
- 배당 지급월 휴리스틱(스펙 §4): 12월 말 기준일(결산배당) → 익년 4월 / 그 외(분기·중간) → 기준일 익월.
- 세금 임계치 상수: 금융소득종합과세 20,000,000 / 건보 피부양자 소득 20,000,000(참고용) / 사적연금 저율한도 15,000,000. 금융소득의 건보 산입: 연 10,000,000 초과 시 전액 산입, 이하 0 (2022.9 개편 기준 — 구현 시 웹 확인 후 주석에 기준일 명시).
- 연금 세후(MVP 단순화): 연금저축·IRP 인출분 × (1 − 나이별 연금소득세율 5.5/4.4/3.3%). 1,500만 초과 여부는 게이지가 경고 (카드 세후는 저율 기준 + 게이지 빨강 시 카드에 ⚠ 표시).
- ⚠️ 운영 교훈(연금나침반 사고 재발 방지): keystore 생성 **즉시** 비밀번호 포함 데스크탑 백업 / AndroidManifest activity는 FQCN / versionCode 재사용 불가 / 앱 라벨 한글 "은퇴월급".

## File Structure

| 경로 (repo: ~/Workspace/retire-paycheck) | 작업 | 책임 |
|---|---|---|
| `app/` | Create (flutter create) | Flutter 프로젝트, applicationId `com.quantlog.retirepaycheck` |
| `app/lib/models/holding.dart` | Create | 보유 종목(corp_code·이름·수량) |
| `app/lib/models/retirement_input.dart` | Create | 연금 잔액·나이·월 인출 2필드·이자소득 |
| `app/lib/models/dividend_event.dart` | Create | API 응답 모델 + 예상 지급월 계산 |
| `app/lib/services/tax_constants.dart` | Create | 임계치 상수·나이별 세율 (기준일 주석) |
| `app/lib/services/dividend_api.dart` | Create | API 클라이언트 + 24h 캐시 + 오프라인 폴백 |
| `app/lib/services/cashflow_engine.dart` | Create | 월별 합산(세전·세후)·연간 게이지 3종 |
| `app/lib/providers/app_providers.dart` | Create | Riverpod 배선 |
| `app/lib/screens/input_screen.dart` | Create | 화면1 자산 입력 |
| `app/lib/screens/calendar_screen.dart` | Create | 화면2 달력(메인) |
| `app/lib/screens/gauge_screen.dart` | Create | 화면3 게이지 |
| `app/lib/theme/`, `app/lib/services/ad_service.dart`, `banner_ad_widget.dart`, `disclaimer_dialog.dart` | Copy | pension-compass에서 복제(출처 주석) |
| `app/test/services/*_test.dart` | Create | 엔진·API·모델 TDD |

---

### Task 1: 프로젝트 스캐폴딩 + pension-compass 자산 이식

**Files:** Create `app/` 전체, Copy 위 표의 복제 대상.

**Interfaces:** Produces — 빌드 가능한 빈 앱(3탭 셸), 이후 태스크의 토대.

- [ ] Step 1: `cd ~/Workspace/retire-paycheck && flutter create --org com.quantlog --project-name retire_paycheck app`
- [ ] Step 2: `app/android/app/build.gradle.kts`를 pension-compass 것 기준으로 정비: applicationId `com.quantlog.retirepaycheck`, targetSdk 35, signingConfig(release)·proguardFiles 블록, `androidx.work:work-runtime:2.10.1` 의존성(광고 크래시 예방), `app/android/app/proguard-rules.pro` 복사(RoomDatabase keep 규칙).
- [ ] Step 3: **keystore 신규 생성 + 즉시 백업** — pension-compass 절차 재사용: `keytool -genkeypair -keystore upload-keystore.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000` (비번 openssl rand 생성) → `key.properties` 작성 → **데스크탑 `은퇴월급_서명키_백업/`에 keystore+비번+README 즉시 복사** → `app/android/.gitignore`에 `key.properties`·`**/*.jks` 확인.
- [ ] Step 4: AndroidManifest — `android:label="은퇴월급"`, activity `android:name` **FQCN**(`com.quantlog.retire_paycheck.MainActivity`), AdMob APPLICATION_ID 메타데이터(연금나침반과 동일 App ID `ca-app-pub-7975666616683761~8296037385` — 동일 AdMob 계정, 앱 등록은 대장님 후속).
- [ ] Step 5: pension-compass에서 복사(각 파일 상단 `// pension-compass에서 이식 (2026-07-09)` 주석): `lib/theme/app_colors.dart`, `app_text_styles.dart`, `lib/services/ad_service.dart`(광고단위 dart-define 키명만 `RETIRE_*`로 변경), `lib/widgets/banner_ad_widget.dart`, `lib/widgets/disclaimer_dialog.dart`(문구를 "세금·현금흐름 추정치" 맥락으로 수정), pubspec 의존성 블록(riverpod·intl·shared_preferences·google_mobile_ads ^9.0.0·in_app_review 제외 가능 + **http ^1.2.0 추가**).
- [ ] Step 6: `lib/main.dart` — ProviderScope + 하단 3탭(입력/달력/게이지) 셸, 각 탭은 빈 Scaffold placeholder. 앱 title '은퇴월급'.
- [ ] Step 7: 검증 `cd app && flutter analyze && flutter test` (기본 widget_test를 '앱 기동+타이틀' 스모크로 교체) + `flutter build apk --debug` 성공 확인.
- [ ] Step 8: Commit `feat: 프로젝트 스캐폴딩 — 3탭 셸, 서명·광고·테마 이식 (pension-compass 패턴)`

---

### Task 2: 모델 + 세금 상수 + 지급월 휴리스틱 (TDD)

**Files:** Create `app/lib/models/{holding,retirement_input,dividend_event}.dart`, `app/lib/services/tax_constants.dart`, Test `app/test/models/dividend_event_test.dart`.

**Interfaces (Produces — 이후 태스크가 의존하는 정확한 시그니처):**
```dart
class Holding { final String corpCode; final String corpName; final int shares; }  // +copyWith, toJson/fromJson
class RetirementInput {
  final int pensionSavings; final int irpBalance; final int isaBalance; final int currentAge;
  final int monthlyPensionWithdrawal; // 연금저축·IRP분 (과세대상 보수 가정)
  final int monthlyOtherWithdrawal;   // ISA·기타분 (비과세 취급)
  final int annualInterestIncome;     // 선택 입력, 기본 0
}  // +copyWith, toJson/fromJson, isValid
class DividendEvent {
  final String corpCode; final String corpName; final DateTime? exDate; final DateTime? recordDate;
  final int perShare; final bool isConfirmed;
  factory DividendEvent.fromJson(Map<String, dynamic> j);
  /// 예상 지급월: 12월 기준일 → 익년 4월 / 그 외 → 기준일 익월. recordDate null이면 exDate 기준.
  DateTime? get expectedPaymentMonth;
}
// tax_constants.dart
const int kFinancialIncomeThreshold = 20000000;
const int kHealthInsuranceIncomeThreshold = 20000000; // 참고용 — 기준일 주석 필수
const int kPensionLowRateLimit = 15000000;
const int kHealthInsFinancialFloor = 10000000; // 금융소득 이 금액 초과 시 전액 산입
const double kDividendWithholding = 0.154;
double pensionTaxRate(int age); // 80+→0.033, 70+→0.044, else 0.055 (연금나침반 이식)
```

- [ ] Step 1: 실패 테스트 — `dividend_event_test.dart`:
```dart
test('12월 말 기준일(결산배당) → 익년 4월', () {
  final e = DividendEvent(corpCode: '1', corpName: 'A', exDate: null,
      recordDate: DateTime(2026, 12, 31), perShare: 500, isConfirmed: true);
  expect(e.expectedPaymentMonth, DateTime(2027, 4));
});
test('3월 말 기준일(분기배당) → 익월(4월)', () {
  final e = DividendEvent(corpCode: '1', corpName: 'A', exDate: null,
      recordDate: DateTime(2026, 3, 31), perShare: 300, isConfirmed: true);
  expect(e.expectedPaymentMonth, DateTime(2026, 4));
});
test('fromJson — API 실측 스키마', () {
  final e = DividendEvent.fromJson({'corp_name': '폴레드', 'corp_code': '01565364',
      'ex_date': '2026-07-09', 'record_date': '2026-07-10', 'per_share': 200,
      'is_confirmed': true, 'source': 'disclosure', 'disclosed_at': '20260625'});
  expect(e.perShare, 200);
  expect(e.expectedPaymentMonth, DateTime(2026, 8)); // 7월 기준일 → 8월
});
```
- [ ] Step 2: FAIL 확인 → Step 3: 구현 (위 시그니처 그대로) → Step 4: PASS + `flutter test` 전체 → Step 5: Commit `feat: 모델·세금상수·지급월 휴리스틱`

---

### Task 3: DividendApi — 클라이언트 + 24h 캐시 + 오프라인 폴백 (TDD)

**Files:** Create `app/lib/services/dividend_api.dart`, Test `app/test/services/dividend_api_test.dart`.

**Interfaces:**
```dart
class DividendApi {
  DividendApi({http.Client? client, SharedPreferences? prefs}); // 주입 가능(테스트용)
  /// GET https://api.quant-view.co.kr/dividends?limit=1000&include_predicted=true
  /// 성공 → prefs에 body+timestamp 캐시. 실패/오프라인 → 캐시 반환(TTL 무시, 스탬프와 함께).
  /// 캐시가 24h 이내면 네트워크 생략.
  Future<DividendFetchResult> fetchAll();
}
class DividendFetchResult { final List<DividendEvent> events; final DateTime fetchedAt; final bool fromCache; }
```
캐시 키: `dividends_cache_body` / `dividends_cache_at`(epoch ms). limit=1000은 스펙 §7-5(연간 커버) 대응 — 응답에서 당해 연도 지급월 커버리지가 부족하면 후속 조정 주석.

- [ ] Step 1: 실패 테스트 — MockClient(http/testing)로 ①정상 응답 → 파싱·캐시 저장 ②네트워크 예외 → 캐시 폴백(fromCache=true) ③캐시 24h 이내 → 네트워크 미호출(호출 카운터 0) 3케이스. SharedPreferences는 `SharedPreferences.setMockInitialValues` 사용.
- [ ] Step 2: FAIL → Step 3: 구현 → Step 4: PASS + 전체 → Step 5: Commit `feat: 배당 API 클라이언트 — 24h 캐시·오프라인 폴백`

---

### Task 4: CashflowEngine — 월별 합산 + 게이지 3종 (TDD, 앱의 심장)

**Files:** Create `app/lib/services/cashflow_engine.dart`, Test `app/test/services/cashflow_engine_test.dart`.

**Interfaces:**
```dart
class MonthlyCashflow {
  final DateTime month;
  final int dividendGross; final int dividendNet;   // net = gross×(1−0.154) round
  final int pensionGross;  final int pensionNet;    // net = 과세분×(1−나이세율)+비과세분
  int get totalNet; int get totalGross;
  final List<DividendLine> lines;                   // 종목별 상세(이름·주당×수량·확정여부)
}
class GaugeStatus { final int current; final int threshold; double get ratio; }  // ratio = current/threshold
class YearlyGauges {
  final GaugeStatus financialIncome;   // 연 배당(gross, 세전) 합계 + annualInterestIncome
  final GaugeStatus healthInsurance;   // 금융소득(1,000만 초과 시 전액, 이하 0) + 연금 과세분 연간
  final GaugeStatus pensionLowRate;    // monthlyPensionWithdrawal×12
}
class CashflowEngine {
  static List<MonthlyCashflow> buildMonths({required List<Holding> holdings,
      required List<DividendEvent> events, required RetirementInput input,
      required DateTime from, int monthCount = 12});
  static YearlyGauges buildGauges({required List<Holding> holdings,
      required List<DividendEvent> events, required RetirementInput input, required int year});
}
```
계산 규칙(테스트 기대값의 근거): 배당 gross=per_share×shares(해당 월에 expectedPaymentMonth 매칭된 이벤트 합), 연금 net=과세분×(1−pensionTaxRate(age))+비과세분. 게이지 financialIncome은 **세전** 배당 연간합+이자.

- [ ] Step 1: 실패 테스트 (수동 계산 기대값 명시):
```dart
// 시나리오: A사 1,000주 per_share 500, 12월 기준일(→익년4월) / 나이 60, 과세인출 월100만, 비과세 월50만, 이자 0
test('4월 현금흐름 = 배당 50만 gross/42.3만 net + 연금 150만 gross/144.5만 net', () {
  // dividendNet = 500000×(1−0.154)=423,000
  // pensionNet = 1,000,000×(1−0.055)+500,000 = 945,000+500,000 = 1,445,000
  // totalNet = 1,868,000
});
test('게이지: 연 배당 50만+이자0 → financial ratio 0.025 / pension 1200만÷1500만=0.8 / 건보: 금융소득 1,000만 이하 → 산입 0, 연금 과세 1,200만 → ratio 0.6', () {...});
test('금융소득 1,000만 초과 시 건보 게이지에 전액 산입', () {...}); // per_share·수량 키워 10,000,001원 케이스
test('예측 배당(is_confirmed=false)도 월별·게이지에 포함되고 lines에 구분 플래그', () {...});
```
- [ ] Step 2: FAIL → Step 3: 구현 → Step 4: PASS + 전체 → Step 5: Commit `feat: CashflowEngine — 세후 통일 월별 합산 + 게이지 3종`

---

### Task 5: 화면1 자산 입력

**Files:** Create `app/lib/screens/input_screen.dart`, `app/lib/providers/app_providers.dart`, `app/lib/widgets/input_widgets.dart`(pension-compass 복사).

**명세** (pension-compass `home_screen.dart` 패턴 — InputSectionCard·AmountInputField·NumberInputField 재사용):
- 카드 1 "보유 종목": 종목 추가 버튼 → 바텀시트에서 검색(소스 = DividendApi 캐시의 corp_name 목록 dedupe, `contains` 필터) + 수량 입력 → 리스트(스와이프 삭제)
- 카드 2 "연금 계좌": 연금저축/IRP/ISA 잔액 + 현재 나이 스텝퍼
- 카드 3 "월 인출 계획": ①연금저축·IRP분 ②ISA·기타분 — 각 필드 helperText로 과세/비과세 취급 설명, 하단에 "공제·비공제 정밀 구분은 연금나침반에서" 안내 텍스트(CTA)
- 카드 4 "(선택) 연 이자소득"
- providers: `holdingsProvider`(StateNotifier, SharedPreferences persist), `retirementInputProvider`(동일), `dividendEventsProvider`(FutureProvider → DividendApi.fetchAll)
- 수용 기준: 입력→앱 재시작→값 유지 / analyze 0 에러 / 위젯테스트 1개(입력 화면 렌더+종목 추가 흐름)
- [ ] 구현 → 검증(`flutter test`) → Commit `feat: 화면1 자산 입력 — 종목 검색·연금·인출 2필드`

### Task 6: 화면2 은퇴 월급 달력 (메인)

**Files:** Create `app/lib/screens/calendar_screen.dart`.

**명세**:
- 상단 월 네비게이션(◀ 2026년 7월 ▶) + 메인 카드: **"이번 달 실수령 ○○○만원"** 크게, 서브 "세전 ○○○만원 · 배당 ○○만 + 연금 ○○○만"
- 본문: 해당 월 배당 라인 리스트 — 종목명 / 주당×수량 / 금액, `isConfirmed=false`면 흐린 색+"예상" 배지. 연금 인출 라인 1개(고정)
- 하단 고지 텍스트: "지급월은 예상이며 회사별로 다를 수 있습니다"
- 게이지 빨강(100%+) 상태면 카드에 ⚠ 아이콘 + "세금 임계치 초과 — 게이지 탭 확인"
- 데이터: `CashflowEngine.buildMonths` 결과를 월 인덱스로 표시. 빈 월은 "이 달 예정 배당 없음"
- 수용 기준: 위젯테스트(mock 데이터로 카드 합계 텍스트 검증 — Task 4 시나리오 값 재사용)
- [ ] 구현 → 검증 → Commit `feat: 화면2 은퇴 월급 달력 — 세후 메인 카드·예상 배지`

### Task 7: 화면3 세금 임계치 게이지

**Files:** Create `app/lib/screens/gauge_screen.dart`.

**명세**:
- 게이지 카드 3개 (LinearProgressIndicator + 수치): 초록(<80%)/노랑(80~100%)/빨강(>100%)
- 각 카드: 제목 / "연간 ○○○만원 ÷ 기준 ○○○만원 (○○%)" / 초과 시 한 줄 설명("1원이라도 넘으면 전액 16.5% 과세로 전환" 등 — 연금나침반 문구 재사용)
- 건보 카드에 **"참고용" 배지** + 디스클레이머 텍스트 "공적연금·기타 소득 합산에 따라 달라질 수 있습니다 (기준: 2026-07 현행)"
- 수용 기준: 위젯테스트(Task 4 게이지 시나리오 → 색상·퍼센트 텍스트 검증)
- [ ] 구현 → 검증 → Commit `feat: 화면3 세금 임계치 게이지 3종 — 참고용 배지·경고 문구`

### Task 8: 마무리 — 광고·면책·검증·게시 준비

**Files:** Modify `main.dart`(AdService.initialize, 면책 다이얼로그 1회), Create `docs/PUBLISH_CHECKLIST.md`.

- [ ] Step 1: 배너(달력·게이지 하단)+전면(달력 새로고침 2회당 1회 — ad_service 카운터) 배선, 테스트ID 기본·`--dart-define=RETIRE_*` 주입 구조
- [ ] Step 2: 첫 실행 면책 다이얼로그("추정치·투자/세무 자문 아님") — pension-compass 복제본 문구 확정
- [ ] Step 3: `flutter analyze`(0 에러) + `flutter test` 전체 + `flutter build appbundle --release` 성공
- [ ] Step 4: 실기기(R3CY40EQV2X) 설치 → 입력→달력→게이지 E2E + adb 스크린샷 (스토어 애셋 겸용)
- [ ] Step 5: `docs/PUBLISH_CHECKLIST.md` 작성 — 연금나침반 체크리스트 템플릿 재사용 (대장님 액션: AdMob 앱+광고단위 2개 발급 / Play 새 앱 항목 / privacy-policy GitHub Pages)
- [ ] Step 6: Commit + 최종 브랜치 리뷰 1회(opus, 대장님 방침)

## Self-Review

- 스펙 §4 3화면 ↔ Task 5/6/7 매핑 ✓, 세후 통일·지급월 휴리스틱·입력 2필드·참고용 배지 전부 Task에 반영 ✓
- 스펙 §7 확인사항: limit=1000(§7-5) Task 3 반영 / 건보 산입 규칙 Task 4 구현+웹 확인 지시 / 종목 사전(§7-3) Task 5에서 캐시 corp 목록으로 해소
- 운영 교훈(keystore 백업·FQCN·work-runtime 2.10.1) Task 1 반영 ✓
- 알려진 한계(의도): 지급월 휴리스틱 오차, 건보 산식 단순화(참고용), 예측 배당 정확도 — 전부 UI 고지로 방어
