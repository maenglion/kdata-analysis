begin;

create extension if not exists pgcrypto;

create schema if not exists ledger;
create schema if not exists audit;
create schema if not exists private;

revoke all on schema ledger from anon, authenticated;
revoke all on schema audit from anon, authenticated;
revoke all on schema private from anon, authenticated;

create table ledger.claims (
  id text primary key,
  claim_type text not null,
  title text not null,
  claim_text text not null,
  legacy_status text check (legacy_status in ('F', 'I', 'U')),
  current_status_code text
    check (current_status_code in ('confirmed', 'supported', 'conditional', 'insufficient', 'contradicted', 'unassessed')),
  current_status_reason_short text,
  current_evaluation_run_id uuid,
  current_status_materialized_at timestamptz,
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check (
    (current_status_code is null and current_status_reason_short is null and current_evaluation_run_id is null and current_status_materialized_at is null)
    or
    (current_status_code is not null and length(trim(current_status_reason_short)) > 0 and current_evaluation_run_id is not null)
  )
);

create table ledger.evidence (
  id text primary key,
  title text not null,
  source_grade smallint not null check (source_grade between 0 and 5),
  authenticity text not null check (authenticity in ('original', 'verified_copy', 'unverified')),
  independence text not null check (independence in ('independent', 'shared_origin', 'duplicate')),
  source_locator text,
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  public_hash_prefix text,
  source_limitation text,
  is_public boolean not null default false,
  collected_at timestamptz,
  created_at timestamptz not null default now()
);

create table private.evidence_locations (
  evidence_id text primary key references ledger.evidence(id) on delete restrict,
  storage_provider text not null,
  storage_locator text not null,
  contains_personal_data boolean not null default true,
  retention_note text,
  created_at timestamptz not null default now()
);

create table ledger.evidence_requests (
  id text primary key,
  title text not null,
  request_text text not null,
  request_status text not null default 'needed'
    check (request_status in ('needed', 'requested', 'received', 'partial', 'unavailable', 'closed')),
  narrows_claim_ids jsonb not null default '[]'::jsonb,
  expected_uncertainty_reduction text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table ledger.methodologies (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  version text not null,
  name text not null,
  description text not null,
  effective_from timestamptz not null,
  retired_at timestamptz,
  formula_definition jsonb not null,
  created_at timestamptz not null default now(),
  unique (code, version)
);

create table ledger.evaluation_dimensions (
  id uuid primary key default gen_random_uuid(),
  methodology_id uuid not null references ledger.methodologies(id) on delete restrict,
  code text not null,
  name text not null,
  weight_total numeric(6,3) not null default 100 check (weight_total > 0),
  display_order integer not null,
  unique (methodology_id, code)
);

create table ledger.evaluation_criteria (
  id uuid primary key default gen_random_uuid(),
  dimension_id uuid not null references ledger.evaluation_dimensions(id) on delete restrict,
  code text not null,
  name text not null,
  definition text not null,
  weight numeric(6,3) not null check (weight > 0),
  score_min numeric(6,3) not null default 0,
  score_max numeric(6,3) not null default 100,
  display_order integer not null,
  unique (dimension_id, code),
  check (score_min < score_max)
);

create table ledger.methodology_gates (
  id uuid primary key default gen_random_uuid(),
  methodology_id uuid not null references ledger.methodologies(id) on delete restrict,
  code text not null,
  name text not null,
  definition text not null,
  effect text not null check (effect in ('BLOCK', 'CAP', 'INFO')),
  score_cap numeric(6,3) check (score_cap between 0 and 100),
  status_cap text
    check (status_cap in ('confirmed', 'supported', 'conditional', 'insufficient', 'contradicted', 'unassessed')),
  is_core boolean not null default true,
  gate_priority integer not null check (gate_priority > 0),
  display_order integer not null,
  unique (methodology_id, code),
  unique (methodology_id, gate_priority),
  unique (id, code),
  check (effect = 'INFO' or score_cap is not null or status_cap is not null)
);

create table ledger.evaluation_runs (
  id uuid primary key default gen_random_uuid(),
  claim_id text not null references ledger.claims(id) on delete restrict,
  methodology_id uuid not null references ledger.methodologies(id) on delete restrict,
  prior_run_id uuid references ledger.evaluation_runs(id) on delete restrict,
  calculation_type text not null
    check (calculation_type in ('observed', 'derived', 'estimated', 'unscored')),
  engine_name text not null,
  engine_version text not null,
  evaluated_at timestamptz not null default now(),
  evaluated_by uuid references auth.users(id) on delete set null,
  human_review_status text not null default 'pending'
    check (human_review_status in ('pending', 'reviewed', 'approved', 'rejected')),
  input_snapshot jsonb not null,
  notes text
);

alter table ledger.claims
  add constraint claims_current_evaluation_run_fk
  foreign key (current_evaluation_run_id)
  references ledger.evaluation_runs(id)
  on delete restrict;

create table ledger.evaluation_factor_scores (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references ledger.evaluation_runs(id) on delete restrict,
  criterion_id uuid not null references ledger.evaluation_criteria(id) on delete restrict,
  input_score numeric(6,3) not null check (input_score between 0 and 100),
  applied_weight numeric(6,3) not null check (applied_weight > 0),
  weighted_score numeric(7,3) not null check (weighted_score between 0 and 100),
  basis text not null check (length(trim(basis)) > 0),
  source_values jsonb not null default '{}'::jsonb,
  unique (run_id, criterion_id)
);

create table ledger.evaluation_gate_results (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references ledger.evaluation_runs(id) on delete restrict,
  gate_id uuid not null references ledger.methodology_gates(id) on delete restrict,
  gate_code text not null,
  gate_name text not null,
  input_value jsonb not null default '{}'::jsonb,
  required_value jsonb not null default '{}'::jsonb,
  result text not null check (result in ('PASS', 'FAIL', 'NA', 'PENDING')),
  effect text not null check (effect in ('BLOCK', 'CAP', 'INFO')),
  score_cap numeric(6,3) check (score_cap between 0 and 100),
  status_cap text
    check (status_cap in ('confirmed', 'supported', 'conditional', 'insufficient', 'contradicted', 'unassessed')),
  gate_priority integer not null check (gate_priority > 0),
  reason_code text not null check (length(trim(reason_code)) > 0),
  reason_text text not null check (length(trim(reason_text)) > 0),
  unique (run_id, gate_id),
  unique (run_id, gate_code),
  foreign key (gate_id, gate_code) references ledger.methodology_gates(id, code) on delete restrict,
  check (result <> 'FAIL' or effect = 'INFO' or score_cap is not null or status_cap is not null)
);

create table ledger.evaluation_results (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references ledger.evaluation_runs(id) on delete restrict,
  fact_support_raw_score numeric(6,3) check (fact_support_raw_score between 0 and 100),
  fact_support_final_score numeric(6,3) check (fact_support_final_score between 0 and 100),
  fact_support_level text,
  readiness_raw_score numeric(6,3) check (readiness_raw_score between 0 and 100),
  readiness_final_score numeric(6,3) check (readiness_final_score between 0 and 100),
  readiness_level text,
  probability_low numeric(6,3) check (probability_low between 0 and 100),
  probability_high numeric(6,3) check (probability_high between 0 and 100),
  probability_semantics text not null
    check (probability_semantics in ('confirmed', 'estimated', 'not_estimated')),
  probability_basis text not null check (length(trim(probability_basis)) > 0),
  status_code text not null
    check (status_code in ('confirmed', 'supported', 'conditional', 'insufficient', 'contradicted', 'unassessed')),
  status_label text not null,
  status_reason_code text not null check (length(trim(status_reason_code)) > 0),
  status_reason_short text not null check (length(trim(status_reason_short)) between 1 and 240),
  decisive_gate_code text,
  passed_gate_codes jsonb not null default '[]'::jsonb,
  failed_gate_codes jsonb not null default '[]'::jsonb,
  highest_evidence_grade smallint check (highest_evidence_grade between 0 and 5),
  evidence_count integer not null default 0 check (evidence_count >= 0),
  direct_evidence_count integer not null default 0 check (direct_evidence_count >= 0),
  independent_source_count integer not null default 0 check (independent_source_count >= 0),
  contradicting_evidence_count integer not null default 0 check (contradicting_evidence_count >= 0),
  missing_evidence_codes jsonb not null default '[]'::jsonb,
  conditional_assumptions jsonb not null default '[]'::jsonb,
  formula_snapshot jsonb not null,
  decision_trace jsonb not null,
  created_at timestamptz not null default now(),
  check (
    (status_code = 'confirmed' and status_label = '확정')
    or (status_code = 'supported' and status_label = '유력')
    or (status_code = 'conditional' and status_label = '조건부')
    or (status_code = 'insufficient' and status_label = '불충분')
    or (status_code = 'contradicted' and status_label = '반증됨')
    or (status_code = 'unassessed' and status_label = '미평가')
  ),
  check (jsonb_typeof(passed_gate_codes) = 'array'),
  check (jsonb_typeof(failed_gate_codes) = 'array'),
  check (jsonb_typeof(missing_evidence_codes) = 'array'),
  check (jsonb_typeof(conditional_assumptions) = 'array'),
  check (jsonb_typeof(formula_snapshot) = 'object'),
  check (jsonb_typeof(decision_trace) = 'object' and decision_trace ? 'rule_path'),
  check (probability_low is null or probability_high is null or probability_low <= probability_high),
  check (fact_support_raw_score is null or fact_support_final_score is null or fact_support_final_score <= fact_support_raw_score),
  check (readiness_raw_score is null or readiness_final_score is null or readiness_final_score <= readiness_raw_score),
  check (status_code = 'unassessed' or readiness_final_score is not null),
  check (
    status_code <> 'confirmed'
    or (
      highest_evidence_grade >= 4
      and direct_evidence_count > 0
      and contradicting_evidence_count = 0
    )
  ),
  check (status_code <> 'conditional' or jsonb_array_length(conditional_assumptions) > 0),
  check (status_code <> 'insufficient' or jsonb_array_length(failed_gate_codes) > 0),
  check (status_code <> 'contradicted' or contradicting_evidence_count > 0),
  check (status_code <> 'supported' or evidence_count >= 2 and contradicting_evidence_count = 0),
  check (status_code <> 'unassessed' or readiness_final_score is null),
  check (fact_support_final_score is not distinct from fact_support_raw_score)
);

create table ledger.evaluation_evidence_links (
  run_id uuid not null references ledger.evaluation_runs(id) on delete restrict,
  evidence_id text not null references ledger.evidence(id) on delete restrict,
  use_role text not null check (use_role in ('support', 'contradiction', 'context')),
  evidence_grade smallint not null check (evidence_grade between 0 and 5),
  directness text not null check (directness in ('direct', 'indirect', 'context')),
  temporality text not null check (temporality in ('contemporaneous', 'retrospective')),
  coverage text not null check (coverage in ('full', 'partial', 'peripheral')),
  is_decisive boolean not null default false,
  contribution_note text not null check (length(trim(contribution_note)) > 0),
  limitation text,
  counterinterpretation text,
  primary key (run_id, evidence_id, use_role),
  check (not is_decisive or use_role = 'contradiction' and directness = 'direct')
);

create table ledger.evaluation_missing_evidence_links (
  run_id uuid not null references ledger.evaluation_runs(id) on delete restrict,
  evidence_request_id text not null references ledger.evidence_requests(id) on delete restrict,
  reason text not null check (length(trim(reason)) > 0),
  primary key (run_id, evidence_request_id)
);

create table ledger.evaluation_assumptions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references ledger.evaluation_runs(id) on delete restrict,
  assumption_code text not null,
  assumption_text text not null check (length(trim(assumption_text)) > 0),
  assumption_status text not null check (assumption_status in ('pending', 'satisfied', 'rejected')),
  impact_note text not null check (length(trim(impact_note)) > 0),
  unique (run_id, assumption_code)
);

create table ledger.web_snapshots (
  id text primary key,
  url text not null,
  captured_at timestamptz not null,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  public_hash_prefix text not null,
  display_summary text not null,
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create table audit.evaluation_events (
  id bigint generated always as identity primary key,
  claim_id text not null references ledger.claims(id) on delete restrict,
  run_id uuid references ledger.evaluation_runs(id) on delete restrict,
  prior_run_id uuid references ledger.evaluation_runs(id) on delete restrict,
  event_type text not null,
  before_state jsonb,
  after_state jsonb not null,
  change_reason text not null check (length(trim(change_reason)) > 0),
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now()
);

create table audit.export_events (
  id bigint generated always as identity primary key,
  export_type text not null,
  filter_snapshot jsonb not null default '{}'::jsonb,
  row_count integer not null check (row_count >= 0),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  requested_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index evaluation_runs_claim_time_idx
  on ledger.evaluation_runs (claim_id, evaluated_at desc);
create index evaluation_evidence_evidence_idx
  on ledger.evaluation_evidence_links (evidence_id);
create index evaluation_missing_evidence_request_idx
  on ledger.evaluation_missing_evidence_links (evidence_request_id);
create index evaluation_events_claim_time_idx
  on audit.evaluation_events (claim_id, occurred_at desc);
create index evidence_requests_status_idx
  on ledger.evidence_requests (request_status);

create function audit.reject_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% is append-only; create a new evaluation run or correction event', tg_table_name;
end;
$$;

create function audit.reject_finalized_run_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_run_id uuid;
begin
  target_run_id := case when tg_op = 'DELETE' then old.run_id else new.run_id end;

  if exists (
    select 1
    from ledger.evaluation_results
    where run_id = target_run_id
  ) then
    raise exception 'evaluation run % is finalized; create a new run', target_run_id;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create function ledger.status_rank(value text)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case value
    when 'insufficient' then 1
    when 'conditional' then 2
    when 'supported' then 3
    when 'confirmed' then 4
    else 0
  end;
$$;

create function ledger.validate_factor_score()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  criterion_weight numeric(6,3);
  criterion_methodology_id uuid;
  run_methodology_id uuid;
  expected_weighted_score numeric(7,3);
begin
  select ec.weight, ed.methodology_id
  into criterion_weight, criterion_methodology_id
  from ledger.evaluation_criteria ec
  join ledger.evaluation_dimensions ed on ed.id = ec.dimension_id
  where ec.id = new.criterion_id;

  select methodology_id
  into run_methodology_id
  from ledger.evaluation_runs
  where id = new.run_id;

  if criterion_methodology_id is distinct from run_methodology_id then
    raise exception 'criterion and evaluation run must use the same methodology';
  end if;

  if new.applied_weight is distinct from criterion_weight then
    raise exception 'applied_weight must match the versioned methodology criterion';
  end if;

  expected_weighted_score := round((new.input_score * criterion_weight / 100)::numeric, 3);
  if new.weighted_score is distinct from expected_weighted_score then
    raise exception 'weighted_score must equal input_score * weight / 100';
  end if;

  return new;
end;
$$;

create function ledger.validate_gate_result_input()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  gate_definition ledger.methodology_gates%rowtype;
  run_methodology_id uuid;
begin
  select *
  into gate_definition
  from ledger.methodology_gates
  where id = new.gate_id;

  select methodology_id
  into run_methodology_id
  from ledger.evaluation_runs
  where id = new.run_id;

  if gate_definition.methodology_id is distinct from run_methodology_id then
    raise exception 'gate and evaluation run must use the same methodology';
  end if;

  if new.gate_code is distinct from gate_definition.code
     or new.gate_name is distinct from gate_definition.name
     or new.effect is distinct from gate_definition.effect
     or new.score_cap is distinct from gate_definition.score_cap
     or new.status_cap is distinct from gate_definition.status_cap
     or new.gate_priority is distinct from gate_definition.gate_priority then
    raise exception 'gate result snapshot must match the versioned methodology gate';
  end if;

  return new;
end;
$$;

create function ledger.decisive_gate_for_run(target_run_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  decisive_code text;
begin
  -- BLOCK은 수치 상한이나 CAP보다 먼저 최종 상태를 insufficient로 제한한다.
  select gate_code
  into decisive_code
  from ledger.evaluation_gate_results
  where run_id = target_run_id and result = 'FAIL' and effect = 'BLOCK'
  order by gate_priority, gate_code
  limit 1;

  if decisive_code is not null then
    return decisive_code;
  end if;

  -- BLOCK이 없으면 가장 낮은 허용상태를 만드는 CAP이 결정 게이트다.
  select gate_code
  into decisive_code
  from ledger.evaluation_gate_results
  where run_id = target_run_id
    and result = 'FAIL'
    and effect = 'CAP'
    and status_cap is not null
  order by ledger.status_rank(status_cap), gate_priority, gate_code
  limit 1;

  return decisive_code;
end;
$$;

create function ledger.derive_status_for_run(target_run_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  calculation_kind text;
  pending_gate_count integer;
  blocking_failure_count integer;
  cap_rank integer;
  decisive_contradiction_count integer;
  contradiction_count integer;
  support_count integer;
  direct_support_count integer;
  maximum_evidence_grade smallint;
  pending_assumption_count integer;
begin
  select calculation_type
  into calculation_kind
  from ledger.evaluation_runs
  where id = target_run_id;

  select
    count(*) filter (where result = 'PENDING'),
    count(*) filter (where result = 'FAIL' and effect = 'BLOCK'),
    min(ledger.status_rank(status_cap)) filter (
      where result = 'FAIL' and effect = 'CAP' and status_cap is not null
    )
  into pending_gate_count, blocking_failure_count, cap_rank
  from ledger.evaluation_gate_results
  where run_id = target_run_id;

  select
    count(distinct evidence_id) filter (where use_role = 'contradiction' and is_decisive),
    count(distinct evidence_id) filter (where use_role = 'contradiction'),
    count(distinct evidence_id) filter (where use_role = 'support'),
    count(distinct evidence_id) filter (where use_role = 'support' and directness = 'direct'),
    max(evidence_grade)
  into
    decisive_contradiction_count,
    contradiction_count,
    support_count,
    direct_support_count,
    maximum_evidence_grade
  from ledger.evaluation_evidence_links
  where run_id = target_run_id;

  select count(*)
  into pending_assumption_count
  from ledger.evaluation_assumptions
  where run_id = target_run_id and assumption_status = 'pending';

  if calculation_kind = 'unscored' or pending_gate_count > 0 then
    return 'unassessed';
  end if;

  if decisive_contradiction_count > 0 then
    return 'contradicted';
  end if;

  if blocking_failure_count > 0 then
    return 'insufficient';
  end if;

  if cap_rank = 1 then
    return 'insufficient';
  end if;

  if pending_assumption_count > 0 or cap_rank = 2 then
    return 'conditional';
  end if;

  if cap_rank = 3 then
    return 'supported';
  end if;

  if maximum_evidence_grade >= 4 and direct_support_count > 0 and contradiction_count = 0 then
    return 'confirmed';
  end if;

  if support_count >= 2 and contradiction_count = 0 then
    return 'supported';
  end if;

  raise exception 'completed inputs do not justify a six-stage status; correct the gates or evidence links';
end;
$$;

create function ledger.validate_evaluation_result()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  expected_failed jsonb;
  expected_passed jsonb;
  expected_final numeric(6,3);
  expected_gate_count integer;
  actual_gate_count integer;
  pending_gate_count integer;
  blocking_failure_count integer;
  cap_rank integer;
  expected_factor_count integer;
  actual_factor_count integer;
  expected_fact_support_raw numeric(6,3);
  expected_readiness_raw numeric(6,3);
  expected_decisive_gate_code text;
  run_calculation_type text;
  expected_highest_evidence_grade smallint;
  expected_evidence_count integer;
  expected_direct_evidence_count integer;
  expected_independent_source_count integer;
  expected_contradicting_evidence_count integer;
  expected_missing_evidence_codes jsonb;
  expected_conditional_assumptions jsonb;
  expected_status_code text;
begin
  select
    coalesce(jsonb_agg(gate_code order by gate_code) filter (where result = 'FAIL'), '[]'::jsonb),
    coalesce(jsonb_agg(gate_code order by gate_code) filter (where result = 'PASS'), '[]'::jsonb),
    count(*) filter (where result = 'PENDING'),
    count(*) filter (where result = 'FAIL' and effect = 'BLOCK'),
    min(ledger.status_rank(status_cap)) filter (where result = 'FAIL' and effect = 'CAP' and status_cap is not null),
    count(*)
  into
    expected_failed,
    expected_passed,
    pending_gate_count,
    blocking_failure_count,
    cap_rank,
    actual_gate_count
  from ledger.evaluation_gate_results
  where run_id = new.run_id;

  select count(*)
  into expected_gate_count
  from ledger.methodology_gates mg
  join ledger.evaluation_runs er on er.methodology_id = mg.methodology_id
  where er.id = new.run_id;

  select calculation_type
  into run_calculation_type
  from ledger.evaluation_runs
  where id = new.run_id;

  expected_decisive_gate_code := ledger.decisive_gate_for_run(new.run_id);

  select count(*)
  into expected_factor_count
  from ledger.evaluation_criteria ec
  join ledger.evaluation_dimensions ed on ed.id = ec.dimension_id
  join ledger.evaluation_runs er on er.methodology_id = ed.methodology_id
  where er.id = new.run_id;

  select
    count(*),
    coalesce(sum(efs.weighted_score) filter (where ed.code = 'fact_support'), 0),
    coalesce(sum(efs.weighted_score) filter (where ed.code = 'readiness'), 0)
  into actual_factor_count, expected_fact_support_raw, expected_readiness_raw
  from ledger.evaluation_factor_scores efs
  join ledger.evaluation_criteria ec on ec.id = efs.criterion_id
  join ledger.evaluation_dimensions ed on ed.id = ec.dimension_id
  where efs.run_id = new.run_id;

  select
    max(eel.evidence_grade),
    count(distinct eel.evidence_id),
    count(distinct eel.evidence_id) filter (where eel.directness = 'direct'),
    count(distinct eel.evidence_id) filter (where e.independence = 'independent'),
    count(distinct eel.evidence_id) filter (where eel.use_role = 'contradiction')
  into
    expected_highest_evidence_grade,
    expected_evidence_count,
    expected_direct_evidence_count,
    expected_independent_source_count,
    expected_contradicting_evidence_count
  from ledger.evaluation_evidence_links eel
  join ledger.evidence e on e.id = eel.evidence_id
  where eel.run_id = new.run_id;

  select coalesce(jsonb_agg(evidence_request_id order by evidence_request_id), '[]'::jsonb)
  into expected_missing_evidence_codes
  from ledger.evaluation_missing_evidence_links
  where run_id = new.run_id;

  select coalesce(jsonb_agg(assumption_code order by assumption_code), '[]'::jsonb)
  into expected_conditional_assumptions
  from ledger.evaluation_assumptions
  where run_id = new.run_id and assumption_status = 'pending';

  if new.status_code <> 'unassessed' and actual_gate_count <> expected_gate_count then
    raise exception 'all methodology gates must be recorded before a result is finalized';
  end if;

  if new.status_code <> 'unassessed' and actual_factor_count <> expected_factor_count then
    raise exception 'all methodology criteria must be scored before a result is finalized';
  end if;

  if new.status_code <> 'unassessed'
     and (new.fact_support_raw_score is distinct from expected_fact_support_raw
          or new.readiness_raw_score is distinct from expected_readiness_raw) then
    raise exception 'raw scores must equal the sum of versioned weighted factor scores';
  end if;

  if new.status_code <> 'unassessed' and pending_gate_count > 0 then
    raise exception 'a finalized result cannot contain PENDING gates';
  end if;

  if (new.status_code = 'unassessed') is distinct from (run_calculation_type = 'unscored') then
    raise exception 'unassessed status and unscored calculation_type must be used together';
  end if;

  if new.failed_gate_codes <> expected_failed or new.passed_gate_codes <> expected_passed then
    raise exception 'passed_gate_codes and failed_gate_codes must match evaluation_gate_results';
  end if;

  if new.decisive_gate_code is distinct from expected_decisive_gate_code then
    raise exception 'decisive_gate_code must follow BLOCK > lowest CAP > gate_priority precedence';
  end if;

  if new.highest_evidence_grade is distinct from expected_highest_evidence_grade
     or new.evidence_count is distinct from expected_evidence_count
     or new.direct_evidence_count is distinct from expected_direct_evidence_count
     or new.independent_source_count is distinct from expected_independent_source_count
     or new.contradicting_evidence_count is distinct from expected_contradicting_evidence_count then
    raise exception 'materialized evidence counts and grade must match evaluation_evidence_links';
  end if;

  if new.missing_evidence_codes <> expected_missing_evidence_codes then
    raise exception 'missing_evidence_codes must match evaluation_missing_evidence_links';
  end if;

  if new.conditional_assumptions <> expected_conditional_assumptions then
    raise exception 'conditional_assumptions must match pending evaluation_assumptions';
  end if;

  expected_status_code := ledger.derive_status_for_run(new.run_id);
  if new.status_code is distinct from expected_status_code then
    raise exception 'status_code must equal the gate-first derived status %', expected_status_code;
  end if;

  if new.readiness_raw_score is not null then
    select least(
      new.readiness_raw_score,
      coalesce(min(score_cap) filter (where result = 'FAIL' and score_cap is not null), 100)
    )
    into expected_final
    from ledger.evaluation_gate_results
    where run_id = new.run_id;

    if new.readiness_final_score is distinct from expected_final then
      raise exception 'readiness_final_score must equal the raw score after failed-gate caps';
    end if;
  end if;

  if new.status_code not in ('unassessed', 'contradicted') and blocking_failure_count > 0
     and new.status_code <> 'insufficient' then
    raise exception 'a BLOCK gate failure requires insufficient status';
  end if;

  if new.status_code not in ('unassessed', 'contradicted') and cap_rank is not null
     and ledger.status_rank(new.status_code) > cap_rank then
    raise exception 'status exceeds the cap imposed by a failed CAP gate';
  end if;

  if new.status_code = 'insufficient'
     and (new.decisive_gate_code is null or not (new.failed_gate_codes ? new.decisive_gate_code)) then
    raise exception 'insufficient status requires a decisive failed gate';
  end if;

  return new;
end;
$$;

create function ledger.materialize_current_claim_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_claim_id text;
  target_evaluated_at timestamptz;
  current_evaluated_at timestamptz;
begin
  select claim_id, evaluated_at
  into target_claim_id, target_evaluated_at
  from ledger.evaluation_runs
  where id = new.run_id;

  select er.evaluated_at
  into current_evaluated_at
  from ledger.claims c
  left join ledger.evaluation_runs er on er.id = c.current_evaluation_run_id
  where c.id = target_claim_id;

  if current_evaluated_at is null or target_evaluated_at >= current_evaluated_at then
    perform set_config('ledger.materializing_current_status', 'on', true);
    update ledger.claims
    set current_status_code = new.status_code,
        current_status_reason_short = new.status_reason_short,
        current_evaluation_run_id = new.run_id,
        current_status_materialized_at = now()
    where id = target_claim_id;
    perform set_config('ledger.materializing_current_status', 'off', true);
  end if;

  return new;
end;
$$;

create function ledger.protect_materialized_claim_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    new.current_status_code is distinct from old.current_status_code
    or new.current_status_reason_short is distinct from old.current_status_reason_short
    or new.current_evaluation_run_id is distinct from old.current_evaluation_run_id
    or new.current_status_materialized_at is distinct from old.current_status_materialized_at
  ) and coalesce(current_setting('ledger.materializing_current_status', true), 'off') <> 'on' then
    raise exception 'current_status fields are derived cache values; insert a new evaluation result';
  end if;

  return new;
end;
$$;

create function audit.record_evaluation_result_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_claim_id text;
  target_prior_run_id uuid;
  target_actor_id uuid;
  prior_state jsonb;
begin
  select claim_id, prior_run_id, evaluated_by
  into target_claim_id, target_prior_run_id, target_actor_id
  from ledger.evaluation_runs
  where id = new.run_id;

  select jsonb_build_object(
    'status_code', status_code,
    'status_reason_code', status_reason_code,
    'status_reason_short', status_reason_short,
    'fact_support_final_score', fact_support_final_score,
    'readiness_final_score', readiness_final_score
  )
  into prior_state
  from ledger.evaluation_results
  where run_id = target_prior_run_id;

  insert into audit.evaluation_events (
    claim_id,
    run_id,
    prior_run_id,
    event_type,
    before_state,
    after_state,
    change_reason,
    actor_id
  )
  values (
    target_claim_id,
    new.run_id,
    target_prior_run_id,
    case when target_prior_run_id is null then 'INITIAL_EVALUATION' else 'REEVALUATION' end,
    prior_state,
    jsonb_build_object(
      'status_code', new.status_code,
      'status_reason_code', new.status_reason_code,
      'status_reason_short', new.status_reason_short,
      'fact_support_final_score', new.fact_support_final_score,
      'readiness_final_score', new.readiness_final_score,
      'decisive_gate_code', new.decisive_gate_code,
      'failed_gate_codes', new.failed_gate_codes
    ),
    new.status_reason_short,
    target_actor_id
  );

  return new;
end;
$$;

create trigger validate_evaluation_result_before_insert
before insert on ledger.evaluation_results
for each row execute function ledger.validate_evaluation_result();

create trigger validate_factor_score_before_write
before insert or update on ledger.evaluation_factor_scores
for each row execute function ledger.validate_factor_score();

create trigger validate_gate_result_before_write
before insert or update on ledger.evaluation_gate_results
for each row execute function ledger.validate_gate_result_input();

create trigger protect_materialized_claim_status_before_update
before update on ledger.claims
for each row execute function ledger.protect_materialized_claim_status();

create trigger materialize_current_claim_status_after_insert
after insert on ledger.evaluation_results
for each row execute function ledger.materialize_current_claim_status();

create trigger record_evaluation_result_event_after_insert
after insert on ledger.evaluation_results
for each row execute function audit.record_evaluation_result_event();

create trigger evaluation_results_append_only
before update or delete on ledger.evaluation_results
for each row execute function audit.reject_mutation();

create trigger methodologies_append_only
before update or delete on ledger.methodologies
for each row execute function audit.reject_mutation();

create trigger evaluation_runs_append_only
before update or delete on ledger.evaluation_runs
for each row execute function audit.reject_mutation();

create trigger evaluation_dimensions_append_only
before update or delete on ledger.evaluation_dimensions
for each row execute function audit.reject_mutation();

create trigger evaluation_criteria_append_only
before update or delete on ledger.evaluation_criteria
for each row execute function audit.reject_mutation();

create trigger methodology_gates_append_only
before update or delete on ledger.methodology_gates
for each row execute function audit.reject_mutation();

create trigger evidence_append_only
before update or delete on ledger.evidence
for each row execute function audit.reject_mutation();

create trigger web_snapshots_append_only
before update or delete on ledger.web_snapshots
for each row execute function audit.reject_mutation();

create trigger finalized_factor_scores_immutable
before insert or update or delete on ledger.evaluation_factor_scores
for each row execute function audit.reject_finalized_run_mutation();

create trigger finalized_gate_results_immutable
before insert or update or delete on ledger.evaluation_gate_results
for each row execute function audit.reject_finalized_run_mutation();

create trigger finalized_evidence_links_immutable
before insert or update or delete on ledger.evaluation_evidence_links
for each row execute function audit.reject_finalized_run_mutation();

create trigger finalized_missing_evidence_links_immutable
before insert or update or delete on ledger.evaluation_missing_evidence_links
for each row execute function audit.reject_finalized_run_mutation();

create trigger finalized_assumptions_immutable
before insert or update or delete on ledger.evaluation_assumptions
for each row execute function audit.reject_finalized_run_mutation();

create trigger evaluation_events_append_only
before update or delete on audit.evaluation_events
for each row execute function audit.reject_mutation();

create trigger export_events_append_only
before update or delete on audit.export_events
for each row execute function audit.reject_mutation();

create view ledger.evaluation_result_timeline
with (security_invoker = true)
as
select
  er.claim_id,
  er.id as evaluation_run_id,
  res.id as evaluation_result_id,
  res.status_code,
  res.status_label,
  res.status_reason_code,
  res.status_reason_short,
  er.evaluated_at as valid_from,
  lead(er.evaluated_at) over (
    partition by er.claim_id
    order by er.evaluated_at, er.id
  ) as valid_to,
  er.methodology_id,
  er.engine_version,
  er.human_review_status
from ledger.evaluation_runs er
join ledger.evaluation_results res on res.run_id = er.id;

create view ledger.current_evaluation_export_rows
with (security_invoker = true)
as
select
  c.id as claim_id,
  c.claim_text,
  res.status_code,
  res.status_label,
  res.status_reason_code,
  res.status_reason_short,
  res.fact_support_final_score,
  res.readiness_final_score,
  res.failed_gate_codes,
  res.passed_gate_codes,
  res.missing_evidence_codes,
  res.conditional_assumptions,
  res.highest_evidence_grade,
  res.evidence_count,
  res.contradicting_evidence_count,
  er.calculation_type,
  m.version as methodology_version,
  er.engine_version,
  er.evaluated_at,
  er.human_review_status
from ledger.claims c
join ledger.evaluation_runs er on er.id = c.current_evaluation_run_id
join ledger.evaluation_results res on res.run_id = er.id
join ledger.methodologies m on m.id = er.methodology_id;

alter table ledger.claims enable row level security;
alter table ledger.evidence enable row level security;
alter table private.evidence_locations enable row level security;
alter table ledger.evidence_requests enable row level security;
alter table ledger.methodologies enable row level security;
alter table ledger.evaluation_dimensions enable row level security;
alter table ledger.evaluation_criteria enable row level security;
alter table ledger.methodology_gates enable row level security;
alter table ledger.evaluation_runs enable row level security;
alter table ledger.evaluation_factor_scores enable row level security;
alter table ledger.evaluation_gate_results enable row level security;
alter table ledger.evaluation_results enable row level security;
alter table ledger.evaluation_evidence_links enable row level security;
alter table ledger.evaluation_missing_evidence_links enable row level security;
alter table ledger.evaluation_assumptions enable row level security;
alter table ledger.web_snapshots enable row level security;
alter table audit.evaluation_events enable row level security;
alter table audit.export_events enable row level security;

comment on schema ledger is 'K-DATA 판정, 증거, 산식 및 확보요청 데이터';
comment on schema audit is '덮어쓰지 않는 판정 및 CSV 반출 이력';
comment on schema private is '공개하지 않는 원본 위치와 민감 메타데이터';
comment on column ledger.claims.current_status_code is '최신 평가 결과에서 자동 materialize된 화면·CSV용 캐시';
comment on column ledger.claims.current_status_reason_short is '최신 평가 결과에서 자동 materialize된 짧은 근거';
comment on column ledger.evaluation_results.status_reason_short is 'CSV와 UI에 항상 표시하는 간단한 판정 근거';
comment on column ledger.evaluation_results.formula_snapshot is '평가 당시 정의·산식·상한 규칙의 불변 스냅샷';
comment on view ledger.evaluation_result_timeline is 'append-only 평가 결과로부터 유효 시작·종료 시점을 계산한 이력';
comment on view ledger.current_evaluation_export_rows is '현재 판정 CSV의 최소 설명가능 컬럼 계약';

commit;
