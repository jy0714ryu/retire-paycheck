/// 이자소득 항목 — 연 이자 금액(세전)과 지급월. 빈 [months]=월 균등 12분할.
/// 이자율×원금 계산은 지원하지 않는다(스펙 §1.4 — 입력 최소화).
class InterestItem {
  final String id;
  final String name;
  final int annualAmount;
  final List<int> months;

  const InterestItem({
    required this.id,
    required this.name,
    required this.annualAmount,
    this.months = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'annual_amount': annualAmount,
        'months': months,
      };

  factory InterestItem.fromJson(Map<String, dynamic> json) => InterestItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        annualAmount: (json['annual_amount'] as num?)?.toInt() ?? 0,
        months: (json['months'] is List)
            ? (json['months'] as List).map((e) => (e as num).toInt()).toList()
            : const [],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterestItem &&
          id == other.id &&
          name == other.name &&
          annualAmount == other.annualAmount &&
          _listEq(months, other.months);

  @override
  int get hashCode =>
      Object.hash(id, name, annualAmount, Object.hashAll(months));

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
