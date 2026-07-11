import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/dividend_event.dart';

void main() {
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
  test('explicitPaymentMonth 우선 — record/exDate 무시하고 지정월 반환', () {
    final e = DividendEvent(
      corpCode: 'manual_1', corpName: '수동', exDate: null, recordDate: null,
      perShare: 3000, isConfirmed: false,
      explicitPaymentMonth: DateTime(2026, 7), source: 'manual');
    expect(e.expectedPaymentMonth, DateTime(2026, 7));
    expect(e.source, 'manual');
  });
  test('explicitPaymentMonth 이 record/exDate 역산보다 우선', () {
    final e = DividendEvent(
      corpCode: '1', corpName: 'A', exDate: null,
      recordDate: DateTime(2026, 12, 31), // 역산 시 익년 4월
      perShare: 500, isConfirmed: true,
      explicitPaymentMonth: DateTime(2026, 9));
    expect(e.expectedPaymentMonth, DateTime(2026, 9));
  });
  test('fromJson — API 실측 스키마', () {
    final e = DividendEvent.fromJson({'corp_name': '폴레드', 'corp_code': '01565364',
        'ex_date': '2026-07-09', 'record_date': '2026-07-10', 'per_share': 200,
        'is_confirmed': true, 'source': 'disclosure', 'disclosed_at': '20260625'});
    expect(e.perShare, 200);
    expect(e.expectedPaymentMonth, DateTime(2026, 8)); // 7월 기준일 → 8월
  });
}
