-- The hand-written source-code map (int_lung_cancer_codes) must agree with the SNOMED concept names in the loaded
-- vocabulary: NSCLC codes say 'Non-small cell', SCLC codes say 'small cell' (not 'Non-small'), and a staged code
-- names the same TNM stage digit. Returns codes that disagree or are missing from the vocabulary.
with expected as (
    select
        k.source_code, k.histology, k.stage,
        case k.stage when 'I' then '1' when 'II' then '2' when 'III' then '3' when 'IV' then '4' end as stage_digit
    from {{ ref('int_lung_cancer_codes') }} k
)
select e.source_code, e.histology, e.stage, c.concept_name
from expected e
left join {{ source('cdm', 'concept') }} c
       on c.vocabulary_id = 'SNOMED' and c.concept_code = e.source_code
where c.concept_id is null
   or (e.histology = 'NSCLC' and c.concept_name not ilike 'Non-small cell%')
   or (e.histology = 'SCLC' and (c.concept_name ilike 'Non-small%' or c.concept_name not ilike '%small cell%'))
   or (e.stage_digit is not null and c.concept_name not ilike '%stage ' || e.stage_digit || '%')
   or (e.stage_digit is null and c.concept_name ilike '%stage %')
