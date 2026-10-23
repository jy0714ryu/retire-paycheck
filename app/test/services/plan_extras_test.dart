import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/engine/pension_input.dart';
import 'package:retire_paycheck/engine/withdrawal_optimizer.dart';
import 'package:retire_paycheck/screens/plan_screen.dart';
import 'package:retire_paycheck/services/review_prompt.dart';
import 'package:retire_paycheck/utils/currency_format.dart';

void main() {
  test('리뷰 요청: 3번째 이후 · 절감 10만원 이상 · 평생 1회', () {
    expect(
      ReviewPrompt.shouldAsk(views: 2, alreadyAsked: false, savings: 500000),
      isFalse,
    );
    expect(
      ReviewPrompt.shouldAsk(views: 3, alreadyAsked: false, savings: 99999),
      isFalse,
    );
    expect(
      ReviewPrompt.shouldAsk(views: 3, alreadyAsked: false, savings: 100000),
      isTrue,
    );
    expect(
      ReviewPrompt.shouldAsk(views: 9, alreadyAsked: true, savings: 900000),
      isFalse,
    );
  });

  test('공유 문구: 전략·총 세금·절감만, 잔액·자산 금액은 넣지 않음', () {
    final input = PensionInput.example();
    final r = WithdrawalOptimizer.optimize(input);
    final text = planShareText(r, 20);
    expect(
      text,
      contains(planStrategyName(r.optimalStrategyId, r.optimalStrategyName)),
    );
    expect(text, contains('${CurrencyFormat.man(r.totalTaxOptimal)}만원'));
    expect(text, contains('투자 권유 아님'));
    for (final asset in [
      input.pensionSavings,
      input.irpBalance,
      input.isaMaturity,
    ]) {
      expect(text, isNot(contains('${CurrencyFormat.man(asset)}만')));
    }
  });
}
