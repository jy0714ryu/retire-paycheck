// Holding 모델 — 수동 입력 필드 하위호환·직렬화 검증.
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/holding.dart';

void main() {
  test('하위호환: 구버전 json(새 필드 없음) → manual 필드 null·isManual=false', () {
    final h = Holding.fromJson({
      'corp_code': '005930',
      'corp_name': '삼성전자',
      'shares': 10,
    });
    expect(h.manualPerShareAnnual, isNull);
    expect(h.manualPaymentMonths, isNull);
    expect(h.isManual, isFalse);
  });

  test('수동 종목 toJson/fromJson 라운드트립 + isManual=true', () {
    final h = Holding(
      corpCode: 'manual_123',
      corpName: '내가쓴ETF',
      shares: 100,
      manualPerShareAnnual: 12000,
      manualPaymentMonths: const [1, 4, 7, 10],
    );
    expect(h.isManual, isTrue);

    final round = Holding.fromJson(h.toJson());
    expect(round.corpCode, 'manual_123');
    expect(round.corpName, '내가쓴ETF');
    expect(round.shares, 100);
    expect(round.manualPerShareAnnual, 12000);
    expect(round.manualPaymentMonths, [1, 4, 7, 10]);
    expect(round.isManual, isTrue);
    expect(round, h);
  });
}
