begin;

insert into ledger.methodologies (
  code,
  version,
  name,
  description,
  effective_from,
  formula_definition
)
values (
  'KDATA_CLAIM_EVAL',
  '1.0.0',
  'K-DATA 사실주장 설명가능 판정 방법론',
  '점수는 사실지지와 판정준비도 분석축으로만 사용하고, 최종 6단계 상태는 증거조건과 게이트를 우선 적용한다.',
  '2026-09-12T00:00:00+09:00'::timestamptz,
  jsonb_build_object(
    'fact_support_score', jsonb_build_object(
      'raw_formula', 'sum(input_score * weight / 100)',
      'final_formula', 'raw_score; v1.0.0에서는 게이트가 사실지지점수를 변경하지 않고 상태와 판정가능도만 제한',
      'meaning', '주변 사실과 증거가 해당 주장을 지지하는 정도; 최종 상태와 동일하지 않음',
      'levels', jsonb_build_object(
        '95-100', '거의 확실',
        '80-94', '강하게 지지',
        '60-79', '개연성 있음',
        '40-59', '판단 유보',
        '20-39', '가능성 낮음',
        '0-19', '기각',
        'unscored', '미산정'
      )
    ),
    'readiness_score', jsonb_build_object(
      'raw_formula', 'sum(input_score * weight / 100)',
      'final_formula', 'min(raw_score, all failed gate score_caps)',
      'meaning', '현재 기록만으로 제3자가 판정을 재현할 준비 정도'
    ),
    'status_resolution', jsonb_build_object(
      'order', jsonb_build_array('unassessed', 'contradicted', 'insufficient', 'conditional', 'supported', 'confirmed'),
      'rule', 'gate-first',
      'effect_precedence', jsonb_build_array('BLOCK', 'CAP', 'INFO'),
      'multiple_cap_rule', '가장 낮은 허용상태를 만드는 CAP 우선; 동률은 gate_priority 우선',
      'block', '실패 시 불충분 상한',
      'cap', '실패 게이트의 status_cap 이하만 허용',
      'info', '상태를 제한하지 않고 설명에 포함'
    )
  )
)
on conflict (code, version) do nothing;

with methodology as (
  select id
  from ledger.methodologies
  where code = 'KDATA_CLAIM_EVAL' and version = '1.0.0'
)
insert into ledger.evaluation_dimensions (
  methodology_id,
  code,
  name,
  weight_total,
  display_order
)
select methodology.id, valueset.code, valueset.name, 100, valueset.display_order
from methodology
cross join (
  values
    ('fact_support', '사실지지점수', 1),
    ('readiness', '판정가능도', 2)
) as valueset(code, name, display_order)
on conflict (methodology_id, code) do nothing;

with dimensions as (
  select ed.id, ed.code
  from ledger.evaluation_dimensions ed
  join ledger.methodologies m on m.id = ed.methodology_id
  where m.code = 'KDATA_CLAIM_EVAL' and m.version = '1.0.0'
), criteria(dimension_code, code, name, definition, weight, display_order) as (
  values
    ('fact_support', 'FS-01', '직접성', '주장을 직접 입증하는 정도', 20::numeric, 1),
    ('fact_support', 'FS-02', '출처 신뢰성·진본성', '공식 원문 또는 검증된 사본인지', 20::numeric, 2),
    ('fact_support', 'FS-03', '주장 적합성', '증거가 해당 주장과 정확히 맞물리는지', 15::numeric, 3),
    ('fact_support', 'FS-04', '독립 교차확인', '공통 기원이 아닌 독립 근거가 지지하는지', 15::numeric, 4),
    ('fact_support', 'FS-05', '시간 정합성', '관련 시점에 생성된 기록인지', 10::numeric, 5),
    ('fact_support', 'FS-06', '행위자 특정성', '담당자·부서·권한 주체가 특정되는지', 10::numeric, 6),
    ('fact_support', 'FS-07', '반대근거 처리', '상충자료와 대안해석을 식별·처리했는지', 10::numeric, 7),
    ('readiness', 'RD-01', '주장 구체성', '검증 가능한 단일 사실명제로 정의됐는지', 10::numeric, 1),
    ('readiness', 'RD-02', '필수사실 충족', '판정에 필요한 핵심 사실이 확보됐는지', 25::numeric, 2),
    ('readiness', 'RD-03', '출처 추적성', '증거번호와 원문 위치를 다시 찾을 수 있는지', 20::numeric, 3),
    ('readiness', 'RD-04', '행위자·행위·대상·시점 연결', '판단요소가 하나의 기록 사슬로 연결되는지', 20::numeric, 4),
    ('readiness', 'RD-05', '반론 처리', '직접 반론과 다른 해석을 검토했는지', 15::numeric, 5),
    ('readiness', 'RD-06', '제3자 재현성', '동일 입력으로 제3자가 판정을 재현할 수 있는지', 10::numeric, 6)
)
insert into ledger.evaluation_criteria (
  dimension_id,
  code,
  name,
  definition,
  weight,
  display_order
)
select d.id, c.code, c.name, c.definition, c.weight, c.display_order
from criteria c
join dimensions d on d.code = c.dimension_code
on conflict (dimension_id, code) do nothing;

with methodology as (
  select id
  from ledger.methodologies
  where code = 'KDATA_CLAIM_EVAL' and version = '1.0.0'
), gates(code, name, definition, effect, score_cap, status_cap, is_core, gate_priority, display_order) as (
  values
    ('G-01', '증거 식별·원문 위치', '증거번호 또는 원문 위치가 없어 제3자가 근거를 재확인할 수 없음', 'BLOCK', 39::numeric, 'insufficient', true, 10, 1),
    ('G-02', '핵심 인과 연결', '주장과 결과 사이의 핵심 인과 연결기록이 없음', 'BLOCK', 59::numeric, 'insufficient', true, 20, 2),
    ('G-03', '권한·행위자 직접기록', '관련 시점의 권한표·담당자·접근로그 등 직접기록이 없음', 'BLOCK', 59::numeric, 'insufficient', true, 30, 3),
    ('G-04', '직접 상충근거 해소', '주장을 직접 부정하는 자료 또는 대안해석이 해소되지 않음', 'BLOCK', 49::numeric, 'insufficient', true, 40, 4),
    ('G-05', '원출처 증거', 'AI 출력 또는 2차 정리만 있고 원출처 증거가 없음', 'BLOCK', 39::numeric, 'insufficient', true, 50, 5),
    ('G-06', '관련 시점 적용성', '규정·업무분장·권한이 해당 시점에도 적용됐는지 불명확함', 'BLOCK', 59::numeric, 'insufficient', true, 60, 6),
    ('G-07', '중복·공통기원 제거', '중복 또는 공통기원 증거를 독립 근거처럼 계산하여 재산정이 필요함', 'BLOCK', 59::numeric, 'insufficient', true, 70, 7),
    ('G-08', '확정용 직접증거', '직접증거가 부족하여 확정에는 이르지 못하지만 핵심 사실은 지지될 수 있음', 'CAP', null::numeric, 'supported', true, 80, 8),
    ('G-09', '조건 전제 해소', '명시된 조건 또는 전제가 해소되지 않아 조건부 이상으로 올릴 수 없음', 'CAP', null::numeric, 'conditional', false, 90, 9)
)
insert into ledger.methodology_gates (
  methodology_id,
  code,
  name,
  definition,
  effect,
  score_cap,
  status_cap,
  is_core,
  gate_priority,
  display_order
)
select methodology.id, gates.code, gates.name, gates.definition, gates.effect,
       gates.score_cap, gates.status_cap, gates.is_core, gates.gate_priority, gates.display_order
from methodology
cross join gates
on conflict (methodology_id, code) do nothing;

commit;
