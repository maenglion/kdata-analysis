# 2026-09-15 K-DATA Supabase 컬럼·적재 현황

## 1. 검증 목적

DeepSeek 등 별도 분석 경로가 K-DATA Supabase의 현재 구조를 교차검증할 수 있도록 원격 PostgreSQL의 실제 컬럼과 적재 행 수를 읽기 전용으로 조회했다.

- Supabase project ref: `bdmyfchrjfuvsenpjtcc`
- project URL: `https://bdmyfchrjfuvsenpjtcc.supabase.co`
- 조회 대상 schema: `ledger`, `audit`, `private`
- 조회 방법: `information_schema.columns`, PostgreSQL constraint catalog 및 각 테이블의 `count(*)`
- 변경 작업: 없음. schema·table·row·policy를 생성·수정·삭제하지 않음

## 2. 요약

| 구분 | 현재 원격 상태 |
|---|---:|
| 실제 테이블 | 22개 |
| View | 2개 |
| 고유 컬럼 | 259개 |
| 적재된 방법론 | 1행 |
| 평가축 | 2행 |
| 평가기준 | 13행 |
| 게이트 | 9행 |
| Claim·Evidence·Evaluation run/result | 0행 |
| 수집 배치·문장 단위·조직도 정규화 | 0행 |
| 감사·내보내기 이력 | 0행 |

최초 FK 조인 결과는 260행이었다. `evaluation_gate_results.gate_id`가 단일 FK와 `(gate_id, gate_code)` 복합 FK에 모두 참여해 조인 결과에 두 번 나타난 것이다. `information_schema.columns` 기준 실제 고유 컬럼 수는 259개다.

## 3. 현재 실제 적재 상태

현재는 **루브릭의 정의 데이터만 적재**되어 있다.

| 객체 | 컬럼 수 | 행 수 | 의미 |
|---|---:|---:|---|
| `ledger.methodologies` | 9 | 1 | `KDATA_CLAIM_EVAL / 1.0.0` |
| `ledger.evaluation_dimensions` | 6 | 2 | 사실지지·판정가능도 |
| `ledger.evaluation_criteria` | 9 | 13 | 사실지지 7개·판정가능도 6개 |
| `ledger.methodology_gates` | 11 | 9 | G-01~G-09 |

그 밖의 테이블과 두 View의 현재 행 수는 0이다. 따라서 화면에 보이는 F/I/U 판정, 증거목록, 웹 스냅샷과 SLDA 85개 문장은 아직 DB evaluation run으로 적재되지 않았다.

## 4. 컬럼 전체 목록

표기 형식은 `schema.table — 컬럼 수 — 컬럼명`이다. View는 별도로 표시한다.

### 4.1 `audit` — 감사·내보내기 이력

#### `audit.evaluation_events` — 10개 — 0행

`id`, `claim_id`, `run_id`, `prior_run_id`, `event_type`, `before_state`, `after_state`, `change_reason`, `actor_id`, `occurred_at`

판정 생성·변경 이벤트와 변경 전후 상태, 변경 이유, 행위자를 보존한다.

#### `audit.export_events` — 7개 — 0행

`id`, `export_type`, `filter_snapshot`, `row_count`, `sha256`, `requested_by`, `created_at`

CSV 등 내보내기의 필터·행 수·해시·요청자를 기록한다.

### 4.2 `ledger` — Claim·Evidence·루브릭·평가 실행

#### `ledger.claims` — 12개 — 0행

`id`, `claim_type`, `title`, `claim_text`, `legacy_status`, `current_status_code`, `current_status_reason_short`, `current_evaluation_run_id`, `current_status_materialized_at`, `is_public`, `created_at`, `retired_at`

#### `ledger.evidence` — 12개 — 0행

`id`, `title`, `source_grade`, `authenticity`, `independence`, `source_locator`, `sha256`, `public_hash_prefix`, `source_limitation`, `is_public`, `collected_at`, `created_at`

#### `ledger.evidence_requests` — 8개 — 0행

`id`, `title`, `request_text`, `request_status`, `narrows_claim_ids`, `expected_uncertainty_reduction`, `created_at`, `updated_at`

#### `ledger.methodologies` — 9개 — 1행

`id`, `code`, `version`, `name`, `description`, `effective_from`, `retired_at`, `formula_definition`, `created_at`

#### `ledger.evaluation_dimensions` — 6개 — 2행

`id`, `methodology_id`, `code`, `name`, `weight_total`, `display_order`

#### `ledger.evaluation_criteria` — 9개 — 13행

`id`, `dimension_id`, `code`, `name`, `definition`, `weight`, `score_min`, `score_max`, `display_order`

#### `ledger.methodology_gates` — 11개 — 9행

`id`, `methodology_id`, `code`, `name`, `definition`, `effect`, `score_cap`, `status_cap`, `is_core`, `gate_priority`, `display_order`

#### `ledger.evaluation_runs` — 12개 — 0행

`id`, `claim_id`, `methodology_id`, `prior_run_id`, `calculation_type`, `engine_name`, `engine_version`, `evaluated_at`, `evaluated_by`, `human_review_status`, `input_snapshot`, `notes`

#### `ledger.evaluation_factor_scores` — 8개 — 0행

`id`, `run_id`, `criterion_id`, `input_score`, `applied_weight`, `weighted_score`, `basis`, `source_values`

#### `ledger.evaluation_gate_results` — 14개 — 0행

`id`, `run_id`, `gate_id`, `gate_code`, `gate_name`, `input_value`, `required_value`, `result`, `effect`, `score_cap`, `status_cap`, `gate_priority`, `reason_code`, `reason_text`

#### `ledger.evaluation_results` — 29개 — 0행

`id`, `run_id`, `fact_support_raw_score`, `fact_support_final_score`, `fact_support_level`, `readiness_raw_score`, `readiness_final_score`, `readiness_level`, `probability_low`, `probability_high`, `probability_semantics`, `probability_basis`, `status_code`, `status_label`, `status_reason_code`, `status_reason_short`, `decisive_gate_code`, `passed_gate_codes`, `failed_gate_codes`, `highest_evidence_grade`, `evidence_count`, `direct_evidence_count`, `independent_source_count`, `contradicting_evidence_count`, `missing_evidence_codes`, `conditional_assumptions`, `formula_snapshot`, `decision_trace`, `created_at`

#### `ledger.evaluation_evidence_links` — 11개 — 0행

`run_id`, `evidence_id`, `use_role`, `evidence_grade`, `directness`, `temporality`, `coverage`, `is_decisive`, `contribution_note`, `limitation`, `counterinterpretation`

#### `ledger.evaluation_missing_evidence_links` — 3개 — 0행

`run_id`, `evidence_request_id`, `reason`

#### `ledger.evaluation_assumptions` — 6개 — 0행

`id`, `run_id`, `assumption_code`, `assumption_text`, `assumption_status`, `impact_note`

#### `ledger.web_snapshots` — 8개 — 0행

`id`, `url`, `captured_at`, `sha256`, `public_hash_prefix`, `display_summary`, `is_public`, `created_at`

### 4.3 원격에만 확인된 수집·정규화 테이블

다음 4개 테이블은 원격 DB에 존재하지만 현재 Git `main`의 두 migration 파일에는 정의돼 있지 않다. 모두 0행이다.

#### `ledger.ingest_batches` — 11개 — 0행

`id`, `parser_name`, `parser_version`, `source_filename`, `source_sha256`, `source_row_count`, `source_scope`, `content_contract`, `source_evidence_id`, `notes`, `ingested_at`

#### `ledger.parsed_claim_units` — 16개 — 0행

`id`, `ingest_batch_id`, `source_evidence_id`, `legacy_unit_id`, `source_row_number`, `document_code`, `document_date`, `recipient`, `section_locator`, `author_name`, `channel`, `frame_codes`, `expression_strength`, `signal_codes`, `source_text`, `created_at`

#### `ledger.organization_snapshots` — 10개 — 0행

`id`, `ingest_batch_id`, `observed_on`, `source_url`, `archive_url`, `source_container_evidence_id`, `source_hash_scope`, `normalized_rows_sha256`, `source_limitation`, `created_at`

#### `ledger.organization_assignments` — 9개 — 0행

`id`, `snapshot_id`, `person_name`, `department_name`, `role_title`, `duties`, `source_locator`, `normalized_row_sha256`, `created_at`

### 4.4 `ledger` View

#### `ledger.evaluation_result_timeline` — View 12개 — 0행

`claim_id`, `evaluation_run_id`, `evaluation_result_id`, `status_code`, `status_label`, `status_reason_code`, `status_reason_short`, `valid_from`, `valid_to`, `methodology_id`, `engine_version`, `human_review_status`

#### `ledger.current_evaluation_export_rows` — View 20개 — 0행

`claim_id`, `claim_text`, `status_code`, `status_label`, `status_reason_code`, `status_reason_short`, `fact_support_final_score`, `readiness_final_score`, `failed_gate_codes`, `passed_gate_codes`, `missing_evidence_codes`, `conditional_assumptions`, `highest_evidence_grade`, `evidence_count`, `contradicting_evidence_count`, `calculation_type`, `methodology_version`, `engine_version`, `evaluated_at`, `human_review_status`

### 4.5 `private` — 원본 보관 위치

#### `private.evidence_locations` — 6개 — 0행

`evidence_id`, `storage_provider`, `storage_locator`, `contains_personal_data`, `retention_note`, `created_at`

이 테이블은 공개 화면과 분리해야 하며 원본 파일 위치와 개인정보 포함 여부를 보존한다.

## 5. 핵심 FK 연결

| 출발 컬럼 | 대상 |
|---|---|
| `claims.current_evaluation_run_id` | `evaluation_runs.id` |
| `evaluation_runs.claim_id` | `claims.id` |
| `evaluation_runs.methodology_id` | `methodologies.id` |
| `evaluation_runs.prior_run_id` | 이전 `evaluation_runs.id` |
| `evaluation_factor_scores.run_id` | `evaluation_runs.id` |
| `evaluation_factor_scores.criterion_id` | `evaluation_criteria.id` |
| `evaluation_gate_results.run_id` | `evaluation_runs.id` |
| `evaluation_gate_results.gate_id/gate_code` | `methodology_gates.id/code` |
| `evaluation_results.run_id` | `evaluation_runs.id` |
| `evaluation_evidence_links` | `evaluation_runs` ↔ `evidence` |
| `evaluation_missing_evidence_links` | `evaluation_runs` ↔ `evidence_requests` |
| `private.evidence_locations.evidence_id` | `evidence.id` |
| `parsed_claim_units.ingest_batch_id` | `ingest_batches.id` |
| `organization_assignments.snapshot_id` | `organization_snapshots.id` |
| `evaluated_by`, `actor_id`, `requested_by` | `auth.users.id` |

## 6. DeepSeek 교차검증 질문

다음 질문으로 교차검증하는 것이 적절하다.

1. 259개 컬럼이 `원자료 → 증거 → 루브릭 입력 → 게이트 → 결과 → 이력 → CSV` 설명 체인을 완전하게 지원하는가?
2. 점수 필드와 상태 필드가 분리돼 있으며 점수가 상태를 직접 결정하는 숨은 threshold가 없는가?
3. `status_reason_code`, `decisive_gate_code`, `failed_gate_codes`, `missing_evidence_codes`, `formula_snapshot`, `decision_trace`로 각 판정을 제3자가 설명할 수 있는가?
4. `prior_run_id`와 timeline View가 기존 판정을 덮어쓰지 않는 append-only 이력을 충분히 보장하는가?
5. 원격에만 존재하는 수집 테이블 4개를 Git migration으로 정식 편입하기 전에 컬럼명·민감정보 범위·RLS가 적절한가?
6. `parsed_claim_units.source_text`, `recipient`, `author_name`, `organization_assignments.person_name`을 공개 API와 분리하기 위한 정책이 충분한가?
7. 루브릭 정의만 적재되고 실제 claim/evidence/run이 0행인 현재 단계에서 화면 상수를 DB 기반으로 교체하는 것은 아직 이른가?

## 7. 판정

`DRIFT`

기존 루브릭·평가 엔진 테이블과 View는 유지되고 있으나, Git migration에 없는 수집·조직도 정규화 테이블 4개가 원격에 추가되어 있다. 이 4개는 비어 있으므로 운영 데이터 손상은 없지만, 원격 DB를 현재 Git만으로 재현할 수 없는 상태다.

다음 행동은 다음 순서가 적절하다.

1. 원격 전용 4개 테이블의 생성 SQL 출처 확인
2. 컬럼·제약·RLS 검산 후 별도 migration으로 Git 편입하거나, 불필요하면 사용자 승인 후 별도 정리 계획 수립
3. RLS·공개 View 경계 확정
4. 2026-09-15 자료를 evidence·ingest batch·parsed claim units로 적재
5. 루브릭 기반 evaluation run 생성·검산
6. 승인된 최신 run으로 화면 상수 교체

이번 검증에서는 DB를 변경하지 않았다.
