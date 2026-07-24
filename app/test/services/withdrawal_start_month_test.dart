import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

// Task ②: 전역 인출 개시월(withdrawalStartMonth). 개시월 이전 달은 모든 인출을
// 0 으로 게이팅하고, 배당은 개시월과 무관하게 항상 표시한다. null 이면 게이팅
// 없음(현재월부터 = 기존 동작).

// 연금저축 월 100만 인출 ON(과세), 나이 60(세율 5.5%).
final _pensionAccounts = [
  kDefaultAccounts[2].copyWith(monthlyWithdrawal: 1000000, isWithdrawing: true),
];

// A사 1,000주 × per_share 500, 2025-12 기준일 → 2026-04 지급 배당.
const _holdingA = Holding(corpCode: 'A', corpName: 'A사', shares: 1000);
final _eventA = DividendEvent(
  corpCode: 'A',
  corpName: 'A사',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);

const _base = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 0,
  monthlyOtherWithdrawal: 0,
);

void main() {
  group('RetirementInput — withdrawalStartMonth 모델', () {
    test('기본값 null (설정 안 함 = 지금부터)', () {
      expect(_base.withdrawalStartMonth, isNull);
    });

    test('copyWith 설정 + 연-월 정규화(일자 절사)', () {
      final r = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3, 17));
      expect(r.withdrawalStartMonth, DateTime(2030, 3));
    });

    test('copyWith clearWithdrawalStartMonth → null 복원', () {
      final set = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3));
      final cleared = set.copyWith(clearWithdrawalStartMonth: true);
      expect(cleared.withdrawalStartMonth, isNull);
    });

    test('toJson/fromJson 왕복 — 값 있음', () {
      final r = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3));
      final back = RetirementInput.fromJson(r.toJson());
      expect(back.withdrawalStartMonth, DateTime(2030, 3));
      expect(back, r);
    });

    test('toJson — null 이면 키 자체가 없다(기존 저장분 호환)', () {
      expect(_base.toJson().containsKey('withdrawal_start_month'), isFalse);
    });

    test('fromJson — 키 없으면 null (v1 저장분)', () {
      final back = RetirementInput.fromJson({'current_age': 60});
      expect(back.withdrawalStartMonth, isNull);
    });

    test('== / hashCode 에 반영', () {
      final a = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3));
      final b = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3));
      final c = _base.copyWith(withdrawalStartMonth: DateTime(2031, 3));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  group('엔진 게이팅 — buildMonths', () {
    test('개시월(2026-06) 이전 달은 인출 0, 이후 달은 정상 인출', () {
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2026, 6));
      final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
        accounts: _pensionAccounts,
      );
      // 5월(개시 전) → 인출 0.
      final may = months.firstWhere((m) => m.month == DateTime(2026, 5));
      expect(may.pensionGross, 0);
      expect(may.pensionNet, 0);
      // 6월(개시월 포함) → 정상 인출.
      final june = months.firstWhere((m) => m.month == DateTime(2026, 6));
      expect(june.pensionGross, 1000000);
      expect(june.pensionNet, (1000000 * (1 - 0.055)).round());
      // 7월(개시 후) → 정상.
      final july = months.firstWhere((m) => m.month == DateTime(2026, 7));
      expect(july.pensionGross, 1000000);
    });

    test('배당은 개시월 이전에도 항상 표시(게이팅 대상 아님)', () {
      // 개시월을 2026-12 로 두어 4월 배당월을 개시 전으로 만든다.
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2026, 12));
      final months = CashflowEngine.buildMonths(
        holdings: [_holdingA],
        events: [_eventA],
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
        accounts: _pensionAccounts,
      );
      final april = months.firstWhere((m) => m.month == DateTime(2026, 4));
      // 인출은 게이팅(0)되지만 배당은 그대로.
      expect(april.pensionGross, 0);
      expect(april.dividendGross, 500000);
      expect(april.dividendNet, (500000 * (1 - 0.154)).round());
    });

    test('개시월이 과거면 전 구간 정상 인출', () {
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2020, 1));
      final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
        accounts: _pensionAccounts,
      );
      expect(months.every((m) => m.pensionGross == 1000000), isTrue);
    });
  });

  group('회귀 — withdrawalStartMonth=null 이면 게이팅 없음', () {
    test('null 이면 전 구간 정상 인출 (기존 동작)', () {
      final months = CashflowEngine.buildMonths(
        holdings: const [],
        events: const [],
        input: _base, // withdrawalStartMonth = null
        from: DateTime(2026, 1),
        monthCount: 12,
        accounts: _pensionAccounts,
      );
      expect(months.every((m) => m.pensionGross == 1000000), isTrue);
    });

    test('buildGauges — null 이면 연 인출 = 월 × 12 (기존)', () {
      final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: _base,
        year: 2026,
        accounts: _pensionAccounts,
      );
      expect(g.pensionLowRate.current, 1000000 * 12);
    });
  });

  group('엔진 게이팅 — buildGauges 연간 인출 개월 수', () {
    test('개시월이 미래 연도면 그 해 인출 0', () {
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2030, 3));
      final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: input,
        year: 2026,
        accounts: _pensionAccounts,
      );
      expect(g.pensionLowRate.current, 0);
    });

    test('개시 연도면 개시월~12월 개월 수만 산입', () {
      // 2026-10 개시 → 10·11·12 = 3개월.
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2026, 10));
      final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: input,
        year: 2026,
        accounts: _pensionAccounts,
      );
      expect(g.pensionLowRate.current, 1000000 * 3);
    });

    test('개시 후 연도면 12개월 전부', () {
      final input = _base.copyWith(withdrawalStartMonth: DateTime(2026, 10));
      final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: input,
        year: 2027,
        accounts: _pensionAccounts,
      );
      expect(g.pensionLowRate.current, 1000000 * 12);
    });
  });
}
