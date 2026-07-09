# 은퇴월급 게시 체크리스트 (2026-07-09)

앱: **은퇴월급** — 배당·연금 현금흐름 달력 & 세금 경보
패키지명: `com.quantlog.retirepaycheck` / 현재 버전 `1.0.0+1`

## ✅ 완료 (코드 준비)

- [x] 3화면 MVP (자산 입력 / 은퇴 월급 달력 / 세금 임계치 게이지) — 세후 통일·지급월 예상 배지·참고용 배지
- [x] CashflowEngine (세후 월별 합산 + 게이지 3종: 금융소득종합과세·건보 산입·연금 저율한도)
- [x] 배당 API 클라이언트 (24h 캐시·오프라인 폴백)
- [x] 앱 표시명 한글화: 런처 "은퇴월급" (Android `android:label`)
- [x] AdMob 배선 (`google_mobile_ads ^9.0.0`)
  - 적응 배너: 달력·게이지 화면 하단 (`bottomNavigationBar: SafeArea(child: BannerAdWidget())`)
  - 전면 광고: 달력 월 네비게이션 2회당 1회 (첫 호출 면제 — `AdService` 카운터)
  - App ID (AndroidManifest): `ca-app-pub-7975666616683761~8296037385`
    (pension-compass와 동일 AdMob **계정** — 앱 등록·광고단위는 대장님 후속)
  - **debug/기본값 = Google 테스트 광고 ID** — 실 광고는 릴리스 빌드에 `--dart-define` 주입 필요 (아래 대장님 액션 2)
- [x] 첫 실행 면책 다이얼로그 (SharedPreferences `disclaimer_accepted` 1회 게이트)
  - 문구: "현금흐름·세금 계산은 현행 세법 기준 추정치이며 투자·세무 자문 아님" /
    "배당 지급월은 예상, 회사별로 다를 수 있음" / "정확한 세금·건보료는 세무사·금융기관 상담"
- [x] `flutter analyze` — 에러 0 (info 1건: input_widgets.dart `withOpacity` deprecated, 기능 무관)
- [x] `flutter test` — **19/19 통과** (첫 실행 면책 다이얼로그 표시·확인·플래그 저장 테스트 포함)
- [x] 릴리스 빌드 검증: `flutter build appbundle --release` 성공 (55.2MB)
  - 서명: 전용 upload keystore (`android/upload-keystore.jks`, alias `upload`)
    - **SHA1: `FB:CB:B3:C2:23:56:56:F6:D3:3C:06:37:1C:16:58:B2:73:F0:54:29`**
    - SHA256: `A8:59:51:16:53:ED:5A:AA:0F:E9:D6:95:DB:98:2E:7B:B8:F0:CE:2C:83:D5:A6:9C:C9:C2:31:CE:06:76:78:45`
  - 산출물: `app/build/app/outputs/bundle/release/app-release.aab`
  - **⚠️ keystore + `key.properties` 비밀번호를 데스크탑 백업 폴더에 즉시 보관** (분실 시 앱 업데이트 영구 불가)

## 🔲 대장님 액션 (순서대로)

### 1. AdMob 콘솔 — 앱 등록 + 광고 단위 2개 발급
- 은퇴월급 앱을 AdMob에 신규 등록 (App ID는 위 AndroidManifest 값 재사용 또는 신규 발급 후 교체).
- 광고 단위 2개 생성 후 ID 확보:
  - **전면(retire_interstitial)**: `ca-app-pub-XXXX/XXXX`
  - **배너(retire_banner)**: `ca-app-pub-XXXX/XXXX`

### 2. 릴리스 빌드 (실 광고 ID 주입)
```bash
cd ~/Workspace/retire-paycheck/app
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
flutter build appbundle --release \
  --dart-define=RETIRE_INTERSTITIAL_AD_UNIT_ID=ca-app-pub-XXXX/XXXX \
  --dart-define=RETIRE_BANNER_AD_UNIT_ID=ca-app-pub-XXXX/XXXX
# 산출물: build/app/outputs/bundle/release/app-release.aab (Play 업로드용)
# 실기기 테스트용 apk도 동일 --dart-define으로 build apk --release
```

### 3. 실기기 E2E 스모크 테스트 (⚠️ 이번 Task에서 미수행 — 실기기 R3CY40EQV2X USB 미연결, 에뮬레이터 없음)
아래 항목은 **대장님이 실기기 연결 후 직접 확인** 필요 (단위·위젯 테스트로는 커버되나 실기기 미검증):
- [ ] 앱 기동·첫 실행 면책 다이얼로그 표시·"확인했습니다" 동의 → 재기동 시 미표시
- [ ] 종목 검색·연금/인출 입력 → 달력 화면 세후 실수령 카드 정상
- [ ] 달력 월 네비게이션 (◀▶) → 게이지 화면 3종 정상, 세금 임계치 초과 경고 표시
- [ ] 달력·게이지 하단 배너 **실광고 송출 확인** (릴리스 빌드 + 실 광고 ID)
- [ ] 달력 월 네비게이션 2회 시 전면 광고 노출 (첫 호출 면제 확인)
- [ ] adb 스크린샷 캡처 (입력·달력·게이지 3장 — 스토어 애셋 겸용)

### 4. Play Console 등록
- 스토어 앱 이름: **은퇴월급: 배당·연금 현금흐름 달력 & 세금 경보**
- 짧은 설명·키워드: 배당 지급월 달력 / 연금 인출 세후 / 금융소득종합과세·건보·연금 저율 한도 경보
- 개인정보처리방침 URL: `docs/privacy-policy.html` 작성 후 호스팅 필요
  (GitHub Pages 권장: repo Settings → Pages → main/docs 지정)
- 스크린샷: 달력(세후 실수령 카드) + 게이지(임계치 3종) 최소 2장 (실기기 캡처 — 대장님 액션 3에서 확보)
- 콘텐츠 등급 설문 + 금융 앱 고지: "투자·세무 자문 아님" 면책 명시 (앱 내 disclaimer_dialog 이미 존재)

### 5. 데이터 보안 양식
- 수집·저장 데이터: **온디바이스 전용** (보유 종목·연금 입력값은 SharedPreferences 로컬 저장, 서버 전송 없음)
- **AdMob 광고 ID 수집 신고** (google_mobile_ads가 기기 광고 ID 사용 — Play 데이터 보안 양식에 "기기 또는 기타 ID" 수집 체크)
- app-ads.txt: AdMob 요구 시 별도 절차

### 6. 프로덕션 제출
- aab 업로드 → 프로덕션(또는 내부 테스트) 트랙 제출. 신규 앱 첫 심사는 통상 수일 소요.

## 운영 교훈 (재발 방지)

- **versionCode 재사용 불가**: Play는 동일 versionCode 재업로드를 거부한다. 업데이트마다
  `pubspec.yaml` 의 `version: 1.0.0+1` 의 빌드번호(+N)를 반드시 증가시킬 것.
- **keystore 분실 = 앱 영구 잠김**: `upload-keystore.jks` + `key.properties` 비밀번호를
  생성 즉시 데스크탑 백업 폴더에 비밀번호까지 기록 (pension-compass 키 유실 사고 교훈).
- **키 불일치 반려 주의**: 다른 앱 항목에 잘못 업로드 시 "키 불일치·패키지명" 반려. 항목·패키지명 확인 후 업로드.
- **실 광고 ID 주입 필수**: `--dart-define` 없이 릴리스 빌드하면 테스트 광고가 나가 수익 0 + 정책 위반 소지.
- **AdMob App ID 계정 공유 확인**: 현재 AndroidManifest는 pension-compass와 동일 AdMob 계정 App ID.
  은퇴월급 전용 App ID를 발급받으면 AndroidManifest 값도 함께 교체할 것.

## 알려진 한계 (의도 — UI 고지로 방어)

- 배당 지급월 휴리스틱 오차 (달력 "예상" 배지 + 하단 고지로 방어)
- 건보 산입 게이지 산식 단순화 ("참고용" 배지 + 디스클레이머 상시 노출)
- 예측 배당 정확도 (미확정 배당은 흐린 색 + "예상" 배지)
- iOS 배포 시 `GADApplicationIdentifier`(iOS용 AdMob App ID) Info.plist 추가 필요
