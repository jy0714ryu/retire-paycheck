import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/utils/currency_format.dart';

void main() {
  group('CurrencyFormat.man', () {
    test('37,000원 → "3.7" (소수 한 자리)', () {
      expect(CurrencyFormat.man(37000), '3.7');
    });

    test('30,000원 → "3" (소수부 0이면 생략)', () {
      expect(CurrencyFormat.man(30000), '3');
    });

    test('35,532원 → "3.6" (반올림, 35.532→35.5 절상? 확인) ', () {
      // 35,532/1000 = 35.532 → round() = 36 → 3.6.
      expect(CurrencyFormat.man(35532), '3.6');
    });

    test('42,000원 → "4.2"', () {
      expect(CurrencyFormat.man(42000), '4.2');
    });

    test('1,330,000원 → "133" (큰 금액도 소수부 0이면 생략, 천단위 콤마 없음<1000만)', () {
      expect(CurrencyFormat.man(1330000), '133');
    });

    test('1,215,000원 → "121.5"', () {
      expect(CurrencyFormat.man(1215000), '121.5');
    });

    test('12,340,000원 → "1,234" (정수부 천단위 콤마 유지)', () {
      expect(CurrencyFormat.man(12340000), '1,234');
    });

    test('0원 → "0"', () {
      expect(CurrencyFormat.man(0), '0');
    });

    test('음수 -37,000원 → "-3.7" (부호 유지)', () {
      expect(CurrencyFormat.man(-37000), '-3.7');
    });

    test('음수 -30,000원 → "-3" (소수부 0 생략 + 부호 유지)', () {
      expect(CurrencyFormat.man(-30000), '-3');
    });

    test('반올림 경계: 500원(=0.05만원) → 올림 처리로 다음 자리에 반영', () {
      // 5,000원 -> 0.5만 -> 소수 첫째 자리 표현 "0.5".
      expect(CurrencyFormat.man(5000), '0.5');
    });
  });

  group('CurrencyFormat.eokMan', () {
    test('1억 이상은 억+만', () {
      expect(CurrencyFormat.eokMan(240000000), '2억 4,000만');
      expect(CurrencyFormat.eokMan(110000000), '1억 1,000만');
      expect(CurrencyFormat.eokMan(300000000), '3억');
    });
    test('1억 미만·0·음수', () {
      expect(CurrencyFormat.eokMan(30000000), '3,000만');
      expect(CurrencyFormat.eokMan(0), '0만');
      expect(CurrencyFormat.eokMan(-125000000), '-1억 2,500만');
    });
  });
}
