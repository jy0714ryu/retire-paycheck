// AdMob UMP(사용자 메시지 플랫폼) 광고 동의 게이트 — 경조사부·공시한줄·은퇴월급 공용.
//
// 흐름: 동의 정보 갱신 → (필요한 지역·상태일 때만) 동의창 → canRequestAds 확인
//      → 허용될 때만 광고 SDK 초기화. 동의가 필요 없는 지역(한국 등)은 화면 변화 없이 통과.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// UMP·광고 SDK 호출 경계 — 테스트에서 가짜로 교체한다.
/// 오류는 메시지 문자열(null = 성공)로 돌려준다.
abstract class ConsentPlatform {
  Future<String?> requestConsentInfoUpdate();
  Future<String?> loadAndShowConsentFormIfRequired();
  Future<bool> canRequestAds();
  Future<bool> isPrivacyOptionsRequired();
  Future<String?> showPrivacyOptionsForm();
  Future<void> initializeMobileAds();
}

/// 실제 Google UMP SDK 구현.
class UmpConsentPlatform implements ConsentPlatform {
  const UmpConsentPlatform();

  /// 개발 빌드 실기기 테스트 전용 — 릴리스 빌드에서는 kDebugMode 로 전부 무시된다.
  ///   --dart-define=UMP_TEST_DEVICE_ID=(logcat 의 해시 기기 ID)
  ///   --dart-define=UMP_DEBUG_EEA=true    (유럽 사용자처럼 동작)
  ///   --dart-define=UMP_DEBUG_RESET=true  (첫 설치처럼 동의 상태 초기화)
  static const String _debugDeviceId = String.fromEnvironment('UMP_TEST_DEVICE_ID');
  static const bool _debugEea = bool.fromEnvironment('UMP_DEBUG_EEA');
  static const bool _debugReset = bool.fromEnvironment('UMP_DEBUG_RESET');

  static bool _resetDone = false;

  ConsentRequestParameters _params() {
    if (!kDebugMode || _debugDeviceId.isEmpty) return ConsentRequestParameters();
    return ConsentRequestParameters(
      consentDebugSettings: ConsentDebugSettings(
        debugGeography: _debugEea
            ? DebugGeography.debugGeographyEea
            : DebugGeography.debugGeographyDisabled,
        testIdentifiers: [_debugDeviceId],
      ),
    );
  }

  @override
  Future<String?> requestConsentInfoUpdate() async {
    if (kDebugMode && _debugReset && !_resetDone) {
      _resetDone = true;
      await ConsentInformation.instance.reset();
    }
    final done = Completer<String?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      _params(),
      () => done.complete(null),
      (error) => done.complete(error.message),
    );
    return done.future;
  }

  @override
  Future<String?> loadAndShowConsentFormIfRequired() {
    final done = Completer<String?>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (!done.isCompleted) done.complete(error?.message);
    }).catchError((Object e) {
      if (!done.isCompleted) done.complete('$e');
    });
    return done.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> isPrivacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<String?> showPrivacyOptionsForm() {
    final done = Completer<String?>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (!done.isCompleted) done.complete(error?.message);
    }).catchError((Object e) {
      if (!done.isCompleted) done.complete('$e');
    });
    return done.future;
  }

  @override
  Future<void> initializeMobileAds() async {
    await MobileAds.instance.initialize();
  }
}

/// 앱 전역 광고 동의 상태.
///
/// - [canRequestAds]: true 가 된 뒤에만 광고를 초기화·요청한다 (배너·전면·보상형 공통).
/// - [privacyOptionsRequired]: true 인 사용자에게만 설정의 '광고 개인정보 선택' 메뉴를 보인다.
class AdConsent {
  AdConsent({ConsentPlatform? platform, bool? supported})
      : _platform = platform ?? const UmpConsentPlatform(),
        _supported = supported ?? _platformSupportsAds;

  static AdConsent instance = AdConsent();

  // flutter test(호스트 macOS)·웹에서는 false → 플랫폼 채널을 아예 부르지 않는다.
  static bool get _platformSupportsAds =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final ConsentPlatform _platform;
  final bool _supported;

  final ValueNotifier<bool> canRequestAds = ValueNotifier<bool>(false);
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier<bool>(false);

  Future<void>? _firstRun;
  Future<void>? _inFlight;
  bool _adsStarted = false;
  AppLifecycleListener? _lifecycle;

  /// 앱 시작 시 1회 — 동의 확인 후 허용되면 광고 SDK 를 초기화한다.
  /// 여러 번 불러도 한 번만 실행된다.
  Future<void> gather() {
    if (!_supported) return Future<void>.value();
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(retryIfNeeded()));
    return _firstRun ??= _run();
  }

  /// 아직 광고가 허용되지 않았으면(네트워크 실패·동의창 미완료) 다시 시도한다.
  /// 앱이 다시 화면에 돌아올 때 자동 호출된다.
  Future<void> retryIfNeeded() {
    if (!_supported || canRequestAds.value) return Future<void>.value();
    return _run();
  }

  /// 설정의 '광고 개인정보 선택' — 사용자가 선택을 바꿀 수 있는 화면을 띄운다.
  /// 오류 시 메시지, 성공 시 null.
  Future<String?> showPrivacyOptionsForm() async {
    if (!_supported) return null;
    String? error;
    try {
      error = await _platform.showPrivacyOptionsForm();
    } catch (e) {
      error = '$e';
    }
    await _refreshStatus();
    return error;
  }

  Future<void> _run() {
    final running = _inFlight;
    if (running != null) return running;
    final next = _gatherOnce().whenComplete(() => _inFlight = null);
    _inFlight = next;
    return next;
  }

  Future<void> _gatherOnce() async {
    try {
      final updateError = await _platform.requestConsentInfoUpdate();
      if (updateError != null) {
        // 실패 시 SDK 가 이전 세션의 동의 상태로 canRequestAds 를 판단한다.
        debugPrint('🔒 광고 동의 정보 갱신 실패: $updateError');
      } else {
        final formError = await _platform.loadAndShowConsentFormIfRequired();
        if (formError != null) debugPrint('🔒 광고 동의창 오류: $formError');
      }
    } catch (e) {
      debugPrint('🔒 광고 동의 처리 오류: $e');
    }
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    var can = false;
    var optionsRequired = false;
    try {
      can = await _platform.canRequestAds();
      optionsRequired = await _platform.isPrivacyOptionsRequired();
    } catch (e) {
      debugPrint('🔒 광고 동의 상태 확인 실패: $e');
    }
    privacyOptionsRequired.value = optionsRequired;
    if (can && !_adsStarted) {
      _adsStarted = true;
      try {
        await _platform.initializeMobileAds();
      } catch (e) {
        debugPrint('📢 AdMob 초기화 실패: $e');
      }
    }
    canRequestAds.value = can;
  }
}

/// [AdConsent.privacyOptionsRequired] 인 사용자에게만 [builder](설정의 '광고 개인정보 선택' 메뉴)를 그린다.
/// 한국 등 동의가 필요 없는 지역에서는 아무것도 그리지 않는다.
class AdPrivacyOptionsGate extends StatelessWidget {
  const AdPrivacyOptionsGate({super.key, required this.builder, this.consent});

  final WidgetBuilder builder;
  final AdConsent? consent;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: (consent ?? AdConsent.instance).privacyOptionsRequired,
        builder: (context, required, _) =>
            required ? builder(context) : const SizedBox.shrink(),
      );
}
