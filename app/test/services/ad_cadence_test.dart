import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/services/ad_service.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 9);

  test('첫 4번 넘김은 광고 없음, 5번째에 첫 광고', () {
    for (var c = 1; c <= 4; c++) {
      expect(AdService.shouldShow(callCount: c, now: t0), isFalse);
    }
    expect(AdService.shouldShow(callCount: 5, now: t0), isTrue);
  });

  test('5회째가 와도 직전 광고 후 3분이 안 지났으면 건너뜀', () {
    expect(
      AdService.shouldShow(
        callCount: 10,
        now: t0.add(const Duration(minutes: 2)),
        lastShownAt: t0,
      ),
      isFalse,
    );
    expect(
      AdService.shouldShow(
        callCount: 10,
        now: t0.add(const Duration(minutes: 3)),
        lastShownAt: t0,
      ),
      isTrue,
    );
  });
}
