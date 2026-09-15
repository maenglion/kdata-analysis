# K-DATA 검증 기록

이 디렉터리는 Git의 기대상태와 실제 실행환경을 대조한 결과를 기록한다. 원본 사건자료, 개인정보, 인증정보와 비밀키는 기록하지 않는다.

| 검증일 | 기록 | 결과 |
|---|---|---|
| 2026-09-12 | [Supabase 원격 스키마 읽기 전용 검증](./2026-09-12-supabase-read-only-schema-verification.md) | `MATCH_WITH_UNVERIFIED_TEST_HISTORY` |
| 2026-09-15 | [Supabase 컬럼·적재 현황 및 DeepSeek 교차검증 입력](./2026-09-15-supabase-column-inventory-for-cross-check.md) | `DRIFT` — 원격 전용 빈 테이블 4개 |
