#!/bin/bash
# 릴리스 AAB 빌드 — 운영 광고 ID 주입을 강제한다.
# v1.4.1·v1.4.7 이 --dart-define 누락으로 테스트 광고 ID 를 싣고 출시된 사고(수익 0) 재발 방지.
# release_ads.local(미추적)에 RETIRE_BANNER_AD_UNIT_ID / RETIRE_INTERSTITIAL_AD_UNIT_ID 를 둔다.
set -euo pipefail
cd "$(dirname "$0")"

[ -f release_ads.local ] || { echo "release_ads.local 없음 — 운영 광고 ID 필요" >&2; exit 1; }
set -a; source release_ads.local; set +a
for v in RETIRE_BANNER_AD_UNIT_ID RETIRE_INTERSTITIAL_AD_UNIT_ID; do
  case "${!v:-}" in
    ca-app-pub-3940256099942544/*|"") echo "$v 가 비었거나 테스트 ID" >&2; exit 1 ;;
  esac
done

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

flutter build appbundle --release \
  --dart-define=RETIRE_BANNER_AD_UNIT_ID="$RETIRE_BANNER_AD_UNIT_ID" \
  --dart-define=RETIRE_INTERSTITIAL_AD_UNIT_ID="$RETIRE_INTERSTITIAL_AD_UNIT_ID"

# 빌드 산출물 안에 운영 ID 가 실제로 박혔는지 검사 (명령 누락·캐시 오염 방어).
AAB=build/app/outputs/bundle/release/app-release.aab
ids=$(unzip -p "$AAB" base/lib/arm64-v8a/libapp.so | strings | grep -oE "ca-app-pub-[0-9]+/[0-9]+" | sort -u)
echo "$ids"
for v in "$RETIRE_BANNER_AD_UNIT_ID" "$RETIRE_INTERSTITIAL_AD_UNIT_ID"; do
  grep -qx "$v" <<<"$ids" || { echo "AAB 에 운영 광고 ID 없음: $v" >&2; exit 1; }
done
echo "OK: $AAB"
