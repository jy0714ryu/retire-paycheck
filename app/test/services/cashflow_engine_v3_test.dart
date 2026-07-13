import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

// Task 4(v3): 인출 소스를 RetirementInput flat 필드가 아니라 accounts 합산으로 재배선.
//   과세 연금 인출(월) = accounts.where(type==pension) 의 monthlyWithdrawal 합
//   비과세 인출(월)   = accounts.where(type==isa) 의 monthlyWithdrawal 합
// 절벽·나이세율·pensionNet 구조·게이지 규칙은 전부 불변.

// 인출 모드 ON · 나이 60(저율 5.5%) · flat 인출 필드는 0(엔진이 읽지 않음을 증명).
const _inputWithdrawingAge60 = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 0,
  monthlyOtherWithdrawal: 0,
  annualInterestIncome: 0,
  isWithdrawing: true,
);

void main() {
  test('연금 인출 = pension 계좌들 합산 (연금저축+IRP+유저 IRP)', () {
    final accounts = [
      kDefaultAccounts[2]
          .copyWith(monthlyWithdrawal: 800000, isWithdrawing: true), // 연금저축
      kDefaultAccounts[3]
          .copyWith(monthlyWithdrawal: 400000, isWithdrawing: true), // IRP
      const Account(
          id: 'u1',
          name: '미래에셋 IRP',
          type: AccountType.pension,
          monthlyWithdrawal: 100000,
          isWithdrawing: true),
    ];
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: _inputWithdrawingAge60,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    // 월 130만 → 연 1,560만 > 1,500만 절벽 → 전액 16.5%.
    expect(m.pensionGross, 1300000);
    expect(m.pensionNet, (1300000 * (1 - 0.165)).round());
  });

  test('ISA 인출은 비과세 그대로 + flat 필드는 더 이상 읽지 않음', () {
    final accounts = [
      kDefaultAccounts[1].copyWith(monthlyWithdrawal: 300000, isWithdrawing: true)
    ];
    final input = _inputWithdrawingAge60.copyWith(
        monthlyPensionWithdrawal: 9999999); // 엔진이 읽으면 안 되는 값
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: input,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    expect(m.pensionGross, 300000);
    expect(m.pensionNet, 300000);
  });

  test('buildGauges 절벽 게이지 = 계좌 합산 연 인출', () {
    final accounts = [
      kDefaultAccounts[2].copyWith(monthlyWithdrawal: 700000, isWithdrawing: true),
      kDefaultAccounts[3].copyWith(monthlyWithdrawal: 500000, isWithdrawing: true),
    ];
    final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: _inputWithdrawingAge60,
        year: 2026,
        accounts: accounts);
    expect(g.pensionLowRate.current, 1200000 * 12);
  });

  test('인출 모드 OFF — 계좌 인출액이 있어도 연금 0', () {
    final accounts = [
      kDefaultAccounts[2].copyWith(monthlyWithdrawal: 1000000),
      kDefaultAccounts[1].copyWith(monthlyWithdrawal: 500000),
    ];
    final off = _inputWithdrawingAge60.copyWith(isWithdrawing: false);
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: off,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    expect(m.pensionGross, 0);
    expect(m.pensionNet, 0);

    final g = CashflowEngine.buildGauges(
        holdings: const [],
        events: const [],
        input: off,
        year: 2026,
        accounts: accounts);
    expect(g.pensionLowRate.current, 0);
  });
}
