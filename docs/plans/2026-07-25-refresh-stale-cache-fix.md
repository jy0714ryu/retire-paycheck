# 2026-07-25 — 배당 당겨서 새로고침 스테일 캐시 버그 수정 (v1.4.4+9)

## 문제 (출시 차단)
서버 배당이 갱신돼도 앱 월급 달력이 옛 데이터(24h 캐시)를 계속 표시. 앱 재실행도 소용없고
(디스크 캐시 < 24h) `pm clear` 로만 새 데이터 수신.

## 조사 결과 (근본 원인)
ProviderContainer / 위젯 테스트로 재현·계측한 결과:

1. **24h TTL 이 지배적 원인.** `DividendApi.fetchAll(force:false)` 는 캐시가 24h 이내면
   네트워크를 아예 생략한다. 성공 fetch 후 만 하루 동안 앱은 서버를 스스로 접촉하지 않으며,
   앱 재시작도 디스크 캐시(< 24h)라 그대로 옛 데이터. → "재실행 소용없음 / pm clear 로만 갱신"
   증상과 정확히 일치. 서버 갱신이 자동으로 앱에 오지 못하는 구조.
2. **당겨서 새로고침이 UI 가 소비하는 provider 를 await 하지 않음.** 화면은
   `combinedEventsProvider(year)` 를 watch 하는데, onRefresh 는 `dividendEventsProvider.future`
   만 await 했다. 카운터→watch→flush 타이밍에 의존하는 간접 설계라, 스피너 종료 시점에
   화면 provider 가 rebuild 됐다는 보장이 없다(테스트에선 우연히 동작하나 취약).
3. **API 가 주입 불가.** `dividendEventsProvider` 내부에서 `DividendApi()` 직접 생성 →
   실제 새로고침 경로를 검증하는 테스트가 아예 없었다(버그 클래스가 무검증 출시).

## 수정
- `DividendApi` TTL 24h → **3h** (자동 스테일 상한 축소, 오프라인 폴백은 유지 — 폴백은 TTL 무시).
- `dividendApiProvider` 신설(주입 지점). `dividendEventsProvider` 가 이를 watch.
- 달력 onRefresh: force 카운터 증가 후 **`combinedEventsProvider(_month.year).future` 를 await** —
  네트워크 재조회 + 화면 provider rebuild 완료까지 스피너 유지 보장.
- 온디바이스 원칙(무파라미터 전체조회)·오프라인 캐시 폴백 유지.

## 검증
- 재현→수정 위젯 테스트(신선 캐시 + 서버 변경 → 새로고침 후 새 데이터 표시, 네트워크 호출 계측).
- TTL 경계 유닛 테스트(4h 캐시 → 네트워크 호출 / 2h 캐시 → 미호출 / force → 캐시 무시).
- ProviderContainer 테스트(force 카운터 → dividendEventsProvider 실제 재실행).
- 전체 `flutter test` + `dart analyze` clean. pubspec 1.4.4+9.
