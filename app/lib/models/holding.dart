/// 보유 종목 (배당 캘린더 산출용) — corp_code·이름·수량.
///
/// 배당 API(공시 기반)에 없는 종목·ETF는 유저가 직접 입력한다. 이 경우
/// [manualPerShareAnnual](주당 연간 배당금)·[manualPaymentMonths](지급월)을 채우고
/// corpCode 는 `manual_<고유값>` 형태를 쓴다. API 종목은 두 필드 모두 null.
class Holding {
  final String corpCode;
  final String corpName;
  final int shares;

  /// 수동 입력 종목의 주당 연간 배당금(원). null 이면 API 종목.
  final int? manualPerShareAnnual;

  /// 수동 입력 종목의 지급월(1~12) 목록. null/빈 목록이면 합성 대상 아님.
  final List<int>? manualPaymentMonths;

  const Holding({
    required this.corpCode,
    required this.corpName,
    required this.shares,
    this.manualPerShareAnnual,
    this.manualPaymentMonths,
  });

  /// 수동 입력(배당 API 미커버) 종목 여부.
  bool get isManual => manualPerShareAnnual != null;

  Holding copyWith({
    String? corpCode,
    String? corpName,
    int? shares,
    int? manualPerShareAnnual,
    List<int>? manualPaymentMonths,
  }) {
    return Holding(
      corpCode: corpCode ?? this.corpCode,
      corpName: corpName ?? this.corpName,
      shares: shares ?? this.shares,
      manualPerShareAnnual: manualPerShareAnnual ?? this.manualPerShareAnnual,
      manualPaymentMonths: manualPaymentMonths ?? this.manualPaymentMonths,
    );
  }

  Map<String, dynamic> toJson() => {
        'corp_code': corpCode,
        'corp_name': corpName,
        'shares': shares,
        // 하위호환: 수동 종목만 새 키를 기록(API 종목 저장분은 키 없이 유지).
        if (manualPerShareAnnual != null)
          'manual_per_share_annual': manualPerShareAnnual,
        if (manualPaymentMonths != null)
          'manual_payment_months': manualPaymentMonths,
      };

  factory Holding.fromJson(Map<String, dynamic> json) {
    final months = json['manual_payment_months'];
    return Holding(
      corpCode: json['corp_code'] as String? ?? '',
      corpName: json['corp_name'] as String? ?? '',
      shares: (json['shares'] as num?)?.toInt() ?? 0,
      manualPerShareAnnual: (json['manual_per_share_annual'] as num?)?.toInt(),
      manualPaymentMonths: months is List
          ? months.map((e) => (e as num).toInt()).toList()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Holding &&
          runtimeType == other.runtimeType &&
          corpCode == other.corpCode &&
          corpName == other.corpName &&
          shares == other.shares &&
          manualPerShareAnnual == other.manualPerShareAnnual &&
          _listEq(manualPaymentMonths, other.manualPaymentMonths);

  @override
  int get hashCode => Object.hash(
        corpCode,
        corpName,
        shares,
        manualPerShareAnnual,
        manualPaymentMonths == null
            ? null
            : Object.hashAll(manualPaymentMonths!),
      );

  static bool _listEq(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
