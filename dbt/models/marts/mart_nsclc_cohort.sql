-- Main analysis cohort: staged NSCLC (histology and stage from source codes), age >= min_age_at_dx at diagnosis,
-- all diagnosis years, follow-up censored at followup_cap_months. One row per person.
-- Follow-up: index date to death (event) or to the end of the observation period (censored), in months.
-- Time to next treatment (ttnt): from the start of line 1 to the start of line 2 or death, whichever is first, censored at
-- the end of the observation period, in months (capped like follow-up); null for the person with no line 1 (no recorded
-- NSCLC-directed treatment). prior_other_cancer is a flag only (see int_prior_cancer); nobody is excluded on it.
with base as (
    select
        dx.person_id,
        dx.index_date,
        p.sex,
        sh.stage,
        d.death_date,
        (dx.index_date - p.birth_date) / {{ var('days_per_year') }}::numeric as age_exact,
        greatest((coalesce(d.death_date, op.observation_end_date) - dx.index_date), 0)
            / {{ var('days_per_month') }}::numeric                          as followup_months_raw,
        coalesce(pc.prior_other_cancer, false)                              as prior_other_cancer,
        ln.line1_start,
        least(ln.line2_start, d.death_date)                                 as ttnt_event_date,
        greatest((coalesce(least(ln.line2_start, d.death_date), op.observation_end_date) - ln.line1_start), 0)
            / {{ var('days_per_month') }}::numeric                          as ttnt_months_raw
    from {{ ref('int_lung_cancer_dx') }} dx
    join {{ ref('int_stage_histology') }} sh using (person_id)
    join {{ ref('stg_person') }} p using (person_id)
    join {{ ref('stg_observation_period') }} op using (person_id)
    left join {{ ref('stg_death') }} d using (person_id)
    left join {{ ref('int_prior_cancer') }} pc using (person_id)
    left join (
        select person_id,
               min(line_start_date) filter (where line_number = 1) as line1_start,
               min(line_start_date) filter (where line_number = 2) as line2_start
        from {{ ref('int_lines_of_therapy') }}
        group by person_id
    ) ln using (person_id)
    where sh.histology = 'NSCLC'
      and sh.stage is not null
)
select
    person_id,
    index_date,
    round(age_exact, 2)                                                     as age_at_dx,
    sex,
    stage,
    death_date,
    round(least(followup_months_raw, {{ var('followup_cap_months') }})::numeric, 3) as followup_months,
    (death_date is not null and followup_months_raw <= {{ var('followup_cap_months') }})::int as event,
    (followup_months_raw > {{ var('followup_cap_months') }})                as censored_at_120,
    extract(year from index_date) between {{ var('sensitivity_start_year') }}
                                      and {{ var('sensitivity_end_year') }} as dx_2010_2015,
    prior_other_cancer,
    case when line1_start is not null
         then round(least(ttnt_months_raw, {{ var('followup_cap_months') }})::numeric, 3) end as ttnt_months,
    case when line1_start is not null
         then (ttnt_event_date is not null and ttnt_months_raw <= {{ var('followup_cap_months') }})::int end as ttnt_event
from base
where age_exact >= {{ var('min_age_at_dx') }}
