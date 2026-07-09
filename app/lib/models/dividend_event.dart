/// 배당 이벤트 — 종목별 배당락일/기준일 API 응답 모델.
class DividendEvent {
  final String corpCode;
  final String corpName;
  final DateTime? exDate;
  final DateTime? recordDate;
  final int perShare;
  final bool isConfirmed;

  const DividendEvent({
    required this.corpCode,
    required this.corpName,
    required this.exDate,
    required this.recordDate,
    required this.perShare,
    required this.isConfirmed,
  });

  /// API 실측 스키마(ex_date/record_date 'YYYY-MM-DD' 문자열, null 허용)를 안전 파싱한다.
  factory DividendEvent.fromJson(Map<String, dynamic> json) {
    return DividendEvent(
      corpCode: json['corp_code'] as String? ?? '',
      corpName: json['corp_name'] as String? ?? '',
      exDate: _parseDate(json['ex_date']),
      recordDate: _parseDate(json['record_date']),
      perShare: (json['per_share'] as num?)?.toInt() ?? 0,
      isConfirmed: json['is_confirmed'] as bool? ?? false,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Map<String, dynamic> toJson() => {
        'corp_code': corpCode,
        'corp_name': corpName,
        'ex_date': exDate?.toIso8601String().split('T').first,
        'record_date': recordDate?.toIso8601String().split('T').first,
        'per_share': perShare,
        'is_confirmed': isConfirmed,
      };

  /// 예상 지급월: 12월 기준일(결산배당) → 익년 4월 / 그 외(분기·중간) → 기준일 익월.
  /// recordDate 가 null 이면 exDate 기준. 둘 다 null 이면 null.
  DateTime? get expectedPaymentMonth {
    final basis = recordDate ?? exDate;
    if (basis == null) return null;
    if (basis.month == 12) {
      return DateTime(basis.year + 1, 4);
    }
    return DateTime(basis.year, basis.month + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DividendEvent &&
          runtimeType == other.runtimeType &&
          corpCode == other.corpCode &&
          corpName == other.corpName &&
          exDate == other.exDate &&
          recordDate == other.recordDate &&
          perShare == other.perShare &&
          isConfirmed == other.isConfirmed;

  @override
  int get hashCode => Object.hash(
        corpCode,
        corpName,
        exDate,
        recordDate,
        perShare,
        isConfirmed,
      );
}
