# pension-compass에서 이식 (2026-07-09)
# Room이 생성한 *_Impl 클래스는 리플렉션으로 기본 생성자를 호출해 인스턴스화된다.
# R8이 이 생성자를 제거하면 기동 즉시 NoSuchMethodException(WorkDatabase_Impl.<init>)
# 크래시 발생 (2026-07-09 갤럭시 S25 실기기 진단 — play-services-ads 25.x WorkManager 초기화 경로).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
