import 'package:excel/excel.dart';

import '../models/account.dart';
import '../models/holding.dart';
import 'cashflow_engine.dart';

/// 엑셀 내보내기(v2.3 설정) — 한 해 월별 현금흐름 · 배당 내역 · 보유 종목 3시트.
///
/// 순수 함수(파일 저장·공유는 호출부). 금액은 원 단위 정수 그대로 넣어
/// 엑셀에서 바로 합계·차트를 낼 수 있게 한다.
List<int> buildExportXlsx({
  required int year,
  required List<MonthlyCashflow> months,
  required List<Holding> holdings,
  required List<Account> accounts,
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final nameOf = {for (final a in accounts) a.id: a.name};
  CellValue t(String v) => TextCellValue(v);
  CellValue n(int v) => IntCellValue(v);

  final flow = excel['$year 월별'];
  flow.appendRow([
    t('월'),
    t('통장 입금(세후)'),
    t('일반계좌 배당(세후)'),
    t('연금 인출(세후)'),
    t('이자(세후)'),
    t('ISA·연금 계좌 배당(세전)'),
    t('총계(모든 계좌 배당+연금+이자)'),
  ]);
  for (final m in months) {
    flow.appendRow([
      t('${m.month.month}월'),
      n(m.totalNet),
      n(m.dividendNet),
      n(m.pensionNet),
      n(m.interestNet),
      n(m.reinvestGross),
      n(m.totalNet + m.reinvestGross),
    ]);
  }
  flow.appendRow([
    t('합계'),
    for (final pick in <int Function(MonthlyCashflow)>[
      (m) => m.totalNet,
      (m) => m.dividendNet,
      (m) => m.pensionNet,
      (m) => m.interestNet,
      (m) => m.reinvestGross,
      (m) => m.totalNet + m.reinvestGross,
    ])
      n(months.fold<int>(0, (s, m) => s + pick(m))),
  ]);

  final divs = excel['배당 내역'];
  divs.appendRow([t('월'), t('종목'), t('계좌'), t('세전'), t('세후'), t('구분')]);
  for (final m in months) {
    for (final l in [...m.lines, ...m.reinvestLines]) {
      divs.appendRow([
        t('${m.month.month}월'),
        t(l.corpName),
        t(nameOf[l.accountId] ?? l.accountId),
        n(l.amountGross),
        // ISA·연금 계좌 배당은 계좌에 남아 손에 들어오는 세후액이 아니다 — 빈칸.
        if (l.accountType == AccountType.general) n(l.amountNet) else t(''),
        t(
          '${l.isConfirmed ? '확정' : '예상'}'
          '${l.accountType == AccountType.general ? '' : ' · 계좌에 남음'}',
        ),
      ]);
    }
  }

  final hold = excel['보유 종목'];
  hold.appendRow([t('계좌'), t('종목'), t('수량')]);
  for (final h in holdings) {
    hold.appendRow([
      t(nameOf[h.accountId] ?? h.accountId),
      t(h.corpName),
      n(h.shares),
    ]);
  }

  if (defaultSheet != null) excel.delete(defaultSheet);
  return excel.save()!;
}
