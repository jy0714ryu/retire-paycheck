/// 엔진 테스트 공용 헬퍼 — 실제 params_2026.json 을 로드한다.
library;

import 'package:retire_paycheck/health_engine/engine.dart';

/// 테스트 전역에서 재사용하는 2026 파라미터(파일에서 1회 로드).
///
/// `flutter test` 는 패키지 루트를 cwd 로 실행하므로 상대 경로로 접근 가능.
Future<HealthParams> loadParams2026() async {
  const source = FileParamsSource();
  return HealthParams.load(source, 2026);
}
