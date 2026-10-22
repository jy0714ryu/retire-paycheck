import 'package:intl/intl.dart';

/// 원 단위 정수 금액 → 만원 단위 숫자 문자열(소수 한 자리, 반올림) 공통 포맷터.
///
/// 규칙:
/// - 만원 단위로 반올림해 소수 첫째 자리까지 표시한다 (37,000 → "3.7").
/// - 소수부가 0이면 소수점을 생략한다 (30,000 → "3", 1,330,000 → "133").
/// - 정수부는 천단위 콤마를 유지한다.
/// - 0 → "0", 음수는 부호를 유지한다 (-37,000 → "-3.7").
///
/// 반환값은 "만"/"만원" 접미사를 붙이지 않은 순수 숫자 문자열이다 —
/// 호출부가 기존처럼 접미사를 붙인다 (시그니처·호출부 계약 불변).
class CurrencyFormat {
  CurrencyFormat._();

  static final NumberFormat _intFmt = NumberFormat('#,###');

  /// 원 → 만원(소수 한 자리, 반올림) 문자열.
  static String man(int won) {
    final sign = won < 0 ? '-' : '';
    final absWon = won.abs();
    // 천원 단위로 반올림한 뒤 만원 정수부/소수부(첫째 자리)로 분리한다.
    // (absWon / 1000).round() == 만원 단위 소수 첫째 자리 스케일(×10).
    final scaledTenths = (absWon / 1000).round();
    final integerPart = scaledTenths ~/ 10;
    final decimalDigit = scaledTenths % 10;

    final intStr = _intFmt.format(integerPart);
    if (decimalDigit == 0) {
      return '$sign$intStr';
    }
    return '$sign$intStr.$decimalDigit';
  }

  /// 원 → "2억 4,000만" / "3,000만" (만원 미만 반올림, 접미사 포함).
  /// 큰 잔액을 한눈에 읽게 하는 표시용 — 1억 미만은 man() 과 같은 숫자 + "만".
  static String eokMan(int won) {
    final sign = won < 0 ? '-' : '';
    final manTotal = (won.abs() / 10000).round();
    final eok = manTotal ~/ 10000;
    final rest = manTotal % 10000;
    if (eok == 0) return '$sign${man(rest * 10000).replaceFirst('-', '')}만';
    if (rest == 0) return '$sign$eok억';
    return '$sign$eok억 ${_intFmt.format(rest)}만';
  }
}
