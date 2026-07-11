import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dividend_event.dart';
import '../models/holding.dart';
import '../models/retirement_input.dart';
import '../services/dividend_api.dart';
import '../services/manual_dividends.dart';

/// SharedPreferences persist 키.
const String _kHoldingsKey = 'holdings';
const String _kRetirementInputKey = 'retirement_input';

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
  return DividendApi().fetchAll();
});

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
