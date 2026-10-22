// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 제도 파라미터 모델 (SSOT 로더).
///
/// 순수 Dart — Flutter 의존 없음. `params_2026.json` 등 연도별 파라미터 테이블을
/// 파싱해 계산 엔진에 주입한다. 파일/네트워크 접근은 [ParamsSource] 인터페이스로
/// 분리했다 (rootBundle 등 플랫폼 의존은 앱 레이어에서 구현·주입).
library;

import 'dart:convert';
import 'dart:io';

/// 파라미터 원본(raw JSON 문자열)을 공급하는 인터페이스.
///
/// 앱에서는 `rootBundle` 기반 구현을, 테스트/CLI에서는 [FileParamsSource]를 주입한다.
abstract class ParamsSource {
  Future<String> loadRaw(int year);
}

/// dart:io 파일 시스템 기반 [ParamsSource] (테스트·CLI 전용).
///
/// [directory] 아래에서 `params_<year>.json` 을 읽는다.
class FileParamsSource implements ParamsSource {
  const FileParamsSource({this.directory = 'assets/health_params'});

  final String directory;

  @override
  Future<String> loadRaw(int year) {
    final path = '$directory/params_$year.json';
    return File(path).readAsString();
  }
}

/// 소득 5종의 반영률(지역 소득보험료 산정 시).
class IncomeReflect {
  const IncomeReflect({
    required this.pension,
    required this.labor,
    required this.business,
    required this.financial,
    required this.other,
  });

  final double pension;
  final double labor;
  final double business;
  final double financial;
  final double other;

  factory IncomeReflect.fromMap(Map<String, dynamic> m) => IncomeReflect(
        pension: (m['pension'] as num).toDouble(),
        labor: (m['labor'] as num).toDouble(),
        business: (m['business'] as num).toDouble(),
        financial: (m['financial'] as num).toDouble(),
        other: (m['other'] as num).toDouble(),
      );
}

/// 피부양자 판정 임계값 묶음.
class DependentParams {
  const DependentParams({
    required this.incomeLimit,
    required this.propertyLimitLow,
    required this.propertyLimitHigh,
    required this.midIncomeLimit,
    required this.bizRegisteredLimit,
    required this.bizUnregisteredLimit,
  });

  /// 소득 요건 한도(재산 저구간): 연 2,000만원.
  final int incomeLimit;

  /// 재산 저구간 상한: 5.4억. 이하면 소득 [incomeLimit] 적용.
  final int propertyLimitLow;

  /// 재산 고구간 상한: 9억. 초과 시 무조건 탈락.
  final int propertyLimitHigh;

  /// 재산 중구간(저~고) 소득 한도: 연 1,000만원.
  final int midIncomeLimit;

  /// 사업자 등록자 사업소득 한도: 0원(초과 시 탈락).
  final int bizRegisteredLimit;

  /// 사업자 미등록자 사업소득 한도: 500만원.
  final int bizUnregisteredLimit;

  factory DependentParams.fromMap(Map<String, dynamic> m) => DependentParams(
        incomeLimit: (m['income_limit'] as num).toInt(),
        propertyLimitLow: (m['property_limit_low'] as num).toInt(),
        propertyLimitHigh: (m['property_limit_high'] as num).toInt(),
        midIncomeLimit: (m['mid_income_limit'] as num).toInt(),
        bizRegisteredLimit: (m['biz_registered_limit'] as num).toInt(),
        bizUnregisteredLimit: (m['biz_unregistered_limit'] as num).toInt(),
      );
}

/// 1세대 1주택 특례 공정시장가액비율 구간.
class SingleHomeRatioBand {
  const SingleHomeRatioBand({required this.officialMax, required this.ratio});

  /// 공시가격 구간 상한(이하). null 이면 상한 없음(최고 구간).
  final int? officialMax;
  final double ratio;

  factory SingleHomeRatioBand.fromMap(Map<String, dynamic> m) =>
      SingleHomeRatioBand(
        officialMax: m['official_max'] == null
            ? null
            : (m['official_max'] as num).toInt(),
        ratio: (m['ratio'] as num).toDouble(),
      );
}

/// 간편(추정) 재산과표 모드 계수.
class SimpleModeParams {
  const SimpleModeParams({
    required this.marketToOfficialRatio,
    required this.fairMarketRatio,
    required this.singleHomeBands,
  });

  /// 시세 → 공시가격 현실화율(공동주택 69%).
  final double marketToOfficialRatio;

  /// 일반주택 재산세 공정시장가액비율(60%).
  final double fairMarketRatio;

  /// 1세대 1주택 특례 구간(공시가격 오름차순).
  final List<SingleHomeRatioBand> singleHomeBands;

  factory SimpleModeParams.fromMap(Map<String, dynamic> m) => SimpleModeParams(
        marketToOfficialRatio:
            (m['market_to_official_ratio'] as num).toDouble(),
        fairMarketRatio: (m['fair_market_ratio'] as num).toDouble(),
        singleHomeBands: (m['fair_market_ratio_single_home'] as List)
            .map((e) => SingleHomeRatioBand.fromMap(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

/// 재산보험료부과점수 등급표의 한 등급.
class PropertyGrade {
  const PropertyGrade({
    required this.grade,
    required this.min,
    required this.max,
    required this.points,
  });

  final int grade;

  /// 재산금액(공제 후) 구간 하한 — **초과(exclusive)**.
  final int min;

  /// 구간 상한 — **이하(inclusive)**. null 이면 상한 없음(최고 등급).
  final int? max;

  /// 부과점수.
  final int points;

  factory PropertyGrade.fromMap(Map<String, dynamic> m) => PropertyGrade(
        grade: (m['grade'] as num).toInt(),
        min: (m['min'] as num).toInt(),
        max: m['max'] == null ? null : (m['max'] as num).toInt(),
        points: (m['points'] as num).toInt(),
      );
}

/// 연도별 건강보험 제도 파라미터 (계산 엔진 SSOT).
class HealthParams {
  const HealthParams({
    required this.year,
    required this.version,
    required this.employeeRate,
    required this.ltcRateOfIncome,
    required this.ltcRateOfHealth,
    required this.regionalIncomeRate,
    required this.propertyDeduction,
    required this.propertyPointPrice,
    required this.minPremium,
    required this.maxPremium,
    required this.incomeReflect,
    required this.dependent,
    required this.simpleMode,
    required this.propertyGradeTable,
  });

  final int year;
  final String version;

  /// 직장 보험료율(7.19%).
  final double employeeRate;

  /// 장기요양보험료율 — 소득 대비 환산치(참고용).
  final double ltcRateOfIncome;

  /// 장기요양보험료율 — 건강보험료 대비(13.14%). 엔진 LTC 산정에 사용.
  final double ltcRateOfHealth;

  /// 지역가입자 소득 정률(7.19%).
  final double regionalIncomeRate;

  /// 재산공제(1억).
  final int propertyDeduction;

  /// 재산 부과점수당 금액(211.5원).
  final double propertyPointPrice;

  /// 월 보험료 하한(건강보험 부분).
  final int minPremium;

  /// 월 보험료 상한(건강보험 부분).
  final int maxPremium;

  final IncomeReflect incomeReflect;
  final DependentParams dependent;
  final SimpleModeParams simpleMode;

  /// 재산 60등급표(오름차순).
  final List<PropertyGrade> propertyGradeTable;

  factory HealthParams.fromMap(Map<String, dynamic> m) => HealthParams(
        year: (m['year'] as num).toInt(),
        version: m['version'] as String,
        employeeRate: (m['employee_rate'] as num).toDouble(),
        ltcRateOfIncome: (m['ltc_rate_of_income'] as num).toDouble(),
        ltcRateOfHealth: (m['ltc_rate_of_health'] as num).toDouble(),
        regionalIncomeRate: (m['regional_income_rate'] as num).toDouble(),
        propertyDeduction: (m['property_deduction'] as num).toInt(),
        propertyPointPrice: (m['property_point_price'] as num).toDouble(),
        minPremium: (m['min_premium'] as num).toInt(),
        maxPremium: (m['max_premium'] as num).toInt(),
        incomeReflect:
            IncomeReflect.fromMap(m['income_reflect'] as Map<String, dynamic>),
        dependent:
            DependentParams.fromMap(m['dependent'] as Map<String, dynamic>),
        simpleMode:
            SimpleModeParams.fromMap(m['simple_mode'] as Map<String, dynamic>),
        propertyGradeTable: (m['property_grade_table'] as List)
            .map((e) => PropertyGrade.fromMap(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  factory HealthParams.fromJsonString(String raw) =>
      HealthParams.fromMap(json.decode(raw) as Map<String, dynamic>);

  /// [ParamsSource]에서 raw JSON 을 읽어 파싱한다.
  static Future<HealthParams> load(ParamsSource source, int year) async =>
      HealthParams.fromJsonString(await source.loadRaw(year));

  /// 재산금액(공제 후, 원)에 해당하는 등급을 찾는다.
  ///
  /// 금액이 0 이하이면 null(부과점수 0). 하한 초과 · 상한 이하 규칙.
  PropertyGrade? gradeForAmount(int amount) {
    if (amount <= 0) return null;
    for (final g in propertyGradeTable) {
      final max = g.max;
      if (amount > g.min && (max == null || amount <= max)) {
        return g;
      }
    }
    return null;
  }
}
