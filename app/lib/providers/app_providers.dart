import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import '../services/dividend_api.dart';
import '../services/manual_dividends.dart';

/// SharedPreferences persist 키.
const String _kHoldingsKey = 'holdings';
const String _kRetirementInputKey = 'retirement_input';
const String _kAccountsKey = 'accounts';
const String _kInterestItemsKey = 'interest_items';

/// 보유 종목 목록 상태 — SharedPreferences('holdings')에 jsonEncode 로 영속.
///
/// 앱 시작 시 생성자에서 즉시 로드(비동기). 변경 시마다 자동 저장.
class HoldingsNotifier extends StateNotifier<List<Holding>> {
  HoldingsNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHoldingsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => Holding.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 손상된 캐시는 무시하고 빈 목록 유지.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kHoldingsKey,
      jsonEncode(state.map((h) => h.toJson()).toList()),
    );
  }

  /// 종목 추가(동일 corpCode 존재 시 수량 갱신).
  void add(Holding holding) {
    final idx = state.indexWhere((h) => h.corpCode == holding.corpCode);
    if (idx >= 0) {
      final next = [...state];
      next[idx] = holding;
      state = next;
    } else {
      state = [...state, holding];
    }
    _persist();
  }

  /// 인덱스로 삭제(스와이프 삭제용).
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
    _persist();
  }

  /// 소속 계좌 일괄 이동 — 계좌 삭제 시 [AccountsNotifier] 가 호출한다
  /// (`from` 소속 종목을 같은 유형 기본 계좌 `to` 로 재배정).
  void reassignAccount(String from, String to) {
    if (!state.any((h) => h.accountId == from)) return;
    state = [
      for (final h in state)
        h.accountId == from ? h.copyWith(accountId: to) : h,
    ];
    _persist();
  }
}

final holdingsProvider =
    StateNotifierProvider<HoldingsNotifier, List<Holding>>(
  (ref) => HoldingsNotifier(),
);

/// 연금 자산·인출 계획 입력 상태 — SharedPreferences('retirement_input')에 영속.
class RetirementInputNotifier extends StateNotifier<RetirementInput> {
  RetirementInputNotifier() : super(_defaultInput) {
    _load();
  }

  /// 나이 기본값 60(연금 수령 연령대 가정), 나머지 0.
  static const RetirementInput _defaultInput = RetirementInput(
    pensionSavings: 0,
    irpBalance: 0,
    isaBalance: 0,
    currentAge: 60,
    monthlyPensionWithdrawal: 0,
    monthlyOtherWithdrawal: 0,
    annualInterestIncome: 0,
    isWithdrawing: false,
  );

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRetirementInputKey);
    if (raw == null || raw.isEmpty) return;
    try {
      state = RetirementInput.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // 손상된 캐시는 무시하고 기본값 유지.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRetirementInputKey, jsonEncode(state.toJson()));
  }

  void update(RetirementInput Function(RetirementInput) mutate) {
    state = mutate(state);
    _persist();
  }

  void updatePensionSavings(int v) => update((s) => s.copyWith(pensionSavings: v));
  void updateIrpBalance(int v) => update((s) => s.copyWith(irpBalance: v));
  void updateIsaBalance(int v) => update((s) => s.copyWith(isaBalance: v));
  void updateCurrentAge(int v) => update((s) => s.copyWith(currentAge: v));
  void updateMonthlyPensionWithdrawal(int v) =>
      update((s) => s.copyWith(monthlyPensionWithdrawal: v));
  void updateMonthlyOtherWithdrawal(int v) =>
      update((s) => s.copyWith(monthlyOtherWithdrawal: v));
  void updateAnnualInterestIncome(int v) =>
      update((s) => s.copyWith(annualInterestIncome: v));
}

final retirementInputProvider =
    StateNotifierProvider<RetirementInputNotifier, RetirementInput>(
  (ref) => RetirementInputNotifier(),
);

/// 배당 이벤트 목록 — DividendApi.fetchAll (24h 캐시·오프라인 폴백).
///
/// 종목 검색 소스(corp_name dedupe)와 CashflowEngine 입력으로 공용.
final dividendEventsProvider =
    FutureProvider<DividendFetchResult>((ref) async {
  final force = ref.watch(forceRefreshProvider) > 0;
  return DividendApi().fetchAll(force: force);
});

/// 당겨서 새로고침 카운터 — 증가시키면 [dividendEventsProvider] 가 신선 캐시를
/// 무시하고 네트워크를 강제한다 (서버 데이터 갱신 즉시 반영 경로).
final forceRefreshProvider = StateProvider<int>((ref) => 0);

/// API 이벤트 + 수동 입력 종목 합성 이벤트 merge — calendar/gauge 공용 소비 지점.
///
/// family 파라미터 = 기준 연도(합성 이벤트의 지급월이 이 연도에 생성됨).
/// holdings 변경(수동 종목 추가·삭제) 시 자동 재계산된다. 엔진 무수정 원칙 —
/// 수동 종목도 동일한 [DividendEvent] 로 흘려보낸다.
final combinedEventsProvider =
    FutureProvider.family<List<DividendEvent>, int>((ref, year) async {
  final result = await ref.watch(dividendEventsProvider.future);
  final holdings = ref.watch(holdingsProvider);
  return [
    ...result.events,
    ...synthesizeManualEvents(holdings: holdings, year: year),
  ];
});

/// 유저 계좌 목록 상태 — SharedPreferences('accounts')에 jsonEncode 로 영속.
///
/// 기본 계좌 3개([kDefaultAccounts])는 저장하지 않는다 — 이 목록은 유저가
/// 직접 추가한 계좌만 담는다.
class AccountsNotifier extends StateNotifier<List<Account>> {
  AccountsNotifier(this._ref) : super(const []) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 손상된 캐시는 무시하고 빈 목록 유지.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kAccountsKey,
      jsonEncode(state.map((a) => a.toJson()).toList()),
    );
  }

  /// 계좌 추가.
  void add(Account account) {
    state = [...state, account];
    _persist();
  }

  /// 이름 변경(기본 계좌는 목록에 없으므로 대상 아님).
  void rename(String id, String name) {
    final idx = state.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final next = [...state];
    next[idx] = Account(id: next[idx].id, name: name, type: next[idx].type);
    state = next;
    _persist();
  }

  /// 계좌 삭제 — 소속 종목을 같은 유형의 기본 계좌(`default_<type>`)로 이동.
  void remove(String id) {
    final idx = state.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final removed = state[idx];
    state = [...state]..removeAt(idx);
    _persist();
    _ref
        .read(holdingsProvider.notifier)
        .reassignAccount(id, 'default_${removed.type.name}');
  }
}

final accountsProvider =
    StateNotifierProvider<AccountsNotifier, List<Account>>(
  (ref) => AccountsNotifier(ref),
);

/// 이자소득 항목 목록 상태 — SharedPreferences('interest_items')에 영속.
///
/// 키는 [runMigrations] v1→v2 이관이 쓰는 키와 동일 — 마이그레이션 산출물을
/// 그대로 로드한다.
class InterestItemsNotifier extends StateNotifier<List<InterestItem>> {
  InterestItemsNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInterestItemsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => InterestItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // 손상된 캐시는 무시하고 빈 목록 유지.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kInterestItemsKey,
      jsonEncode(state.map((i) => i.toJson()).toList()),
    );
  }

  /// 이자소득 항목 추가.
  void add(InterestItem item) {
    state = [...state, item];
    _persist();
  }

  /// 인덱스로 삭제.
  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
    _persist();
  }
}

final interestItemsProvider =
    StateNotifierProvider<InterestItemsNotifier, List<InterestItem>>(
  (ref) => InterestItemsNotifier(),
);
