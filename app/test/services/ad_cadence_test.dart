import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/services/ad_service.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 9);

  test('첫 2번 넘김은 광고 없음, 3번째에 첫 광고', () {
    for (var c = 1; c <= 2; c++) {
      expect(AdService.shouldShow(callCount: c, now: t0), isFalse);
    }
    expect(AdService.shouldShow(callCount: 3, now: t0), isTrue);
  });

  test('3회째가 와도 직전 광고 후 3분이 안 지났으면 건너뜀', () {
    expect(
      AdService.shouldShow(
        callCount: 6,
        now: t0.add(const Duration(minutes: 2)),
        lastShownAt: t0,
      ),
      isFalse,
    );
    expect(AdService.shouldShow(callCount: 4, now: t0), isFalse);
    expect(
      AdService.shouldShow(
        callCount: 6,
        now: t0.add(const Duration(minutes: 3)),
        lastShownAt: t0,
      ),
      isTrue,
    );
  });
}
