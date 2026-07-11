import '../models/dividend_event.dart';
import '../models/holding.dart';

/// 수동 입력(배당 API 미커버) 종목의 [DividendEvent] 를 합성한다.
///
/// 엔진 무수정 원칙 — 수동 종목을 특별 취급하지 않고, API 이벤트와 동일한
/// [DividendEvent] 로 변환해 기존 [CashflowEngine] 파이프라인에 그대로 흘려보낸다.
///
/// 규칙:
/// - 지급월마다 per_share = 연간배당 ÷ 지급월 수. 정수 나눗셈 잔여는 가장 이른 달에 몰아준다.
/// - 지급월 확정은 record/exDate 역산이 아니라 [DividendEvent.explicitPaymentMonth] 로 한다
///   (수동 종목은 기준일 정보가 없으므로).
/// - isConfirmed=false(예측 취급) · source='manual'(라인에서 "직접 입력" 구분용).
///
/// [holdings] 중 [Holding.isManual] 이고 [Holding.manualPaymentMonths] 가 비어있지
/// 않은 종목만 대상. [year] 의 지정 월에 이벤트를 생성한다.
List<DividendEvent> synthesizeManualEvents({
  required List<Holding> holdings,
  required int year,
}) {
  final events = <DividendEvent>[];

  for (final h in holdings) {
    final annual = h.manualPerShareAnnual;
    final rawMonths = h.manualPaymentMonths;
    if (annual == null || rawMonths == null || rawMonths.isEmpty) continue;

    // 1~12 범위만 채택 후 dedupe·오름차순 정렬(가장 이른 달이 첫 달).
    final months = rawMonths.where((m) => m >= 1 && m <= 12).toSet().toList()
      ..sort();
    if (months.isEmpty) continue;

    final base = annual ~/ months.length;
    final remainder = annual - base * months.length; // 첫 달에 가산.

    for (var i = 0; i < months.length; i++) {
      final perShare = base + (i == 0 ? remainder : 0);
      events.add(DividendEvent(
        corpCode: h.corpCode,
        corpName: h.corpName,
        exDate: null,
        recordDate: null,
        perShare: perShare,
        isConfirmed: false,
        explicitPaymentMonth: DateTime(year, months[i]),
        source: 'manual',
      ));
    }
  }

  return events;
}
