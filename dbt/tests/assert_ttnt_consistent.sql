-- Time to next treatment: null together (months and event) exactly when the person has no line 1; otherwise within 0 and
-- the 120-month cap and never longer than follow-up; an event needs line 2 or a death.
with lines as (
    select person_id,
           min(line_start_date) filter (where line_number = 1) as line1_start,
           min(line_start_date) filter (where line_number = 2) as line2_start
    from {{ ref('int_lines_of_therapy') }}
    group by person_id
)
select m.person_id, m.ttnt_months, m.ttnt_event, m.followup_months, l.line1_start, l.line2_start, m.death_date
from {{ ref('mart_nsclc_cohort') }} m
left join lines l using (person_id)
where (l.line1_start is null and (m.ttnt_months is not null or m.ttnt_event is not null))
   or (l.line1_start is not null and (m.ttnt_months is null or m.ttnt_event is null))
   or m.ttnt_months < 0
   or m.ttnt_months > {{ var('followup_cap_months') }}
   or m.ttnt_months > m.followup_months + 0.001
   or (m.ttnt_event = 1 and l.line2_start is null and m.death_date is null)
