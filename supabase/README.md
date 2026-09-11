# K-DATA Supabase 운영 원칙

이 디렉터리의 마이그레이션은 K-DATA 전용 Supabase 프로젝트에만 적용한다.
신용보증기금 프로젝트, 데이터베이스, Storage, 환경변수와 공유하지 않는다.

## 적용 전 확인

1. Supabase 프로젝트 참조값이 K-DATA 전용 값인지 확인한다.
2. SQL Editor에서 전체 마이그레이션을 검토한다.
3. 원본 사건자료와 개인정보는 초기 DB에 업로드하지 않는다.
4. 최초 적용 후 `ledger`, `audit`, `private` 스키마와 RLS 활성화를 확인한다.
5. 공개키만 프런트엔드에서 사용하고 `service_role` 및 DB 접속 문자열은 서버 환경변수로만 관리한다.

## 데이터 변경 원칙

- 판정 체인은 `원자료 → 증거등급 → 평가 입력값 → 방법론 산식 → 게이트 검사 → 6단계 결과 → 현재 표시 캐시 → 변경이력` 순서로 고정한다.
- 평가 결과는 수정하지 않고 새 `evaluation_run`으로 추가한다.
- `evaluation_results`, `evaluation_events`, `export_events`는 append-only다.
- 모든 상태에는 `status_reason_code`와 `status_reason_short`가 필수다.
- 점수는 분석축이고 상태는 게이트 결과가 결정한다. 높은 원점수가 실패 게이트를 대체하지 않으며, 특정 점수구간을 상태에 대응시키는 숨은 임계값을 두지 않는다.
- `BLOCK` 실패는 점수 상한과 독립적으로 `insufficient`를 결정한다. `score_cap`은 판정가능도 보조 수치를 제한할 뿐 상태의 원인이 아니다.
- 복수 실패의 상태효과 우선순위는 `BLOCK > CAP > INFO`다. 복수 CAP은 가장 낮은 허용상태가 우선하며, 동일 효과·동일 상한은 버전된 `gate_priority`로 결정한다.
- `decisive_gate_code`는 SQL 조회순서상 첫 행이 아니라 최종 상태를 그 이상으로 올리지 못하게 한 실질 결정 게이트다. 다른 실패 게이트도 `failed_gate_codes`에 모두 보존한다.
- `ledger.derive_status_for_run()`이 게이트·조건전제·결정적 반증·증거등급으로 상태를 계산하며 결과 행의 임의 상태 입력을 거부한다.
- 게이트에는 `PASS / FAIL / NA / PENDING`과 `BLOCK / CAP / INFO`를 각각 저장한다.
- `claims.current_status_*`는 최신 결과에서 자동 생성되는 표시용 캐시이며 판정의 원본이 아니다.
- 과거 판정의 유효기간은 append-only 결과를 기반으로 `evaluation_result_timeline` View가 계산한다.
- 평가 입력이 구성되지 않아 실행하지 않은 주장은 `unassessed`로 기록한다. 입력을 구성해 평가했으나 필수 증거 게이트가 실패한 경우는 `insufficient`로 기록한다.
- CSV는 서버에서 생성하며 상태 코드·표시명·간단한 사유·산식 버전을 항상 포함한다.

## CSV 기본 View

`ledger.current_evaluation_export_rows`는 현재 판정 CSV의 최소 계약이다. 다음을 포함한다.

- 주장 ID와 주장 원문
- 6단계 상태 코드·표시명
- 사유 코드·짧은 사유
- 사실지지 최종점수·판정가능도 최종점수
- 통과·실패 게이트와 미확보 증거
- 조건부 전제
- 최고 증거등급·증거 수·반증 수
- 계산 유형·방법론 버전·엔진 버전·평가시각·인간검토 상태
