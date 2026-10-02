-- No person in the NSCLC cohort may carry a small cell lung cancer source code (any of the SCLC SNOMED codes).
select distinct m.person_id, c.condition_source_value
from {{ ref('mart_nsclc_cohort') }} m
join {{ ref('stg_condition_occurrence') }} c on c.person_id = m.person_id
join {{ ref('int_lung_cancer_codes') }} k on k.source_code = c.condition_source_value
where k.histology = 'SCLC'
