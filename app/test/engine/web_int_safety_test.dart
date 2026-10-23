import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 웹(JS) 빌드에서 `1 << 32` 는 0, `1 << 60` 은 2.68억이 된다(비트 연산 32비트).
// 상한값으로 쓰면 웹에서만 clamp 오류·금액 잘림이 생긴다 — kNoLimit 을 쓴다.
void main() {
  test('lib/ 에 32비트 넘는 비트 시프트 상한이 없다', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        final m = RegExp(r'1\s*<<\s*(\d+)').firstMatch(lines[i]);
        if (m != null && int.parse(m.group(1)!) >= 31) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
