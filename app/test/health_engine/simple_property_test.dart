import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/health_engine/engine.dart';

import '_helpers.dart';

void main() {
  late SimplePropertyEstimator est;

  setUpAll(() async {
    est = SimplePropertyEstimator(await loadParams2026());
  });

  test('일반주택: 시세 10억 → 공시가 6.9억 → 과표 4.14억', () {
    // 10억 × 0.69 = 6.9억 → × 0.60 = 4.14억
    final r = est.estimate(marketPrice: 1000000000);
    expect(r.officialPrice, 690000000);
    expect(r.appliedRatio, 0.60);
    expect(r.taxBase, 414000000);
    expect(r.singleHome, isFalse);
  });

  test('1주택 특례: 시세 10억 → 공시가 6.9억(>6억) → 비율 0.45 → 과표 3.105억', () {
    final r = est.estimate(marketPrice: 1000000000, singleHome: true);
    expect(r.officialPrice, 690000000);
    expect(r.appliedRatio, 0.45);
    expect(r.taxBase, 310500000);
  });

  group('1주택 특례 공정시장가액비율 구간', () {
    test('공시가 3억 이하 → 0.43', () {
      // 시세 4억 → 공시가 2.76억 (≤3억) → 0.43 → 과표 118,680,000
      final r = est.estimate(marketPrice: 400000000, singleHome: true);
      expect(r.officialPrice, 276000000);
      expect(r.appliedRatio, 0.43);
      expect(r.taxBase, 118680000);
    });

    test('공시가 3~6억 → 0.44', () {
      // 시세 8억 → 공시가 5.52억 (3~6억) → 0.44 → 과표 242,880,000
      final r = est.estimate(marketPrice: 800000000, singleHome: true);
      expect(r.officialPrice, 552000000);
      expect(r.appliedRatio, 0.44);
      expect(r.taxBase, 242880000);
    });

    test('공시가 6억 초과 → 0.45', () {
      final r = est.estimate(marketPrice: 1000000000, singleHome: true);
      expect(r.appliedRatio, 0.45);
    });
  });
}
