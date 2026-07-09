/// 보유 종목 (배당 캘린더 산출용) — corp_code·이름·수량.
class Holding {
  final String corpCode;
  final String corpName;
  final int shares;

  const Holding({
    required this.corpCode,
    required this.corpName,
    required this.shares,
  });

  Holding copyWith({String? corpCode, String? corpName, int? shares}) {
    return Holding(
      corpCode: corpCode ?? this.corpCode,
      corpName: corpName ?? this.corpName,
      shares: shares ?? this.shares,
    );
  }

  Map<String, dynamic> toJson() => {
        'corp_code': corpCode,
        'corp_name': corpName,
        'shares': shares,
      };

  factory Holding.fromJson(Map<String, dynamic> json) {
    return Holding(
      corpCode: json['corp_code'] as String? ?? '',
      corpName: json['corp_name'] as String? ?? '',
      shares: (json['shares'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Holding &&
          runtimeType == other.runtimeType &&
          corpCode == other.corpCode &&
          corpName == other.corpName &&
          shares == other.shares;

  @override
  int get hashCode => Object.hash(corpCode, corpName, shares);
}
