# 회의록 — 게이트 우선순위 및 상태 경계 계약

- 일자: 2026-09-12
- 대상: K-DATA Evidence Ledger
- 상태: 설계 채택, 로컬 SQL 및 롤백형 계약 검산 작성 완료, 원격 DB 실행 전
- 공개 범위: 공개 저장소용 비식별 기록

## 1. 배경

판정 재현 DB의 기본 구조를 만든 뒤, 점수와 상태가 실제 SQL에서도 독립적인지와 복수 게이트가 충돌할 때 결정 게이트가 일관되게 선택되는지를 추가 검산할 필요가 확인됐다. 또한 `unassessed`와 `insufficient`의 경계를 명시하지 않으면 신규 주장과 평가 실패 주장이 같은 상태로 섞일 수 있다.

이 기록은 선행 회의록의 DEC-KD-003을 구체화하고, DEC-KD-005의 “첫 번째 상태 영향 실패조건” 표현을 아래의 실질 결정 규칙으로 대체한다. 선행 기록은 이력 보존 원칙에 따라 수정하지 않는다.

## 2. 채택한 결정

### DEC-KD-012 — BLOCK과 점수 상한의 직교성

`BLOCK`과 `score_cap`은 서로 다른 역할을 가진다.

```text
readiness_raw = 82
G-03 BLOCK FAIL
→ readiness_final = min(82, 59) = 59  # 분석축 보조 수치
→ status = insufficient               # BLOCK 효과
```

`59 이하이면 insufficient`와 같은 점수-상태 임계값은 두지 않는다. 최종 상태의 이유는 `G-03`의 `BLOCK` 실패이고, 59점은 그 실패가 판정가능도 수치에 준 제한을 설명한다.

### DEC-KD-013 — 복수 게이트의 상태효과 우선순위

상태효과 우선순위는 다음과 같이 고정한다.

```text
BLOCK > CAP > INFO
```

- 실패한 `BLOCK`이 하나라도 있으면 상태는 `insufficient`다.
- `BLOCK`이 없고 실패한 `CAP`이 여러 개이면 가장 낮은 허용상태를 만드는 CAP을 적용한다.
- 같은 효과와 같은 상태 상한이 충돌하면 방법론에 버전된 `gate_priority`가 낮은 게이트를 우선한다.
- `INFO`는 상태를 결정하거나 제한하지 않고 설명정보로만 남긴다.

### DEC-KD-014 — unassessed와 insufficient의 경계

- `unassessed`: 증거 연결과 평가 입력이 아직 구성되지 않아 평가를 실행하지 않은 상태다. 확률 의미는 `not_estimated`이며 실제 가능성 0%를 뜻하지 않는다.
- `insufficient`: 평가 입력을 구성하고 실행했지만 필수 증거 또는 연결조건에 해당하는 `BLOCK` 게이트가 실패한 상태다.

따라서 증거가 연결되지 않은 신규 claim은 자동으로 “근거 부족” 판정을 받은 것이 아니라 아직 평가되지 않은 것이다. 반면 증거와 입력을 넣고 G-03에 필요한 권한표·조회로그가 없음을 확인했다면 `insufficient`다.

### DEC-KD-015 — 실질 결정 게이트

`decisive_gate_code`는 SQL 정렬상 첫 번째 실패행이 아니라 다음 정의를 따른다.

> 최종 상태를 그 이상으로 올리지 못하게 만든 가장 우선적인 상태영향 게이트

선택 규칙:

1. 실패한 `BLOCK` 중 `gate_priority`가 가장 높은 우선순위
2. `BLOCK`이 없으면 가장 낮은 허용상태를 만드는 실패 `CAP`
3. CAP의 허용상태가 같으면 `gate_priority`가 가장 높은 우선순위
4. 나머지 실패 게이트는 삭제하지 않고 `failed_gate_codes`에 모두 보존

## 3. 추가한 계약 검산

| 계약 | 입력 | 기대 결과 | 검산 목적 |
|---|---|---|---|
| BLOCK 독립성 | readiness 82, G-03 BLOCK FAIL, score cap 59 | 59점, `insufficient`, decisive G-03 | 점수가 아니라 BLOCK이 상태를 결정 |
| 복수 CAP | G-08 CAP supported, G-09 CAP conditional | `conditional`, decisive G-09 | 가장 낮은 허용상태 적용 |
| 점수 불변성 | 동일 CAP 입력에 점수 90과 65를 각각 적용 | 두 실행 모두 `conditional` | 수치가 상태를 결정하지 않음 |
| BLOCK·CAP 충돌 | G-03·G-06 BLOCK과 G-08·G-09 CAP 동시 실패 | `insufficient`, decisive G-03, 실패 4건 모두 보존 | 효과 우선순위와 명시적 gate_priority |
| 미평가 경계 | 입력·증거·게이트가 없는 unscored 실행 | `unassessed`, 점수 null, 증거 수 0 | 신규 주장과 평가 후 불충분을 분리 |

모든 검산은 마지막에 `ROLLBACK`하는 시험 SQL로 작성했으며 실제 사건 데이터는 만들지 않는다.

## 4. 구현 영향

- 방법론 게이트에 버전된 `gate_priority`를 추가했다.
- 평가 실행의 게이트 결과에도 해당 우선순위를 스냅샷으로 저장하고 방법론 정의와의 불일치를 거부한다.
- `ledger.decisive_gate_for_run()`을 추가해 실질 결정 게이트를 계산한다.
- `ledger.derive_status_for_run()`은 원점수나 최종점수의 구간을 읽지 않고 게이트·전제·반증·증거조건으로 상태를 산출한다.
- 결과 검증 트리거는 입력한 `decisive_gate_code`가 위 규칙의 계산값과 다르면 저장을 거부한다.

## 5. 현재 범위와 다음 단계

완료:

- 로컬 마이그레이션과 방법론 seed 수정
- 다중 CAP, 점수 불변성, BLOCK·CAP 충돌, 미평가 경계 계약 검산 작성
- 운영 문서에 점수·상태 분리와 우선순위 명시

아직 하지 않음:

- K-DATA 전용 Supabase에 마이그레이션 적용
- 실제 PostgreSQL에서 롤백형 계약 검산 실행
- 기존 화면 상수를 DB 평가실행으로 이전
- Netlify 환경변수 등록 또는 배포

다음 순서는 원격 적용 전 SQL 검토, K-DATA 전용 Supabase 적용, 계약 검산 실행, 성공 결과 확인 후 화면 상수 이전이다.

## 6. 관련 구현

- [`202609120001_kdata_evidence_ledger.sql`](../../supabase/migrations/202609120001_kdata_evidence_ledger.sql)
- [`202609120002_kdata_methodology_v1.sql`](../../supabase/migrations/202609120002_kdata_methodology_v1.sql)
- [`evaluation_contract.sql`](../../supabase/tests/evaluation_contract.sql)
- [`Supabase 운영 원칙`](../../supabase/README.md)
