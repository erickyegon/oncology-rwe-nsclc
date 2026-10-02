-- Cohort flow (attrition) table for the report: how many people remain after each rule.
select 1 as step_order, 'People in the OMOP CDM (lung cancer export)' as step, count(*) as n_persons
from {{ ref('stg_person') }}
union all
select 2, 'With a lung cancer diagnosis code', count(*) from {{ ref('int_lung_cancer_dx') }}
union all
select 3, 'Excluded: small cell (source code)', count(*) from {{ ref('int_stage_histology') }} where histology <> 'NSCLC'
union all
select 4, 'NSCLC (source code)', count(*) from {{ ref('int_stage_histology') }} where histology = 'NSCLC'
union all
select 5, 'Excluded: NSCLC without a single TNM stage code', count(*)
from {{ ref('int_stage_histology') }} where histology = 'NSCLC' and stage is null
union all
select 6, 'Staged NSCLC', count(*) from {{ ref('int_stage_histology') }} where histology = 'NSCLC' and stage is not null
union all
select 7, 'Excluded: age at diagnosis under {{ var("min_age_at_dx") }}',
       (select count(*) from {{ ref('int_stage_histology') }} where histology = 'NSCLC' and stage is not null)
       - (select count(*) from {{ ref('mart_nsclc_cohort') }})
union all
select 8, 'Main analysis cohort', count(*) from {{ ref('mart_nsclc_cohort') }}
union all
select 9, 'Sensitivity cohort (diagnosed 2010-2015)', count(*) from {{ ref('mart_nsclc_cohort') }} where dx_2010_2015
order by step_order
