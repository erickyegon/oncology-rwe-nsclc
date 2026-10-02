-- One row per person. Sex from the OMOP gender concept (8507 male, 8532 female).
select
    person_id,
    person_source_value,
    case gender_concept_id when 8507 then 'M' when 8532 then 'F' else 'U' end as sex,
    coalesce(birth_datetime::date,
             make_date(year_of_birth, coalesce(month_of_birth, 1), coalesce(day_of_birth, 1))) as birth_date
from {{ source('cdm', 'person') }}
