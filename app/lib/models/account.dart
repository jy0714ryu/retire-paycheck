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

  /// 계좌별 인출 개시 여부 — true 면 이 계좌의 월 인출액이 달력·세금에 반영된다.
  final bool isWithdrawing;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.balance = 0,
    this.monthlyWithdrawal = 0,
    this.isWithdrawing = false,
  });

  bool get isDefault => id.startsWith('default_');

  Account copyWith({
    String? name,
    int? balance,
    int? monthlyWithdrawal,
    bool? isWithdrawing,
  }) =>
      Account(
        id: id,
        name: name ?? this.name,
        type: type,
        balance: balance ?? this.balance,
        monthlyWithdrawal: monthlyWithdrawal ?? this.monthlyWithdrawal,
        isWithdrawing: isWithdrawing ?? this.isWithdrawing,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'balance': balance,
        'monthly_withdrawal': monthlyWithdrawal,
        'is_withdrawing': isWithdrawing,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: AccountType.values.asNameMap()[json['type']] ??
            AccountType.general,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        monthlyWithdrawal: (json['monthly_withdrawal'] as num?)?.toInt() ?? 0,
        isWithdrawing: json['is_withdrawing'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Account &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          balance == other.balance &&
          monthlyWithdrawal == other.monthlyWithdrawal &&
          isWithdrawing == other.isWithdrawing;

  @override
  int get hashCode => Object.hash(
      id, name, type, balance, monthlyWithdrawal, isWithdrawing);
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

/// 유형 → 기본 계좌 id 매핑. `AccountsNotifier.remove()`가 유저 계좌 삭제 시
/// 소속 종목을 재배정할 대상을 결정할 때 사용한다. v3 에서 연금이
/// 연금저축/IRP 로 분리되면서 `'default_${type.name}'` 문자열 조합은 더 이상
/// 1:1 대응이 아니므로(연금 유형은 `default_pension` 이 존재하지 않는다) 이
/// 명시 매핑이 유일한 SSOT 다 — 마이그레이션의 연금 인출 라우팅과도 일관.
String defaultAccountIdFor(AccountType type) => switch (type) {
      AccountType.general => 'default_general',
      AccountType.isa => 'default_isa',
      AccountType.pension => 'default_pension_savings',
    };

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
