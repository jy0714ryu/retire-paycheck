import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';

// Task 4(v4): 인출 소스를 전역 input.isWithdrawing 게이트가 아니라 계좌별
//   Account.isWithdrawing 게이트로 재배선한다.
//   과세 연금 인출(월) = accounts.where(type==pension && isWithdrawing) 합
//   비과세 인출(월)   = accounts.where(type==isa && isWithdrawing) 합
// 절벽(연 과세 인출 합 × 12 > 1,500만 → 전액 16.5%)은 인출을 켠 pension 계좌
// 합산(사람 단위)으로 판정한다. 나이세율·pensionNet 구조·게이지 규칙 불변.

// flat 인출 필드 0 · input.isWithdrawing 미지정(기본 false) — 엔진이 전역
// 게이트를 더 이상 읽지 않음을 증명.
const _input60 = RetirementInput(
    pensionSavings: 0,
    irpBalance: 0,
    isaBalance: 0,
    currentAge: 60,
    monthlyPensionWithdrawal: 0,
    monthlyOtherWithdrawal: 0);

void main() {
  test('계좌별 게이트 — 인출 ON 계좌만 산입', () {
    final accounts = [
      kDefaultAccounts[2]
          .copyWith(monthlyWithdrawal: 800000, isWithdrawing: true), // 연금저축 ON
      kDefaultAccounts[3]
          .copyWith(monthlyWithdrawal: 400000, isWithdrawing: false), // IRP OFF
    ];
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: _input60,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    expect(m.pensionGross, 800000); // IRP OFF 라 제외
  });

  test('절벽 = 인출 켠 pension 계좌 합산 × 12 (사람 단위)', () {
    final accounts = [
      kDefaultAccounts[2].copyWith(monthlyWithdrawal: 700000, isWithdrawing: true),
      kDefaultAccounts[3].copyWith(monthlyWithdrawal: 600000, isWithdrawing: true),
    ];
    // 합 130만 × 12 = 1,560만 > 1,500만 → 전액 16.5%.
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: _input60,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    expect(m.pensionNet, (1300000 * (1 - 0.165)).round());
  });

  test('ISA 인출도 계좌별 게이트', () {
    final accounts = [
      kDefaultAccounts[1]
          .copyWith(monthlyWithdrawal: 300000, isWithdrawing: false),
    ];
    final m = CashflowEngine.buildMonths(
            holdings: const [],
            events: const [],
            input: _input60,
            from: DateTime(2026, 1, 1),
            monthCount: 1,
            accounts: accounts)
        .first;
    expect(m.pensionGross, 0); // ISA OFF
  });
}
