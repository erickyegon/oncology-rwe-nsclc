-- A death date, when present, must be on or after the index date (no death before diagnosis).
select person_id, index_date, death_date
from {{ ref('mart_nsclc_cohort') }}
where death_date is not null
  and death_date < index_date
