// 수동 종목 합성 배당 이벤트 + 엔진 통합 검증.
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';
import 'package:retire_paycheck/services/manual_dividends.dart';

void main() {
  group('synthesizeManualEvents', () {
    test('연 12,000원 · 지급월 [4] → 4월 이벤트 1건 per_share 12,000', () {
      final holding = Holding(
        corpCode: 'manual_1',
        corpName: '수동A',
        shares: 10,
        manualPerShareAnnual: 12000,
        manualPaymentMonths: const [4],
      );
      final events = synthesizeManualEvents(holdings: [holding], year: 2026);
      expect(events.length, 1);
      final e = events.first;
      expect(e.perShare, 12000);
      expect(e.expectedPaymentMonth, DateTime(2026, 4));
      expect(e.isConfirmed, isFalse);
      expect(e.source, 'manual');
      expect(e.corpCode, 'manual_1');
    });

    test('연 12,000원 · 지급월 [1,4,7,10] → 4건 각 3,000', () {
      final holding = Holding(
        corpCode: 'manual_2',
        corpName: '수동B',
        shares: 5,
        manualPerShareAnnual: 12000,
        manualPaymentMonths: const [1, 4, 7, 10],
      );
      final events = synthesizeManualEvents(holdings: [holding], year: 2026);
      expect(events.length, 4);
      for (final e in events) {
        expect(e.perShare, 3000);
        expect(e.source, 'manual');
      }
      expect(
        events.map((e) => e.expectedPaymentMonth!.month).toList()..sort(),
        [1, 4, 7, 10],
      );
    });

    test('나누어 떨어지지 않으면 잔여는 첫(가장 이른) 달에', () {
      final holding = Holding(
        corpCode: 'manual_3',
        corpName: '수동C',
        shares: 1,
        manualPerShareAnnual: 10000,
        manualPaymentMonths: const [4, 10, 7], // 정렬 후 [4,7,10]
      );
      final events = synthesizeManualEvents(holdings: [holding], year: 2026);
      expect(events.length, 3);
      final byMonth = {
        for (final e in events) e.expectedPaymentMonth!.month: e.perShare
      };
      // 10000 ÷ 3 = 3333, 잔여 1 → 첫 달(4월) 3334.
      expect(byMonth[4], 3334);
      expect(byMonth[7], 3333);
      expect(byMonth[10], 3333);
    });

    test('API 종목(manual 필드 없음)은 무시', () {
      final api = const Holding(corpCode: '005930', corpName: '삼성전자', shares: 10);
      final events = synthesizeManualEvents(holdings: [api], year: 2026);
      expect(events, isEmpty);
    });

    test('지급월 비었으면 무시', () {
      final holding = Holding(
        corpCode: 'manual_4',
        corpName: '수동D',
        shares: 10,
        manualPerShareAnnual: 12000,
        manualPaymentMonths: const [],
      );
      expect(synthesizeManualEvents(holdings: [holding], year: 2026), isEmpty);
    });
  });

  group('엔진 통합 (수동 종목이 buildMonths·게이지에 반영)', () {
    final manual = Holding(
      corpCode: 'manual_x',
      corpName: '수동X',
      shares: 100,
      manualPerShareAnnual: 12000,
      manualPaymentMonths: const [4],
    );
    const input = RetirementInput(
      pensionSavings: 0,
      irpBalance: 0,
      isaBalance: 0,
      currentAge: 60,
      monthlyPensionWithdrawal: 0,
      monthlyOtherWithdrawal: 0,
      annualInterestIncome: 0,
    );

    test('buildMonths 4월에 수동 배당 gross 120만(12000×100) 반영·라인 source=manual', () {
      final events = synthesizeManualEvents(holdings: [manual], year: 2026);
      final months = CashflowEngine.buildMonths(
        holdings: [manual],
        events: events,
        input: input,
        from: DateTime(2026, 1),
        monthCount: 12,
      );
      final april = months.firstWhere((m) => m.month == DateTime(2026, 4));
      expect(april.dividendGross, 1200000);
      expect(april.lines.single.isConfirmed, isFalse);
      expect(april.lines.single.source, 'manual');
    });

    test('buildGauges 연 배당에 수동분 산입', () {
      final events = synthesizeManualEvents(holdings: [manual], year: 2026);
      final g = CashflowEngine.buildGauges(
        holdings: [manual],
        events: events,
        input: input,
        year: 2026,
      );
      expect(g.financialIncome.current, 1200000);
    });
  });
}
