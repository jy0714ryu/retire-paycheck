/// 계좌 유형 — 배당 세금 처리가 갈리는 3분류 (스펙 §2 분기표).
enum AccountType { general, isa, pension }

/// 계좌 — 유형(세금 엔진용) + 이름(보기용) + 잔액·월 인출액(v3, 계좌 중심 IA).
/// 기본 계좌 4개는 저장소에 기록하지 않는 코드 상수([kDefaultAccounts])로
/// 항상 존재하며, 잔액·인출 오버라이드만 별도 저장소(Task 2)에 영속된다.
class Account {
  final String id;
  final String name;
  final AccountType type;

  /// 현금성 잔액(원) — ISA·연금 계좌 전용, 일반계좌는 항상 0 (UI 미노출).
  final int balance;

  /// 월 인출액(원) — 인출 모드 ON 일 때 달력·세금에 반영. 일반계좌는 항상 0.
  final int monthlyWithdrawal;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.monthlyWithdrawal = 0,
  });

  bool get isDefault => id.startsWith('default_');

  Account copyWith({String? name, int? balance, int? monthlyWithdrawal}) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type,
        balance: balance ?? this.balance,
        monthlyWithdrawal: monthlyWithdrawal ?? this.monthlyWithdrawal,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'balance': balance,
        'monthly_withdrawal': monthlyWithdrawal,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: AccountType.values.asNameMap()[json['type']] ??
            AccountType.general,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        monthlyWithdrawal: (json['monthly_withdrawal'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          balance == other.balance &&
          monthlyWithdrawal == other.monthlyWithdrawal;

  @override
  int get hashCode => Object.hash(id, name, type, balance, monthlyWithdrawal);
}

/// 기본 계좌 4개 — 삭제·이름변경 불가. 연금은 연금저축·IRP 로 분리(구 단일
/// `default_pension` 은 폐지, 저장분 이관은 마이그레이션(Task 3) 소관).
const List<Account> kDefaultAccounts = [
  Account(id: 'default_general', name: '일반계좌', type: AccountType.general),
  Account(id: 'default_isa', name: 'ISA', type: AccountType.isa),
  Account(
      id: 'default_pension_savings',
      name: '연금저축',
      type: AccountType.pension),
  Account(id: 'default_irp', name: 'IRP', type: AccountType.pension),
];

/// id → 계좌 해석. 기본 계좌 우선, 유저 계좌 순회, 없으면 null
/// (호출부가 default_general 폴백 — 삭제된 계좌 참조 안전망).
Account? resolveAccount(String id, List<Account> userAccounts) {
  for (final a in kDefaultAccounts) {
    if (a.id == id) return a;
  }
  for (final a in userAccounts) {
    if (a.id == id) return a;
  }
  return null;
}
