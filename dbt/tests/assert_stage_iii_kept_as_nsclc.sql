-- Regression test for the Athena v20260829 mapping problem: SNOMED 422968005 (NSCLC, TNM stage 3) also maps to the
-- standard concept 'Small cell carcinoma of lung'. Anyone with that source code must be classified NSCLC, stage III.
select s.person_id, s.histology, s.stage
from {{ ref('int_stage_histology') }} s
where s.person_id in (
        select person_id from {{ ref('stg_condition_occurrence') }} where condition_source_value = '422968005')
  and (s.histology <> 'NSCLC' or s.stage is distinct from 'III')
