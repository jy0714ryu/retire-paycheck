import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/services/cashflow_engine.dart';
import 'package:retire_paycheck/services/excel_export.dart';

void main() {
  test('엑셀 3시트 — 월별 12행+합계, 배당 내역에 계좌 이름, 보유 종목', () {
    final months = [
      for (var m = 1; m <= 12; m++)
        MonthlyCashflow(
          month: DateTime(2026, m),
          dividendGross: m == 4 ? 500000 : 0,
          dividendNet: m == 4 ? 423000 : 0,
          pensionGross: 1000000,
          pensionNet: 945000,
          reinvestGross: m == 4 ? 300000 : 0,
          lines: [
            if (m == 4)
              const DividendLine(
                corpName: 'A사',
                amountGross: 500000,
                amountNet: 423000,
                isConfirmed: true,
              ),
          ],
          reinvestLines: [
            if (m == 4)
              const DividendLine(
                corpName: 'B사',
                amountGross: 300000,
                amountNet: 300000,
                isConfirmed: false,
                accountId: 'default_isa',
                accountType: AccountType.isa,
              ),
          ],
        ),
    ];
    final bytes = buildExportXlsx(
      year: 2026,
      months: months,
      holdings: const [Holding(corpCode: 'A', corpName: 'A사', shares: 1000)],
      accounts: kDefaultAccounts,
    );
    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys, containsAll(['2026 월별', '배당 내역', '보유 종목']));
    expect(x.tables.keys, isNot(contains('Sheet1')));

    final flow = x.tables['2026 월별']!;
    expect(flow.maxRows, 14); // 머리 + 12개월 + 합계
    final total = flow.rows.last;
    expect(total[0]!.value.toString(), '합계');
    expect((total[1]!.value as IntCellValue).value, 945000 * 12 + 423000);

    final divs = x.tables['배당 내역']!.rows;
    expect(divs.length, 3);
    expect(divs[2][2]!.value.toString(), 'ISA');
    expect(divs[2][4]?.value?.toString() ?? '', '');
    expect(divs[2][5]!.value.toString(), '예상 · 계좌에 남음');

    final hold = x.tables['보유 종목']!.rows;
    expect(hold[1][0]!.value.toString(), '일반계좌');
  });
}
