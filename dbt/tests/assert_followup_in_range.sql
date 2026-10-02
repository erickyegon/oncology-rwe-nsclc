-- Follow-up must lie between 0 and the 120-month cap. Returns offending rows (a passing test returns none).
select person_id, followup_months
from {{ ref('mart_nsclc_cohort') }}
where followup_months < 0
   or followup_months > {{ var('followup_cap_months') }}
