-- One row per person with a lung cancer diagnosis. Index date = first recorded lung cancer diagnosis
-- (earliest start date over all lung cancer source codes, NSCLC or small cell).
select
    c.person_id,
    min(c.condition_start_date)    as index_date,
    bool_or(k.histology = 'NSCLC') as has_nsclc_code,
    bool_or(k.histology = 'SCLC')  as has_sclc_code
from {{ ref('stg_condition_occurrence') }} c
join {{ ref('int_lung_cancer_codes') }} k on k.source_code = c.condition_source_value
group by c.person_id
