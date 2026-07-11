/// 계좌 유형 — 배당 세금 처리가 갈리는 3분류 (스펙 §2 분기표).
enum AccountType { general, isa, pension }

/// 계좌 — 유형(세금 엔진용) + 이름(보기용). 기본 계좌 3개는 저장소에 기록하지
/// 않는 코드 상수([kDefaultAccounts])로 항상 존재한다.
class Account {
  final String id;
  final String name;
  final AccountType type;

  const Account({required this.id, required this.name, required this.type});

  bool get isDefault => id.startsWith('default_');

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': type.name};

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: AccountType.values.asNameMap()[json['type']] ??
            AccountType.general,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          id == other.id &&
          name == other.name &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, name, type);
}

/// 기본 계좌 3개 — 삭제·이름변경 불가, 유형당 1개 암묵 존재.
const List<Account> kDefaultAccounts = [
  Account(id: 'default_general', name: '일반계좌', type: AccountType.general),
  Account(id: 'default_isa', name: 'ISA', type: AccountType.isa),
  Account(id: 'default_pension', name: '연금계좌', type: AccountType.pension),
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
