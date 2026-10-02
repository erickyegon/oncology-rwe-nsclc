-- One observation period per person; its end date is the last recorded activity (used to censor survivors).
select
    person_id,
    min(observation_period_start_date) as observation_start_date,
    max(observation_period_end_date)   as observation_end_date
from {{ source('cdm', 'observation_period') }}
group by person_id
