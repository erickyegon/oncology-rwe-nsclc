-- Main analysis cohort: staged NSCLC (histology and stage from source codes), age >= min_age_at_dx at diagnosis,
-- all diagnosis years, follow-up censored at followup_cap_months. One row per person.
-- Follow-up: index date to death (event) or to the end of the observation period (censored), in months.
with base as (
    select
        dx.person_id,
        dx.index_date,
        p.sex,
        sh.stage,
        d.death_date,
        (dx.index_date - p.birth_date) / {{ var('days_per_year') }}::numeric as age_exact,
        greatest((coalesce(d.death_date, op.observation_end_date) - dx.index_date), 0)
            / {{ var('days_per_month') }}::numeric                          as followup_months_raw
    from {{ ref('int_lung_cancer_dx') }} dx
    join {{ ref('int_stage_histology') }} sh using (person_id)
    join {{ ref('stg_person') }} p using (person_id)
    join {{ ref('stg_observation_period') }} op using (person_id)
    left join {{ ref('stg_death') }} d using (person_id)
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
                                      and {{ var('sensitivity_end_year') }} as dx_2010_2015
from base
where age_exact >= {{ var('min_age_at_dx') }}
