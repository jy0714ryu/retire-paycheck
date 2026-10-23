import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/holding.dart';
import '../models/interest_item.dart';
import '../models/retirement_input.dart';
import '../screens/quick_start_screen.dart';

/// 웹 체험판 전용 — 처음 열면 계좌 종류별 예시 자산을 채운다.
/// `--dart-define=RETIRE_DEMO_SEED=true` 로 빌드할 때만 켜지고, 앱(AAB) 빌드에서는
/// 컴파일 상수 false 라 코드째 빠진다.
const bool kDemoSeedEnabled = bool.fromEnvironment('RETIRE_DEMO_SEED');

const String _kDemoSeededKey = 'demo_seeded_v1';

/// 아직 채운 적이 없으면 예시 자산을 쓴다. 이후 사용자가 고친 값은 덮어쓰지 않는다.
Future<void> seedDemoIfNeeded(SharedPreferences prefs) async {
  if (!kDemoSeedEnabled || (prefs.getBool(_kDemoSeededKey) ?? false)) return;

  const holdings = [
    // 일반계좌 — 배당 15.4% 원천징수, 통장으로 바로 들어옴.
    Holding(corpCode: '005930', corpName: '삼성전자', shares: 1000),
    Holding(corpCode: '055550', corpName: '신한지주', shares: 800),
    Holding(corpCode: '161510', corpName: 'PLUS 고배당주', shares: 2000),
    // ISA — 배당은 계좌에 쌓임(비과세 한도 안).
    Holding(
      corpCode: '441640',
      corpName: 'KODEX 미국배당커버드콜액티브',
      shares: 3000,
      accountId: 'default_isa',
    ),
    // 연금저축·IRP — 배당은 계좌에 쌓이고 세금은 꺼낼 때.
    Holding(
      corpCode: '458730',
      corpName: 'TIGER 미국배당다우존스',
      shares: 4000,
      accountId: 'default_pension_savings',
    ),
    Holding(
      corpCode: '446720',
      corpName: 'SOL 미국배당다우존스',
      shares: 2000,
      accountId: 'default_irp',
    ),
  ];

  const input = RetirementInput(
    pensionSavings: 0,
    irpBalance: 0,
    isaBalance: 0,
    currentAge: 66,
    monthlyPensionWithdrawal: 0,
    monthlyOtherWithdrawal: 0,
    healthInsType: HealthInsType.dependent,
    publicPensionMonthly: 900000,
  );

  await prefs.setString(
    'holdings',
    jsonEncode(holdings.map((h) => h.toJson()).toList()),
  );
  await prefs.setString('retirement_input', jsonEncode(input.toJson()));
  await prefs.setString(
    'default_account_overrides',
    jsonEncode({
      'default_isa': {
        'balance': 30000000,
        'monthly_withdrawal': 0,
        'is_withdrawing': false,
      },
      'default_pension_savings': {
        'balance': 200000000,
        'monthly_withdrawal': 800000,
        'is_withdrawing': true,
      },
      'default_irp': {
        'balance': 100000000,
        'monthly_withdrawal': 400000,
        'is_withdrawing': true,
      },
    }),
  );
  await prefs.setString(
    'interest_items',
    jsonEncode([
      const InterestItem(
        id: 'demo_deposit',
        name: '정기예금',
        annualAmount: 2400000,
      ).toJson(),
    ]),
  );
  await prefs.setString('accounts', jsonEncode(const []));
  await prefs.setInt('schema_version', 4);
  await prefs.setBool(kQuickStartDoneKey, true);
  await prefs.setBool(_kDemoSeededKey, true);
}
