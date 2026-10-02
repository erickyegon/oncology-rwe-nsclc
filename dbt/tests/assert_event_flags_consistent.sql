-- event, death_date and censored_at_120 must agree: an event needs a death date and is never administratively censored;
-- censored_at_120 means follow-up was truncated at the cap; a person with a death date but no event must be censored_at_120.
select person_id, event, death_date, censored_at_120, followup_months
from {{ ref('mart_nsclc_cohort') }}
where (event = 1 and death_date is null)
   or (event = 1 and censored_at_120)
   or (event = 0 and death_date is not null and not censored_at_120)
   or (censored_at_120 and followup_months <> {{ var('followup_cap_months') }})
