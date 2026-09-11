# 회의록 — 판정 재현 DB 및 6단계 상태체계

- 일자: 2026-09-12
- 대상: K-DATA Evidence Ledger
- 상태: 설계 채택, 로컬 마이그레이션 작성 완료, 원격 DB 적용 전
- 공개 범위: 공개 저장소용 비식별 기록

## 1. 배경

기존 화면의 판정과 확률은 `app/page.tsx`의 상수로 관리되고 있었다. 문제의 핵심은 DB 부재 자체가 아니라, 화면의 판정값이 어떤 증거와 입력값에서 어떤 산식·게이트를 거쳐 생성되었는지 재현할 수 없다는 점이다.

K-DATA는 공식문서의 존재·공개·현행성을 분류하는 시스템이 아니라 개별 사실주장의 성립 여부와 인과 가능성을 분석한다. 따라서 신용보증기금 프로젝트의 등급체계나 데이터를 복사하지 않고, 공통 원칙인 입력 분리·AND 게이트·첫 실패조건 설명·버전 보존만 계승한다.

## 2. 채택한 결정

### DEC-KD-001 — K-DATA 전용 Supabase 분리

K-DATA는 신용보증기금과 별도의 Supabase 프로젝트·DB·환경변수·마이그레이션·백업·Storage를 사용한다. 저장소와 Netlify 사이트도 계속 분리한다.

이유:

- 권한 또는 마이그레이션 실수의 영향 범위를 분리한다.
- 사건자료와 판정 이력이 서로 섞이지 않게 한다.
- 프로젝트별 백업·삭제·보존정책을 독립적으로 운영한다.

### DEC-KD-002 — DB를 판정 재현 엔진의 기록계로 사용

DB는 화면 콘텐츠를 저장하는 데 그치지 않고 다음 전체 체인을 보존한다.

```text
원자료 → 증거등급 → 평가 입력값 → 버전된 산식
→ 게이트 검사 → 6단계 상태 → 사유코드
→ 화면·CSV용 현재값 → 변경이력
```

체인의 각 단계는 다음 단계를 재계산하거나 검증할 수 있어야 한다.

### DEC-KD-003 — 점수와 상태의 분리

`fact_support_score`와 `readiness_score`는 분석축이며 최종 상태와 동일하지 않다. 높은 원점수는 필수 게이트 실패를 상쇄하지 않는다.

예시 계약:

```text
사실지지 원점수: 87
판정가능도 원점수: 82
G-03: FAIL
게이트 상한: 59
판정가능도 최종점수: 59
상태: insufficient
사유: 심사시점 접근권한표 및 조회로그 미확보
```

이 예시는 산식 검산용이며 실제 사건의 I-02 판정을 확정하는 값이 아니다.

### DEC-KD-004 — 6단계 상태체계

| 코드 | 표시 | 의미 |
|---|---|---|
| `confirmed` | 확정 | 직접증거와 필수 게이트로 사실관계가 닫힌 상태 |
| `supported` | 유력 | 복수 근거로 상당히 지지되지만 확정요건 일부가 부족한 상태 |
| `conditional` | 조건부 | 명시된 조건이나 전제가 참일 때 성립하는 상태 |
| `insufficient` | 불충분 | 핵심 게이트 실패로 현재 결론을 확정할 수 없는 상태 |
| `contradicted` | 반증됨 | 결정적인 직접 반증이 주장을 적극적으로 부정하는 상태 |
| `unassessed` | 미평가 | 입력 미완료 또는 평가 미실행으로 산식을 적용하지 않은 상태 |

`unassessed`의 표시값은 실제 가능성 0%를 뜻하지 않으며 `not_estimated` 의미로 관리한다.

### DEC-KD-005 — 게이트 결과와 효과의 분리

게이트 결과는 `PASS / FAIL / NA / PENDING`, 효과는 `BLOCK / CAP / INFO`로 분리한다.

- `BLOCK`: 실패 시 `insufficient` 상한
- `CAP`: 실패 시 지정된 상태 이상으로 올라가지 못함
- `INFO`: 상태를 제한하지 않고 주의·설명정보로만 기록

결과에는 첫 번째 상태 영향 실패조건을 `decisive_gate_code`로 저장한다. 방법론 표시순서와 다른 코드를 임의로 지정하면 DB가 결과 저장을 거부한다.

### DEC-KD-006 — 결과 사유의 의무화

모든 상태는 다음 값을 반드시 가진다.

```text
status_reason_code
status_reason_short
```

`status_reason_short`는 화면과 CSV에 표시할 240자 이하 설명이다. `근거 부족`처럼 일반적인 문구만 쓰지 않고 실패 게이트와 미확보 자료를 특정한다.

### DEC-KD-007 — 증거 속성은 주장·평가실행별로 판정

동일 문서가 어떤 주장에는 직접증거이고 다른 주장에는 정황 또는 반증일 수 있다. 따라서 직접성·지지/반증 방향·적용시점·포괄범위·해당 주장에 대한 증거등급은 원문서 행이 아니라 `evaluation_evidence_links`에 저장한다.

원문서 행에는 진본성, 출처등급, 독립성, 해시 등 문서 자체 속성을 둔다.

### DEC-KD-008 — 현재 상태는 파생 캐시

`claims.current_status_code`와 `current_status_reason_short`는 진실의 원본이 아니다. 새 평가결과가 저장될 때 DB 트리거가 자동으로 materialize하는 표시용 캐시다.

이 필드를 직접 변경하면 DB가 저장을 거부한다. 판정을 변경하려면 반드시 새 `evaluation_run`과 결과를 생성해야 한다.

### DEC-KD-009 — append-only 이력과 방법론 버전

- 완료된 평가실행, 입력점수, 게이트 결과, 증거 연결, 결과는 덮어쓰지 않는다.
- 재평가는 새 실행으로 추가하고 `prior_run_id`로 이전 실행을 연결한다.
- 과거 상태의 유효 종료시점은 다음 실행시각을 이용해 View에서 계산한다.
- 방법론이 바뀌면 기존 기준을 수정하지 않고 새 `methodology_version`을 만든다.
- 결과 생성 시 변경 이벤트를 자동으로 기록한다.

### DEC-KD-010 — 설명가능 CSV 계약

현재 판정 CSV는 적어도 다음 값을 포함한다.

```text
claim_id
claim_text
status_code
status_label
status_reason_code
status_reason_short
fact_support_final_score
readiness_final_score
passed_gate_codes
failed_gate_codes
missing_evidence_codes
conditional_assumptions
highest_evidence_grade
evidence_count
contradicting_evidence_count
calculation_type
methodology_version
engine_version
evaluated_at
human_review_status
```

`ledger.current_evaluation_export_rows`를 이 최소 계약의 DB View로 사용한다.

### DEC-KD-011 — 보안 기본값

- 모든 업무 테이블은 RLS를 활성화하고 기본 공개정책을 만들지 않는다.
- 공개키는 RLS 적용을 전제로만 사용한다.
- 서비스 역할 키와 DB 접속문자열은 서버 환경변수에만 둔다.
- 원본 사건자료와 개인정보는 초기 DB에 업로드하지 않는다.
- 공개 화면에는 비식별 결과, 증거번호, 축약 해시만 제공한다.
- 원본 위치와 민감 메타데이터는 별도 비공개 스키마에서 관리한다.

## 3. 구현된 보호장치

- 항목별 가중점수는 `입력점수 × 버전된 가중치 ÷ 100`과 일치해야 한다.
- 원점수는 해당 방법론의 전체 평가항목 합계와 일치해야 한다.
- 최종점수는 실패 게이트의 수치 상한을 반영해야 한다.
- PASS/FAIL 배열은 상세 게이트 행과 일치해야 한다.
- 증거 수, 직접증거 수, 최고등급, 반증 수는 증거 연결행과 일치해야 한다.
- 미확보 증거와 조건부 전제 배열은 정규화된 연결행과 일치해야 한다.
- 최종 상태는 게이트 우선 함수의 계산값과 일치해야 한다.
- `confirmed`는 E4 이상 직접증거와 중대 반증 부재를 요구한다.
- `conditional`, `insufficient`, `contradicted`는 각각 전제·실패 게이트·반증자료가 실제로 존재해야 한다.

## 4. 현재 범위와 보류사항

완료:

- 로컬 PostgreSQL 마이그레이션 작성
- 방법론 v1 기준 13개와 게이트 9개 정의
- 롤백형 `87 → 82 → G-03 → 59 → insufficient` 계약 검산 작성
- Netlify 빌드 성공 확인

미완료·별도 승인 필요:

- Supabase 원격 프로젝트에 마이그레이션 적용
- 롤백형 계약 검산을 실제 PostgreSQL에서 실행
- 기존 화면 상수를 DB의 claim/evaluation 데이터로 이전
- Netlify 환경변수 등록과 서버 측 DB 연결
- 사용자 인증·관리자 역할·RLS 정책 확정
- 원본 파일 저장 여부와 암호화·백업·보존정책 확정
- `INFO` 효과를 사용할 실제 게이트 정의

## 5. 관련 구현

- [`202609120001_kdata_evidence_ledger.sql`](../../supabase/migrations/202609120001_kdata_evidence_ledger.sql)
- [`202609120002_kdata_methodology_v1.sql`](../../supabase/migrations/202609120002_kdata_methodology_v1.sql)
- [`evaluation_contract.sql`](../../supabase/tests/evaluation_contract.sql)
- [`Supabase 운영 원칙`](../../supabase/README.md)

## 6. 다음 작업 순서

1. 원격 적용 전 마이그레이션 SQL 최종 검토
2. K-DATA 전용 Supabase에 마이그레이션 적용
3. 롤백형 계약 검산 실행
4. 현재 화면의 각 주장에 증거·입력·게이트를 매핑
5. 실제 평가 실행을 생성하고 기존 상수와 차이를 비교
6. CSV 다운로드와 상세 판정 설명 UI 연결
7. 공개 전 비식별·접근권한·환경변수 검사
