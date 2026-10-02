{{ config(materialized='table') }}
-- Rule-based lines of therapy, one row per person and line, from administrations of the NSCLC-directed drugs on or
-- after diagnosis (int_nsclc_systemic_administrations).
--   * A new line starts at the first administration, and again after a gap of MORE than var line_gap_days (default 90)
--     between consecutive administration dates (a restart after the gap is the next line).
--   * A new drug on its own never starts a line.
--   * The line's regimen is the set of drugs administered within var line_window_days (default 28) of the line start.
-- Both thresholds are dbt variables, so sensitivity runs need no code change:  dbt run --vars '{line_gap_days: 60}'
with dates as (
    select distinct person_id, administration_date
    from {{ ref('int_nsclc_systemic_administrations') }}
),
gaps as (
    select
        person_id,
        administration_date,
        administration_date - lag(administration_date) over (partition by person_id order by administration_date) as days_since_previous
    from dates
),
numbered as (
    select
        person_id,
        administration_date,
        days_since_previous,
        sum(case when days_since_previous is null or days_since_previous > {{ var('line_gap_days') }} then 1 else 0 end)
            over (partition by person_id order by administration_date rows unbounded preceding) as line_number
    from gaps
),
lines as (
    select
        person_id,
        line_number,
        min(administration_date)                                         as line_start_date,
        max(administration_date)                                         as line_end_date,
        count(*)                                                         as n_administration_dates,
        (array_agg(days_since_previous order by administration_date))[1] as gap_before_days
    from numbered
    group by person_id, line_number
),
regimens as (
    select
        l.person_id,
        l.line_number,
        string_agg(distinct a.ingredient, ' + ' order by a.ingredient) as regimen
    from lines l
    join numbered n on n.person_id = l.person_id and n.line_number = l.line_number
    join {{ ref('int_nsclc_systemic_administrations') }} a
         on a.person_id = n.person_id and a.administration_date = n.administration_date
    where n.administration_date <= l.line_start_date + {{ var('line_window_days') }}
    group by l.person_id, l.line_number
)
select
    l.person_id,
    l.line_number,
    l.line_start_date,
    l.line_end_date,
    l.n_administration_dates,
    l.gap_before_days,
    r.regimen
from lines l
join regimens r using (person_id, line_number)
