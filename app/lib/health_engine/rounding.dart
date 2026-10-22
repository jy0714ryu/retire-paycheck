// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 건보료나침반 — 원(KRW) 단위 절사 헬퍼.
///
/// 건강보험료는 원 단위 미만 절사(truncate)한다. 부동소수 표현 오차로
/// 수학적 정수값이 `x.9999...` 로 계산돼 floor 가 1원 깎이는 문제를 막기 위해
/// 작은 epsilon 을 더한 뒤 floor 한다. epsilon(1e-4 원)은 유효 금액(최소 0.5원
/// 단위 소수)보다 훨씬 작아 정당한 절사에는 영향을 주지 않는다.
library;

const double _epsilon = 1e-4;

/// 원 단위 미만 절사(부동소수 오차 보정 포함).
int wonFloor(num value) => (value + _epsilon).floor();
