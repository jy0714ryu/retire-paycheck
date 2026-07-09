// 세금·건보 임계치 상수 + 나이별 연금소득세율.
//
// 금액은 전부 int 원 단위. 세율 적용 결과는 호출부에서 `.round()` 처리한다.

/// 금융소득종합과세 기준 — 연간 금융소득(이자+배당) 20,000,000원 초과 시 종합과세 대상.
const int kFinancialIncomeThreshold = 20000000;

/// 건강보험 피부양자 자격 상실 소득 기준 (참고용 — 실제 판정은 건보공단 별도 심사).
/// 기준일: 2022-09 건강보험료 부과체계 2단계 개편 이후 기준.
const int kHealthInsuranceIncomeThreshold = 20000000;

/// 사적연금(연금저축·IRP) 저율 분리과세 한도 — 연간 인출액 15,000,000원 이하까지 저율(3.3~5.5%) 적용.
const int kPensionLowRateLimit = 15000000;

/// 건강보험 지역가입자 금융소득 산입 기준 — 연 10,000,000원 초과 시 금융소득 전액을 건보료 산정에 산입.
/// (2022-09 개편 기준. 10,000,000원 이하는 건보료 산정에서 0원 산입.)
const int kHealthInsFinancialFloor = 10000000;

/// 배당소득세(원천징수) 15.4% (지방소득세 포함).
const double kDividendWithholding = 0.154;

/// 나이별 연금소득세율 (사적연금 저율 분리과세, 연금나침반 이식).
/// 80세 이상 3.3% / 70세 이상 4.4% / 그 외(70세 미만) 5.5%.
double pensionTaxRate(int age) {
  if (age >= 80) return 0.033;
  if (age >= 70) return 0.044;
  return 0.055;
}
