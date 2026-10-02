-- One row per person who died (Synthea death date, mapped by ETL-Synthea).
select person_id, death_date
from {{ source('cdm', 'death') }}
