// 건보료나침반(gunbocompass)에서 이식 — 2026-10-22 v2.2 통합. 건보 계산 규칙 SSOT 는 이 폴더.
/// 3-way 비교 선택지.
library;

/// 은퇴 전환 선택지.
enum ComparisonOption {
  /// 임의계속가입.
  voluntary,

  /// 지역가입.
  regional,

  /// 피부양자 편입.
  dependent,
}
