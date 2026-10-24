import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/services/ad_consent.dart';

class FakeConsentPlatform implements ConsentPlatform {
  String? updateError;
  String? formError;
  String? privacyFormError;
  bool can = false;
  bool optionsRequired = false;
  bool formGrantsConsent = false;
  bool throwOnStatus = false;

  int updateCalls = 0;
  int formCalls = 0;
  int privacyFormCalls = 0;
  int initCalls = 0;

  @override
  Future<String?> requestConsentInfoUpdate() async {
    updateCalls++;
    return updateError;
  }

  @override
  Future<String?> loadAndShowConsentFormIfRequired() async {
    formCalls++;
    if (formGrantsConsent) can = true;
    return formError;
  }

  @override
  Future<bool> canRequestAds() async {
    if (throwOnStatus) throw StateError('channel');
    return can;
  }

  @override
  Future<bool> isPrivacyOptionsRequired() async => optionsRequired;

  @override
  Future<String?> showPrivacyOptionsForm() async {
    privacyFormCalls++;
    return privacyFormError;
  }

  @override
  Future<void> initializeMobileAds() async {
    initCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeConsentPlatform fake;
  late AdConsent consent;

  setUp(() {
    fake = FakeConsentPlatform();
    consent = AdConsent(platform: fake, supported: true);
  });

  test('동의가 필요 없는 지역(한국): 메뉴 숨김, 광고 SDK 1회 초기화', () async {
    fake.can = true;
    await consent.gather();
    expect(consent.canRequestAds.value, isTrue);
    expect(consent.privacyOptionsRequired.value, isFalse);
    expect(fake.initCalls, 1);
  });

  test('EEA 동의 전: 광고 SDK 초기화·광고 요청 허용 안 함', () async {
    await consent.gather();
    expect(consent.canRequestAds.value, isFalse);
    expect(fake.initCalls, 0);
  });

  test('EEA 동의창 완료 후: 광고 허용 + 개인정보 선택 메뉴 표시', () async {
    fake
      ..formGrantsConsent = true
      ..optionsRequired = true;
    await consent.gather();
    expect(fake.formCalls, 1);
    expect(consent.canRequestAds.value, isTrue);
    expect(consent.privacyOptionsRequired.value, isTrue);
    expect(fake.initCalls, 1);
  });

  test('동의 정보 갱신 실패: 동의창은 건너뛰고 이전 동의 상태로 판단', () async {
    fake
      ..updateError = 'network'
      ..can = true;
    await consent.gather();
    expect(fake.formCalls, 0);
    expect(consent.canRequestAds.value, isTrue);
    expect(fake.initCalls, 1);
  });

  test('광고 허용 알림은 SDK 초기화가 끝난 뒤에 온다', () async {
    fake.can = true;
    var initCallsAtNotify = -1;
    consent.canRequestAds.addListener(() => initCallsAtNotify = fake.initCalls);
    await consent.gather();
    expect(initCallsAtNotify, 1);
  });

  test('gather 를 여러 번 불러도 한 번만 실행', () async {
    fake.can = true;
    await Future.wait([consent.gather(), consent.gather()]);
    await consent.gather();
    expect(fake.updateCalls, 1);
    expect(fake.initCalls, 1);
  });

  test('retryIfNeeded: 허용 전이면 다시 시도, 허용 후에는 생략', () async {
    await consent.gather();
    expect(consent.canRequestAds.value, isFalse);

    fake.can = true;
    await consent.retryIfNeeded();
    expect(fake.updateCalls, 2);
    expect(consent.canRequestAds.value, isTrue);

    await consent.retryIfNeeded();
    expect(fake.updateCalls, 2);
    expect(fake.initCalls, 1);
  });

  test('개인정보 선택 화면: 닫힌 뒤 상태 갱신, 오류 메시지 전달', () async {
    fake.optionsRequired = true;
    await consent.gather();

    fake
      ..can = true
      ..privacyFormError = 'form failed';
    final error = await consent.showPrivacyOptionsForm();
    expect(fake.privacyFormCalls, 1);
    expect(error, 'form failed');
    expect(consent.canRequestAds.value, isTrue);
    expect(fake.initCalls, 1);
  });

  test('상태 확인 중 플랫폼 오류: 앱은 계속, 광고는 허용 안 함', () async {
    fake.throwOnStatus = true;
    await consent.gather();
    expect(consent.canRequestAds.value, isFalse);
    expect(fake.initCalls, 0);
  });

  test('미지원 환경(테스트 호스트·웹): 플랫폼을 전혀 호출하지 않음', () async {
    final off = AdConsent(platform: fake, supported: false);
    await off.gather();
    await off.retryIfNeeded();
    expect(await off.showPrivacyOptionsForm(), isNull);
    expect(fake.updateCalls + fake.privacyFormCalls + fake.initCalls, 0);
    expect(off.canRequestAds.value, isFalse);
  });

  testWidgets('광고 개인정보 선택 메뉴: 필요한 사용자에게만 표시', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdPrivacyOptionsGate(
          consent: consent,
          builder: (_) => const Text('광고 개인정보 선택'),
        ),
      ),
    ));
    expect(find.text('광고 개인정보 선택'), findsNothing);

    consent.privacyOptionsRequired.value = true;
    await tester.pump();
    expect(find.text('광고 개인정보 선택'), findsOneWidget);
  });
}
