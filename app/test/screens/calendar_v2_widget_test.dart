// 화면2 v2 바인딩 — 최종 합산 고정·계좌 필터 칩·재투자 아코디언.
// 시드: 일반계좌 A사 1,000주 + ISA B사 1,000주, 둘 다 per_share 500 · 2026-04 지급.
// 4월 실수령(all) = 일반 net 423,000 + ISA net 500,000 = 923,000 → 92.3만원.
// ISA 필터로 바꿔도 상단 합산 카드(92.3만원)는 불변 + 상세에서 일반주(A사) 사라짐.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:retire_paycheck/models/account.dart';
import 'package:retire_paycheck/models/dividend_event.dart';
import 'package:retire_paycheck/models/holding.dart';
import 'package:retire_paycheck/models/interest_item.dart';
import 'package:retire_paycheck/models/retirement_input.dart';
import 'package:retire_paycheck/providers/app_providers.dart';
import 'package:retire_paycheck/screens/calendar_screen.dart';
import 'package:retire_paycheck/services/dividend_api.dart';

/// 금액 문구 찾기 — 일반 텍스트 "186.8만원" 과 v2 메인 카드의 분리 표기 "186.8 만원"(RichText) 모두 인식.
Finder findWon(String man) => find.byWidgetPredicate((w) {
  if (w is Text) {
    if (w.data == '$man만원') return true;
    final span = w.textSpan?.toPlainText();
    return span == '$man 만원' || span == '$man만원';
  }
  return false;
});

final _eventGeneral = DividendEvent(
  corpCode: 'A',
  corpName: '일반주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _eventIsa = DividendEvent(
  corpCode: 'B',
  corpName: 'ISA주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _eventPension = DividendEvent(
  corpCode: 'C',
  corpName: '연금주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 500,
  isConfirmed: true,
);
final _eventSplit = DividendEvent(
  corpCode: 'X',
  corpName: '분할보유주',
  exDate: null,
  recordDate: DateTime(2025, 12, 31),
  perShare: 1000,
  isConfirmed: true,
);

/// 테스트 전용 시드 헬퍼 — [HoldingsNotifier.add] 는 corpCode 로 dedup 하므로
/// 같은 종목을 두 계좌에 나눠 보유하는 상태를 add() 루프로 만들 수 없다.
/// state 를 직접 주입해 분할 보유 시나리오(M1)를 재현한다.
class _SplitHoldingsNotifier extends HoldingsNotifier {
  _SplitHoldingsNotifier(List<Holding> seed) {
    state = seed;
  }
}

const _input = RetirementInput(
  pensionSavings: 0,
  irpBalance: 0,
  isaBalance: 0,
  currentAge: 60,
  monthlyPensionWithdrawal: 0,
  monthlyOtherWithdrawal: 0,
  annualInterestIncome: 0,
  isWithdrawing: false,
);

/// 이번 달 탭을 '배당 전체' 보기로 전환 (setUp 은 '통장 입금' 고정).
Future<void> _showAllDividends(WidgetTester tester) async {
  // 목록 아래로 내려가 있으면 전환 버튼이 아직 안 그려져 있다 — 위로 올린다.
  if (find.text('배당 전체').evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text('배당 전체'), -300);
  }
  await tester.ensureVisible(find.text('배당 전체'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('배당 전체'));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  List<Holding> holdings = const [],
  List<DividendEvent> events = const [],
  List<InterestItem> interestItems = const [],
  RetirementInput input = _input,
  // v4: 연금 타일·절벽 캡션 게이트는 전역 input.isWithdrawing 이 아니라
  // 계좌별 Account.isWithdrawing (최종 리뷰 C1). null 이면 유저 계좌 없음.
  List<Account>? accounts,
  DateTime? initialMonth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        holdingsProvider.overrideWith((ref) {
          final n = HoldingsNotifier();
          for (final h in holdings) {
            n.add(h);
          }
          return n;
        }),
        retirementInputProvider.overrideWith(
          (ref) => RetirementInputNotifier()..update((_) => input),
        ),
        if (accounts != null)
          accountsProvider.overrideWith((ref) {
            final n = AccountsNotifier(ref);
            for (final a in accounts) {
              n.add(a);
            }
            return n;
          }),
        interestItemsProvider.overrideWith((ref) {
          final n = InterestItemsNotifier();
          for (final i in interestItems) {
            n.add(i);
          }
          return n;
        }),
        dividendEventsProvider.overrideWith(
          (ref) async => DividendFetchResult(
            events: events,
            fetchedAt: DateTime(2026, 1, 1),
            fromCache: false,
          ),
        ),
      ],
      child: MaterialApp(home: CalendarScreen(initialMonth: initialMonth)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // 기존 회귀는 '통장 입금' 보기 기준 (v2.1 기본은 '배당 전체').
    SharedPreferences.setMockInitialValues({'calendar_view': false});
  });

  testWidgets('배당 전체 보기: 필터를 ISA 로 바꿔도 상단 합산 카드는 불변 + 상세에서 일반주 사라짐', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      holdings: const [
        Holding(corpCode: 'A', corpName: '일반주', shares: 1000),
        Holding(
          corpCode: 'B',
          corpName: 'ISA주',
          shares: 1000,
          accountId: 'default_isa',
        ),
      ],
      events: [_eventGeneral, _eventIsa],
      initialMonth: DateTime(2026, 4),
    );

    // v2.1: ISA 배당은 계좌 안 — '배당 전체' 보기에서 카드 = 세전 100만원(일반 50 + ISA 50).
    await _showAllDividends(tester);
    expect(findWon('100'), findsOneWidget);
    // 상세: 전체 모드에선 일반주·ISA주 둘 다 노출(스크롤로 뷰포트에 올림).
    final general = find.text('일반주');
    await tester.scrollUntilVisible(general, 200);
    expect(general, findsOneWidget);
    await tester.scrollUntilVisible(find.text('ISA주'), 200);
    expect(find.text('ISA주'), findsOneWidget);

    // 상단으로 복귀(월 네비게이션) → 카드·칩 모두 뷰포트에(offset≈0).
    await tester.scrollUntilVisible(find.text('2026년 4월'), -300);
    // ISA 칩 탭(추가 스크롤 없이 — ensureVisible 은 카드를 밀어내므로 금지).
    await tester.tap(find.widgetWithText(ChoiceChip, 'ISA'));
    await tester.pumpAndSettle();

    // 상단 합산 카드 불변(100만원 그대로 — 필터와 무관).
    expect(findWon('100'), findsOneWidget);

    // 상세로 스크롤 → ISA주만 남고 일반주는 사라짐.
    final isaLine = find.text('ISA주');
    await tester.scrollUntilVisible(isaLine, 200);
    expect(isaLine, findsOneWidget);
    expect(find.text('일반주'), findsNothing);
  });

  testWidgets('배당 라인 타일 — 일반계좌는 세후 42.3만원, ISA는 비과세 50만원 그대로 표시(C1 회귀 가드)', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      holdings: const [
        Holding(corpCode: 'A', corpName: '일반주', shares: 1000),
        Holding(
          corpCode: 'B',
          corpName: 'ISA주',
          shares: 1000,
          accountId: 'default_isa',
        ),
      ],
      events: [_eventGeneral, _eventIsa],
      initialMonth: DateTime(2026, 4),
    );

    // 통장 입금 보기: 일반계좌 라인 gross 500,000 × (1-0.154) = 423,000 → 세후 "42.3만원"
    // (엔진 amountNet 그대로 — 화면에서 재계산 금지).
    final generalLine = find.text('일반주');
    await tester.scrollUntilVisible(generalLine, 200);
    // 통장 보기 카드(ISA 배당은 계좌 안이라 일반 세후만) + 일반 라인 = 42.3 두 곳.
    expect(findWon('42.3'), findsNWidgets(2));

    // v2.1 배당 전체 보기: 카드·막대와 같은 세전 기준 + ISA 라인에 "계좌 안" 배지.
    await _showAllDividends(tester);
    await tester.scrollUntilVisible(find.text('일반주'), 200);
    expect(findWon('42.3'), findsNothing);

    // ISA 라인: 비과세 — line.amountNet(=gross 그대로) 을 재계산 없이 표시 →
    // "50만원"(라인이 gross×0.846 으로 재계산하면 "42.3만원"이 되어 실패한다).
    final isaLine = find.text('ISA주');
    await tester.scrollUntilVisible(isaLine, 200);
    expect(findWon('50'), findsNWidgets(2)); // 일반 세전 50 + ISA 50
    expect(find.text('계좌 안'), findsOneWidget);
  });

  testWidgets('연금계좌 배당 → 재투자 아코디언(기본 접힘) + 펼치면 과세이연 캡션', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      holdings: const [
        Holding(
          corpCode: 'C',
          corpName: '연금주',
          shares: 1000,
          accountId: 'default_pension_savings',
        ),
      ],
      events: [_eventPension],
      initialMonth: DateTime(2026, 4),
    );

    // 재투자 세전 = 500 × 1,000 = 500,000원. 접힌 제목 노출.
    final title = find.text('계좌 안 배당 (연금·ISA) +500,000원');
    await tester.scrollUntilVisible(title, 200);
    expect(title, findsOneWidget);
    // 기본 접힘 → 캡션 미노출.
    expect(find.textContaining('인출 전까지 계좌 안에 남습니다'), findsNothing);

    // 펼치면 과세이연 캡션 노출.
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.textContaining('인출 전까지 계좌 안에 남습니다'), findsOneWidget);
  });

  testWidgets('이자소득 존재 시 상단 카드 서브라인에 이자 병기', (WidgetTester tester) async {
    await _pump(
      tester,
      holdings: const [Holding(corpCode: 'A', corpName: '일반주', shares: 1000)],
      events: [_eventGeneral],
      interestItems: const [
        InterestItem(id: 'i1', name: '정기예금', annualAmount: 1200000),
      ],
      initialMonth: DateTime(2026, 4),
    );

    // 이자 월 균등 = 100,000 → 이자 10만 병기.
    expect(find.textContaining('+ 이자 10만'), findsOneWidget);
  });

  testWidgets('연금 인출 모드 OFF → 필터가 all/연금 이어도 달력에 연금 타일 없음(I1)', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      // _input.isWithdrawing = false (본 파일 기본값).
      holdings: const [Holding(corpCode: 'A', corpName: '일반주', shares: 1000)],
      events: [_eventGeneral],
      initialMonth: DateTime(2026, 4),
    );

    // 전체(all) 필터에서도 "계좌 인출" 섹션 자체가 렌더되지 않아야 한다.
    expect(find.text('계좌 인출'), findsNothing);

    // '연금' 칩으로 바꿔도(과거엔 이 필터에서 무조건 노출) 여전히 미노출.
    await tester.tap(find.widgetWithText(ChoiceChip, '연금'));
    await tester.pumpAndSettle();
    expect(find.text('계좌 인출'), findsNothing);
  });

  testWidgets('전역 OFF(신규 유저 기본)라도 계좌별 인출 ON 이면 연금 타일·절벽 캡션 노출(C1 회귀)', (
    WidgetTester tester,
  ) async {
    // _input.isWithdrawing = false (신규 유저 기본, v4 는 전역 토글 없음).
    // 그럼에도 pension 계좌 인출 ON + 월 인출 140만(연 1,680만 > 1,500만)이면
    // 연금 타일과 절벽 경고 캡션이 떠야 한다 — C1 이 고쳐지기 전엔 실패.
    await _pump(
      tester,
      holdings: const [Holding(corpCode: 'A', corpName: '일반주', shares: 1000)],
      events: [_eventGeneral],
      accounts: const [
        Account(
          id: 'wp',
          name: '연금인출',
          type: AccountType.pension,
          monthlyWithdrawal: 1400000,
          isWithdrawing: true,
        ),
      ],
      initialMonth: DateTime(2026, 4),
    );

    // 절벽 캡션(유니크)을 앵커로 스크롤 — 보이면 연금 섹션이 렌더된 것.
    final cliff = find.text('연 1,500만원 초과 — 16.5% 적용');
    await tester.scrollUntilVisible(
      cliff,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(cliff, findsOneWidget);
    expect(find.text('계좌 인출'), findsWidgets);
  });

  testWidgets('같은 corpCode 를 일반+ISA 두 계좌에 나눠 보유 → 각 라인 수량이 계좌 몫과 일치(M1)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // HoldingsNotifier.add() 는 corpCode dedup 이라 일반적 시드 경로로는
          // 분할 보유를 만들 수 없다 — state 직접 주입 헬퍼 사용.
          holdingsProvider.overrideWith(
            (ref) => _SplitHoldingsNotifier(const [
              Holding(corpCode: 'X', corpName: '분할보유주', shares: 500),
              Holding(
                corpCode: 'X',
                corpName: '분할보유주',
                shares: 300,
                accountId: 'default_isa',
              ),
            ]),
          ),
          retirementInputProvider.overrideWith(
            (ref) => RetirementInputNotifier()..update((_) => _input),
          ),
          interestItemsProvider.overrideWith((ref) => InterestItemsNotifier()),
          dividendEventsProvider.overrideWith(
            (ref) async => DividendFetchResult(
              events: [_eventSplit],
              fetchedAt: DateTime(2026, 1, 1),
              fromCache: false,
            ),
          ),
        ],
        child: MaterialApp(
          home: CalendarScreen(initialMonth: DateTime(2026, 4)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // v2.1: ISA 몫은 계좌 안 — 두 라인을 함께 보려면 '배당 전체' 보기.
    await _showAllDividends(tester);

    // 두 라인 모두 이름이 "분할보유주"로 동일해 scrollUntilVisible 에 그대로 쓰면
    // 다중 매치로 실패한다 — 고유한 수량 상세 텍스트로 스크롤한다.
    final generalDetail = find.textContaining('주당 1,000원 × 500주');
    await tester.scrollUntilVisible(generalDetail, 200);
    // 일반계좌 라인(500주)·ISA 라인(300주) 각각 자기 몫의 수량을 표시해야 한다
    // (버그 시 sharesByName 이 corpName 단일 키라 마지막 holding 값으로 덮어써져
    // 두 라인이 동일 수량을 표시한다).
    expect(generalDetail, findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('주당 1,000원 × 300주'),
      200,
    );
    expect(find.textContaining('주당 1,000원 × 300주'), findsOneWidget);
    expect(find.text('분할보유주'), findsNWidgets(2));
  });

  testWidgets('v2.1 기본 보기 = 배당 전체, 통장 입금으로 바꾸면 카드 제목이 바뀌고 선택이 저장된다', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(
      tester,
      holdings: const [Holding(corpCode: 'A', corpName: '일반주', shares: 1000)],
      events: [_eventGeneral],
      initialMonth: DateTime(2026, 4),
    );
    expect(find.text('이번 달 배당 총액 (세전)'), findsOneWidget);
    await tester.tap(find.text('통장 입금'));
    await tester.pumpAndSettle();
    expect(find.text('이번 달 세후 은퇴 월급'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('calendar_view'), isFalse);
  });
}
