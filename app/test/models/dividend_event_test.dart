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

  // Task ①: 백엔드가 payment_date 를 채우면 그 연-월을 지급월로 확정한다.
  // 월배당 12월 배당락 → payment 익년 1월 시나리오(휴리스틱은 4월로 밀림).
  test('fromJson — payment_date 있으면 그 연-월 우선 (12월 배당락 → 익년 1월)', () {
    final e = DividendEvent.fromJson({
      'corp_name': '월배당ETF',
      'corp_code': 'ETF1',
      'ex_date': '2026-12-30',
      'record_date': '2026-12-31',
      'per_share': 100,
      'is_confirmed': false,
      'payment_date': '2027-01-15',
    });
    // 휴리스틱이면 12월 기준일 → 2027-04 로 밀리지만 payment_date 가 우선.
    expect(e.explicitPaymentMonth, DateTime(2027, 1));
    expect(e.expectedPaymentMonth, DateTime(2027, 1));
  });

  test('fromJson — payment_date null 이면 기존 휴리스틱 폴백 (12월 → 익년 4월)', () {
    final e = DividendEvent.fromJson({
      'corp_name': 'A',
      'corp_code': '1',
      'record_date': '2026-12-31',
      'per_share': 500,
      'is_confirmed': true,
      'payment_date': null,
    });
    expect(e.explicitPaymentMonth, isNull);
    expect(e.expectedPaymentMonth, DateTime(2027, 4)); // 휴리스틱 폴백
  });

  test('fromJson — payment_date 키 자체가 없어도 휴리스틱 폴백 (3월 → 4월)', () {
    final e = DividendEvent.fromJson({
      'corp_name': 'B',
      'corp_code': '2',
      'record_date': '2026-03-31',
      'per_share': 300,
      'is_confirmed': true,
    });
    expect(e.explicitPaymentMonth, isNull);
    expect(e.expectedPaymentMonth, DateTime(2026, 4));
  });

  test('fromJson — payment_date 는 연-월만 취한다 (일자 무시)', () {
    final e = DividendEvent.fromJson({
      'corp_name': 'C',
      'corp_code': '3',
      'record_date': '2026-06-30',
      'per_share': 100,
      'is_confirmed': true,
      'payment_date': '2026-08-25',
    });
    expect(e.explicitPaymentMonth, DateTime(2026, 8));
  });
}
