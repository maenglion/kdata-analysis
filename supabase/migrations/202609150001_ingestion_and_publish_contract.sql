begin;

-- This migration records the ingestion schema in Git. It is not executed by the
-- collector and must be applied only after read-only drift comparison/approval.

create schema if not exists publish;
revoke all on schema publish from public, anon, authenticated;

create table if not exists ledger.ingest_batches (
  id uuid primary key default gen_random_uuid(),
  parser_name text not null,
  parser_version text not null,
  source_filename text not null,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_row_count integer not null default 0 check (source_row_count >= 0),
  source_scope text not null,
  content_contract text not null,
  source_evidence_id text references ledger.evidence(id) on delete restrict,
  notes text,
  ingested_at timestamptz not null default now()
);

create table if not exists ledger.parsed_claim_units (
  id uuid primary key default gen_random_uuid(),
  ingest_batch_id uuid not null references ledger.ingest_batches(id) on delete restrict,
  source_evidence_id text references ledger.evidence(id) on delete restrict,
  legacy_unit_id text,
  source_row_number integer not null check (source_row_number > 0),
  document_code text,
  document_date date,
  recipient text,
  section_locator text,
  author_name text,
  channel text,
  frame_codes jsonb not null default '[]'::jsonb check (jsonb_typeof(frame_codes) = 'array'),
  expression_strength text,
  signal_codes jsonb not null default '[]'::jsonb check (jsonb_typeof(signal_codes) = 'array'),
  source_text text not null,
  created_at timestamptz not null default now(),
  unique (ingest_batch_id, source_row_number)
);

create table if not exists ledger.organization_snapshots (
  id uuid primary key default gen_random_uuid(),
  ingest_batch_id uuid not null references ledger.ingest_batches(id) on delete restrict,
  observed_on date not null,
  source_url text not null,
  archive_url text,
  source_container_evidence_id text references ledger.evidence(id) on delete restrict,
  source_hash_scope text not null,
  normalized_rows_sha256 text not null check (normalized_rows_sha256 ~ '^[0-9a-f]{64}$'),
  source_limitation text,
  created_at timestamptz not null default now()
);

create table if not exists ledger.organization_assignments (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references ledger.organization_snapshots(id) on delete restrict,
  person_name text,
  department_name text not null,
  role_title text,
  duties text,
  source_locator text,
  normalized_row_sha256 text not null check (normalized_row_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique (snapshot_id, normalized_row_sha256)
);

create table if not exists ledger.document_projections (
  id uuid primary key default gen_random_uuid(),
  ingest_batch_id uuid not null references ledger.ingest_batches(id) on delete restrict,
  source_evidence_id text references ledger.evidence(id) on delete restrict,
  document_id text not null,
  institution_id text not null,
  source_id text not null,
  publish_contract text not null,
  runtime_contract text not null,
  parser_version text not null,
  source_sha256 text not null check (source_sha256 ~ '^[0-9a-f]{64}$'),
  normalized_text_sha256 text check (normalized_text_sha256 is null or normalized_text_sha256 ~ '^[0-9a-f]{64}$'),
  projection_sha256 text not null check (projection_sha256 ~ '^[0-9a-f]{64}$'),
  detected_format text not null,
  protection_status text not null,
  extraction_status text not null,
  extraction_confidence numeric(6,3) check (extraction_confidence between 0 and 100),
  extraction_confidence_factors jsonb not null default '[]'::jsonb
    check (jsonb_typeof(extraction_confidence_factors) = 'array'),
  unit_count integer not null check (unit_count >= 0),
  projection_payload jsonb not null check (jsonb_typeof(projection_payload) = 'object'),
  is_public boolean not null default false,
  generated_at timestamptz not null default now(),
  unique (institution_id, source_id, source_sha256, parser_version),
  unique (projection_sha256)
);

create index if not exists parsed_claim_units_batch_idx
  on ledger.parsed_claim_units (ingest_batch_id, source_row_number);
create index if not exists organization_snapshots_observed_idx
  on ledger.organization_snapshots (observed_on, id);
create index if not exists document_projections_source_idx
  on ledger.document_projections (institution_id, source_id, generated_at desc);

alter table ledger.ingest_batches enable row level security;
alter table ledger.parsed_claim_units enable row level security;
alter table ledger.organization_snapshots enable row level security;
alter table ledger.organization_assignments enable row level security;
alter table ledger.document_projections enable row level security;

create or replace function ledger.reject_ingestion_history_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, ledger
as $$
begin
  raise exception '% is append-only; create a new ingestion/projection row instead', tg_table_schema || '.' || tg_table_name
    using errcode = '55000';
end;
$$;

drop trigger if exists protect_ingest_batches_history on ledger.ingest_batches;
create trigger protect_ingest_batches_history
before update or delete on ledger.ingest_batches
for each row execute function ledger.reject_ingestion_history_mutation();

drop trigger if exists protect_parsed_claim_units_history on ledger.parsed_claim_units;
create trigger protect_parsed_claim_units_history
before update or delete on ledger.parsed_claim_units
for each row execute function ledger.reject_ingestion_history_mutation();

drop trigger if exists protect_organization_snapshots_history on ledger.organization_snapshots;
create trigger protect_organization_snapshots_history
before update or delete on ledger.organization_snapshots
for each row execute function ledger.reject_ingestion_history_mutation();

drop trigger if exists protect_organization_assignments_history on ledger.organization_assignments;
create trigger protect_organization_assignments_history
before update or delete on ledger.organization_assignments
for each row execute function ledger.reject_ingestion_history_mutation();

drop trigger if exists protect_document_projections_history on ledger.document_projections;
create trigger protect_document_projections_history
before update or delete on ledger.document_projections
for each row execute function ledger.reject_ingestion_history_mutation();

revoke all on ledger.ingest_batches from anon, authenticated;
revoke all on ledger.parsed_claim_units from anon, authenticated;
revoke all on ledger.organization_snapshots from anon, authenticated;
revoke all on ledger.organization_assignments from anon, authenticated;
revoke all on ledger.document_projections from anon, authenticated;

create or replace view publish.public_document_index
with (security_invoker = true)
as
select
  p.document_id,
  p.institution_id,
  p.source_id,
  p.publish_contract,
  p.parser_version,
  p.source_sha256,
  p.normalized_text_sha256,
  p.projection_sha256,
  p.detected_format,
  p.protection_status,
  p.extraction_status,
  p.extraction_confidence,
  p.extraction_confidence_factors,
  p.unit_count,
  p.generated_at
from ledger.document_projections p
where p.is_public = true;

create or replace view publish.approved_current_evaluations
with (security_invoker = true)
as
select export_row.*
from ledger.current_evaluation_export_rows export_row
join ledger.claims claim on claim.id = export_row.claim_id
where claim.is_public = true
  and export_row.human_review_status = 'approved';

revoke all on publish.public_document_index from public, anon, authenticated;
revoke all on publish.approved_current_evaluations from public, anon, authenticated;

comment on schema publish is
  'Deterministic, approved projections only. No raw text, PII, local paths, or credentials.';
comment on table ledger.document_projections is
  'Append-only parser projection records. Public exposure requires is_public plus an explicit later RLS policy and grant.';

commit;
