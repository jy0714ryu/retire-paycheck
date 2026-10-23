import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/services/demo_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('앱 빌드(기본)에서는 예시 자산을 쓰지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await seedDemoIfNeeded(prefs);
    expect(kDemoSeedEnabled, isFalse);
    expect(prefs.getKeys(), isEmpty);
  });
}
