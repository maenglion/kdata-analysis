-- 마이그레이션 적용 후 SQL Editor에서 실행하는 롤백형 계약 검산이다.
-- 성공하더라도 마지막 ROLLBACK으로 시험 데이터는 남지 않는다.
begin;

insert into ledger.claims (id, claim_type, title, claim_text)
values ('TEST-I-02', 'causal_access', '심사 당시 접근 가능 상태', '검산용 가상 주장');

insert into ledger.evidence (
  id, title, source_grade, authenticity, independence, source_locator, sha256
)
values
  ('TEST-EV-01', '검산용 공식문서', 4, 'original', 'independent', 'TEST:1', repeat('a', 64)),
  ('TEST-EV-02', '검산용 독립자료', 3, 'verified_copy', 'independent', 'TEST:2', repeat('b', 64));

insert into ledger.evidence_requests (id, title, request_text)
values
  ('E-04', '접근로그', '심사시점 사용자별 접근·조회 로그'),
  ('E-07', '권한표', '심사시점 담당자별 문서·시스템 접근권한표');

do $$
declare
  methodology_uuid uuid;
  run_uuid uuid;
begin
  select id into methodology_uuid
  from ledger.methodologies
  where code = 'KDATA_CLAIM_EVAL' and version = '1.0.0';

  insert into ledger.evaluation_runs (
    claim_id, methodology_id, calculation_type, engine_name, engine_version,
    input_snapshot, human_review_status
  )
  values (
    'TEST-I-02', methodology_uuid, 'estimated', 'contract-test', '1.0.0',
    jsonb_build_object('case', 'I-02', 'purpose', 'formula-and-gate-verification'),
    'reviewed'
  )
  returning id into run_uuid;

  insert into ledger.evaluation_factor_scores (
    run_id, criterion_id, input_score, applied_weight, weighted_score, basis
  )
  select
    run_uuid,
    ec.id,
    scores.input_score,
    ec.weight,
    round((scores.input_score * ec.weight / 100)::numeric, 3),
    '계약 검산 입력값'
  from ledger.evaluation_criteria ec
  join ledger.evaluation_dimensions ed on ed.id = ec.dimension_id
  join (
    values
      ('FS-01', 85::numeric), ('FS-02', 90::numeric), ('FS-03', 90::numeric),
      ('FS-04', 80::numeric), ('FS-05', 100::numeric), ('FS-06', 75::numeric),
      ('FS-07', 90::numeric), ('RD-01', 90::numeric), ('RD-02', 80::numeric),
      ('RD-03', 80::numeric), ('RD-04', 75::numeric), ('RD-05', 80::numeric),
      ('RD-06', 100::numeric)
  ) as scores(code, input_score) on scores.code = ec.code
  where ed.methodology_id = methodology_uuid;

  insert into ledger.evaluation_gate_results (
    run_id, gate_id, gate_code, gate_name, input_value, required_value,
    result, effect, score_cap, status_cap, reason_code, reason_text
  )
  select
    run_uuid,
    mg.id,
    mg.code,
    mg.name,
    case when mg.code = 'G-03'
      then jsonb_build_object('access_log', false, 'authority_matrix', false)
      else jsonb_build_object('contract_test', true)
    end,
    jsonb_build_object('methodology_gate', mg.code),
    outcomes.result,
    mg.effect,
    mg.score_cap,
    mg.status_cap,
    outcomes.reason_code,
    outcomes.reason_text
  from ledger.methodology_gates mg
  join (
    values
      ('G-01', 'PASS', 'SOURCE_LOCATED', '증거번호와 위치 있음'),
      ('G-02', 'PASS', 'CAUSAL_SCOPE_DEFINED', '검증할 인과범위가 정의됨'),
      ('G-03', 'FAIL', 'MISSING_ACCESS_LOG', '심사시점 접근권한표 및 조회로그 미확보'),
      ('G-04', 'PASS', 'COUNTEREVIDENCE_HANDLED', '직접 상충근거 없음'),
      ('G-05', 'PASS', 'PRIMARY_SOURCE_PRESENT', '원출처 증거 있음'),
      ('G-06', 'PASS', 'TEMPORAL_SCOPE_MATCHED', '관련 시점이 특정됨'),
      ('G-07', 'PASS', 'EVIDENCE_DEDUPED', '중복 근거 제거됨'),
      ('G-08', 'PASS', 'DIRECT_EVIDENCE_PRESENT', '직접증거 있음'),
      ('G-09', 'NA', 'NO_CONDITIONAL_ASSUMPTION', '적용할 조건 전제 없음')
  ) as outcomes(code, result, reason_code, reason_text) on outcomes.code = mg.code
  where mg.methodology_id = methodology_uuid;

  insert into ledger.evaluation_evidence_links (
    run_id, evidence_id, use_role, evidence_grade, directness,
    temporality, coverage, contribution_note
  )
  values
    (run_uuid, 'TEST-EV-01', 'support', 4, 'direct', 'contemporaneous', 'partial', '공식 직접기록'),
    (run_uuid, 'TEST-EV-02', 'support', 3, 'indirect', 'retrospective', 'partial', '독립 보강자료');

  insert into ledger.evaluation_missing_evidence_links (run_id, evidence_request_id, reason)
  values
    (run_uuid, 'E-04', '실제 조회 여부 확인 필요'),
    (run_uuid, 'E-07', '심사시점 접근 가능 권한 확인 필요');

  insert into ledger.evaluation_results (
    run_id,
    fact_support_raw_score, fact_support_final_score, fact_support_level,
    readiness_raw_score, readiness_final_score, readiness_level,
    probability_low, probability_high, probability_semantics, probability_basis,
    status_code, status_label, status_reason_code, status_reason_short,
    decisive_gate_code, passed_gate_codes, failed_gate_codes,
    highest_evidence_grade, evidence_count, direct_evidence_count,
    independent_source_count, contradicting_evidence_count,
    missing_evidence_codes, conditional_assumptions,
    formula_snapshot, decision_trace
  )
  values (
    run_uuid,
    87, 87, '강하게 지지',
    82, 59, '게이트 상한 적용',
    80, 95, 'estimated', '동일 소관부서와 선행 처리경로를 사용한 검산 예시',
    'insufficient', '불충분', 'MISSING_ACCESS_LOG',
    'G-03 실패 · 심사시점 접근권한표 및 조회로그 미확보',
    'G-03',
    jsonb_build_array('G-01', 'G-02', 'G-04', 'G-05', 'G-06', 'G-07', 'G-08'),
    jsonb_build_array('G-03'),
    4, 2, 1, 2, 0,
    jsonb_build_array('E-04', 'E-07'),
    '[]'::jsonb,
    jsonb_build_object(
      'fact_support', 'sum(input_score * weight / 100)',
      'readiness', 'min(raw_score, failed_gate_caps)'
    ),
    jsonb_build_object(
      'rule_path', jsonb_build_array('scores-calculated', 'G-03-failed', 'BLOCK-to-insufficient'),
      'first_failed_condition', 'G-03'
    )
  );

  if not exists (
    select 1
    from ledger.evaluation_results
    where run_id = run_uuid
      and fact_support_raw_score = 87
      and readiness_raw_score = 82
      and readiness_final_score = 59
      and status_code = 'insufficient'
      and decisive_gate_code = 'G-03'
  ) then
    raise exception 'score/gate/status contract verification failed';
  end if;

  if not exists (
    select 1
    from ledger.claims
    where id = 'TEST-I-02'
      and current_status_code = 'insufficient'
      and current_evaluation_run_id = run_uuid
  ) then
    raise exception 'current status materialization verification failed';
  end if;

  if not exists (
    select 1 from audit.evaluation_events
    where run_id = run_uuid and event_type = 'INITIAL_EVALUATION'
  ) then
    raise exception 'evaluation history verification failed';
  end if;
end;
$$;

rollback;
