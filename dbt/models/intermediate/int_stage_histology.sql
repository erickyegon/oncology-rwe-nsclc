-- One row per person with a lung cancer diagnosis: histology (NSCLC vs small cell) and TNM stage, from the
-- source codes. stage is null when the person has no stage code or conflicting stage codes.
with per_person as (
    select
        c.person_id,
        bool_or(k.histology = 'NSCLC') as has_nsclc_code,
        bool_or(k.histology = 'SCLC')  as has_sclc_code,
        count(distinct k.stage)        as n_distinct_stages,
        min(k.stage)                   as any_stage
    from {{ ref('stg_condition_occurrence') }} c
    join {{ ref('int_lung_cancer_codes') }} k on k.source_code = c.condition_source_value
    group by c.person_id
)
select
    person_id,
    case when has_nsclc_code and not has_sclc_code then 'NSCLC'
         when has_sclc_code and not has_nsclc_code then 'SCLC'
         else 'MIXED' end                               as histology,
    case when n_distinct_stages = 1 then any_stage end  as stage,
    n_distinct_stages
from per_person
