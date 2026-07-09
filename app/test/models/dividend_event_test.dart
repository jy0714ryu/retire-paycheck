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
  test('fromJson — API 실측 스키마', () {
    final e = DividendEvent.fromJson({'corp_name': '폴레드', 'corp_code': '01565364',
        'ex_date': '2026-07-09', 'record_date': '2026-07-10', 'per_share': 200,
        'is_confirmed': true, 'source': 'disclosure', 'disclosed_at': '20260625'});
    expect(e.perShare, 200);
    expect(e.expectedPaymentMonth, DateTime(2026, 8)); // 7월 기준일 → 8월
  });
}
