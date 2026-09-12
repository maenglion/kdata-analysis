# 검증기록 — Supabase 원격 스키마 읽기 전용 대조

- 검증일시: 2026-09-12 20:47:14 +09:00
- 대상 저장소: `maenglion/kdata-analysis`
- 대상 브랜치: `main`
- 기준 Git commit: `32ec08c8f6e4e9ff63a2b423bb7f22a3b6283009`
- 기준 관계: DB 구현 commit `d47089b` 및 그 이후 `main` 변경 포함
- Supabase project ref: `bdmyfchrjfuvsenpjtcc`
- Project URL: `https://bdmyfchrjfuvsenpjtcc.supabase.co`
- 연결 database 이름: `postgres`
- 최종 판정: **`MATCH_WITH_UNVERIFIED_TEST_HISTORY`**

## 1. 검증 범위와 방법

Git 마이그레이션에서 기대 객체·방법론 데이터·함수 규칙·트리거 연결을 추출하고, Supabase SQL Editor에서 `SELECT`, `information_schema`, `pg_catalog` 조회만 실행해 원격 PostgreSQL과 대조했다.

실행하지 않은 작업:

- 마이그레이션 및 계약 테스트 재실행
- schema, table, function, view, trigger, policy 생성·변경·삭제
- 시험행 또는 운영데이터 삽입·수정·삭제
- `claims.current_status_*` 변경
- 프로젝트 설정 변경
- secret 조회·출력·기록

**이 검증에서는 DB를 변경하지 않았다.** SQL Editor 안전검사가 함수 본문 확인용 문자열을 변경문으로 오인한 한 차례의 경고는 실행하지 않고 취소했으며, 문자열을 분리한 순수 SELECT로 다시 검증했다.

## 2. 기준 파일

| 파일 | SHA-256 |
|---|---|
| `supabase/migrations/202609120001_kdata_evidence_ledger.sql` | `de97305d3e88b3381460479426f9c77c39074bdd5fc355e0da1bfe353e2a7bbb` |
| `supabase/migrations/202609120002_kdata_methodology_v1.sql` | `ef0e81310e20a09806e177ed0aa35168132202e78ac4f7e3e7f216cba2f1e95e` |
| `supabase/tests/evaluation_contract.sql` | `7d406f7fefd6f688610f1d520f5223a99225d20bc8c4a973a38219b0cb0e7669` |
| `supabase/README.md` | `e7f6d3739d400d7888bdb11ce685388820d50fe9f24fb3e2c662c080aef56ef7` |

## 3. 프로젝트 식별

| 항목 | 기대 | 실제 | 판정 |
|---|---|---|---|
| Dashboard project ref | `bdmyfchrjfuvsenpjtcc` | `bdmyfchrjfuvsenpjtcc` | MATCH |
| Project URL | 위 project ref의 Supabase URL | 일치 | MATCH |
| Database | K-DATA 프로젝트의 기본 PostgreSQL DB | `postgres` | MATCH |
| 프로젝트 표시명 | K-DATA 전용 | `kdata-analysis` | MATCH |

신용보증기금용 다른 프로젝트가 아니라 별도 K-DATA 프로젝트 경로에서 검증했다.

## 4. Schema 및 table 대조

| Schema | EXPECTED | PRESENT | MISSING | EXTRA | 판정 |
|---|---|---|---|---|---|
| `ledger` | 15개 | 15개 | 없음 | 없음 | MATCH |
| `audit` | 2개 | 2개 | 없음 | 없음 | MATCH |
| `private` | 1개 | 1개 | 없음 | 없음 | MATCH |

### ledger — EXPECTED/PRESENT

`claims`, `evidence`, `evidence_requests`, `evaluation_assumptions`, `evaluation_criteria`, `evaluation_dimensions`, `evaluation_evidence_links`, `evaluation_factor_scores`, `evaluation_gate_results`, `evaluation_missing_evidence_links`, `evaluation_results`, `evaluation_runs`, `methodologies`, `methodology_gates`, `web_snapshots`

### audit — EXPECTED/PRESENT

`evaluation_events`, `export_events`

### private — EXPECTED/PRESENT

`evidence_locations`

## 5. 핵심 판정 엔진

요구된 핵심 함수 7개와 보조 검증·불변성 함수 4개가 모두 존재했다.

| 함수 | 존재 | 의도 검산 |
|---|---:|---|
| `ledger.status_rank(text)` | 예 | 상태 상한 순위 정의 존재 |
| `ledger.decisive_gate_for_run(uuid)` | 예 | BLOCK 우선, CAP 최저상한, 동률 `gate_priority` 확인 |
| `ledger.derive_status_for_run(uuid)` | 예 | 게이트·전제·반증·증거조건 기반 상태 산출 확인 |
| `ledger.validate_evaluation_result()` | 예 | 결정 게이트와 상태 산출 함수를 호출하고 입력 결과 불일치 거부 |
| `ledger.materialize_current_claim_status()` | 예 | 최신 평가결과를 `claims` 표시 캐시에 반영 |
| `ledger.protect_materialized_claim_status()` | 예 | 표시 캐시 직접수정 거부 |
| `audit.record_evaluation_result_event()` | 예 | 평가결과 생성 후 audit event 기록 |

추가 존재 확인:

`ledger.validate_factor_score()`, `ledger.validate_gate_result_input()`, `audit.reject_mutation()`, `audit.reject_finalized_run_mutation()`

### 상태 산출 규칙

| 규칙 | 원격 정의 확인 | 판정 |
|---|---:|---|
| BLOCK이 CAP보다 우선 | 예 | MATCH |
| BLOCK FAIL → `insufficient` | 예 | MATCH |
| 복수 CAP → 가장 낮은 허용상태 | 예 | MATCH |
| 동일 상한 → `gate_priority`, 이후 `gate_code` | 예 | MATCH |
| `unscored` → `unassessed` | 예 | MATCH |
| decisive contradiction → `contradicted` | 예 | MATCH |
| 상태 함수 안에 점수 임계값 없음 | 예 | MATCH |
| `decisive_gate_code`를 전용 우선순위 함수로 계산 | 예 | MATCH |

함수 존재 11/11과 위 의미 규칙이 모두 일치했다. 함수 본문을 단순 첫 행이나 점수구간으로 판정하는 드리프트는 발견되지 않았다.

## 6. 방법론 v1 데이터

| 항목 | 기대 | 실제 | 판정 |
|---|---:|---:|---|
| `KDATA_CLAIM_EVAL / 1.0.0` | 1 | 1 | MATCH |
| evaluation dimensions | 2 | 2 | MATCH |
| 사실지지 기준 | 7 | 7 | MATCH |
| 판정가능도 기준 | 6 | 6 | MATCH |
| 전체 criteria | 13 | 13 | MATCH |
| gates | 9 | 9 | MATCH |

### Gate 정의

| Gate | effect | score_cap | status_cap | gate_priority | 판정 |
|---|---|---:|---|---:|---|
| G-01 | BLOCK | 39 | insufficient | 10 | MATCH |
| G-02 | BLOCK | 59 | insufficient | 20 | MATCH |
| G-03 | BLOCK | 59 | insufficient | 30 | MATCH |
| G-04 | BLOCK | 49 | insufficient | 40 | MATCH |
| G-05 | BLOCK | 39 | insufficient | 50 | MATCH |
| G-06 | BLOCK | 59 | insufficient | 60 | MATCH |
| G-07 | BLOCK | 59 | insufficient | 70 | MATCH |
| G-08 | CAP | null | supported | 80 | MATCH |
| G-09 | CAP | null | conditional | 90 | MATCH |

## 7. View 계약

| View | 존재 | 컬럼 계약 | 판정 |
|---|---:|---:|---|
| `ledger.evaluation_result_timeline` | 예 | 12/12 일치 | MATCH |
| `ledger.current_evaluation_export_rows` | 예 | 20/20 일치 | MATCH |

CSV View에서 확인한 컬럼:

`claim_id`, `claim_text`, `status_code`, `status_label`, `status_reason_code`, `status_reason_short`, `fact_support_final_score`, `readiness_final_score`, `failed_gate_codes`, `passed_gate_codes`, `missing_evidence_codes`, `conditional_assumptions`, `highest_evidence_grade`, `evidence_count`, `contradicting_evidence_count`, `calculation_type`, `methodology_version`, `engine_version`, `evaluated_at`, `human_review_status`

## 8. Trigger 및 불변성

원격 trigger는 21개이며 모두 활성 상태였다. 이름, 대상 table, 연결 function, 실행 시점과 event가 Git 정의와 일치했다.

| 목적 | 실제 trigger | 연결 function | 실행조건 | 판정 |
|---|---|---|---|---|
| 평가결과 자동검산 | `validate_evaluation_result_before_insert` | `ledger.validate_evaluation_result` | BEFORE INSERT | MATCH |
| 요소점수 검산 | `validate_factor_score_before_write` | `ledger.validate_factor_score` | BEFORE INSERT/UPDATE | MATCH |
| 게이트 입력 검산 | `validate_gate_result_before_write` | `ledger.validate_gate_result_input` | BEFORE INSERT/UPDATE | MATCH |
| 현재상태 직접수정 방지 | `protect_materialized_claim_status_before_update` | `ledger.protect_materialized_claim_status` | BEFORE UPDATE | MATCH |
| 현재상태 자동 materialize | `materialize_current_claim_status_after_insert` | `ledger.materialize_current_claim_status` | AFTER INSERT | MATCH |
| 평가이력 자동 생성 | `record_evaluation_result_event_after_insert` | `audit.record_evaluation_result_event` | AFTER INSERT | MATCH |

Append-only trigger 10개가 모두 BEFORE UPDATE/DELETE로 연결됨:

`evaluation_results_append_only`, `methodologies_append_only`, `evaluation_runs_append_only`, `evaluation_dimensions_append_only`, `evaluation_criteria_append_only`, `methodology_gates_append_only`, `evidence_append_only`, `web_snapshots_append_only`, `evaluation_events_append_only`, `export_events_append_only`

Finalized-run 불변성 trigger 5개가 모두 BEFORE INSERT/UPDATE/DELETE로 연결됨:

`finalized_factor_scores_immutable`, `finalized_gate_results_immutable`, `finalized_evidence_links_immutable`, `finalized_missing_evidence_links_immutable`, `finalized_assumptions_immutable`

함수 본문에서도 append-only 거부, finalized run 거부, 현재상태 직접수정 거부, 상태 materialize, 평가이력 생성 규칙을 확인했다.

## 9. RLS와 policy

| 항목 | 결과 | 판정 |
|---|---:|---|
| Migration의 RLS 대상 table | 18 | EXPECTED |
| 실제 RLS 활성 table | 18 | MATCH |
| RLS 미활성 대상 | 0 | MATCH |
| `ledger`/`audit`/`private` policy | 0 | 정책 미정의 |

`RLS enabled`와 `적절한 policy 존재`는 별개다. 현재는 18개 table 모두 RLS가 활성화됐지만 policy가 0개이므로, 프런트엔드 공개키를 통한 접근을 허용하기 전 역할·행위별 policy를 별도로 설계해야 한다.

## 10. 계약 테스트 잔존행과 이력

| 검색 대상 | 잔존 수 |
|---|---:|
| `TEST-` claim | 0 |
| `TEST-EV-` evidence | 0 |
| TEST claim 연결 evaluation run | 0 |
| TEST claim 연결 evaluation result | 0 |
| TEST claim 연결 audit event | 0 |

시험행이 남지 않은 상태는 rollback 계약과 일치한다. 그러나 잔존행 0건은 계약 테스트가 실제로 성공 실행됐음을 입증하지 않는다. 저장소와 원격 DB에서 독립적으로 확인 가능한 과거 성공 로그를 찾지 못했으므로 다음과 같이 구분한다.

```text
DB schema state consistent
historical contract-test execution not independently provable
```

## 11. Drift와 최종 판정

- 스키마·table: drift 없음
- 핵심 및 보조 function: drift 없음
- 판정 규칙: drift 없음
- 방법론 v1 및 gate 데이터: drift 없음
- View 컬럼 계약: drift 없음
- trigger·불변성: drift 없음
- RLS 활성화: drift 없음
- policy: Git migration과 같이 미정의 상태
- 시험행: 잔존 없음
- 과거 계약 테스트 실행 성공 로그: 독립 확인 불가

따라서 최종 판정은 다음과 같다.

> **MATCH_WITH_UNVERIFIED_TEST_HISTORY**

## 12. 다음 행동

1. 현재 두 마이그레이션은 재실행하지 않는다.
2. 계약 테스트 성공 로그가 필요하면 향후 별도 승인된 실행에서 결과 식별자와 실행시각을 보존하는 방식을 먼저 설계한다.
3. 프런트 연결 전에 역할별 RLS policy를 설계·검토한다.
4. 이후 별도 작업으로 화면 상수를 DB의 evaluation run 기반 조회로 교체한다.
5. 화면 전환 후 기존 정적 판정과 DB 파생 판정의 차이를 비교하고 변경 이력으로 남긴다.
