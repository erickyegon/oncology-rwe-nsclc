-- Line numbers must be consecutive 1..n within a person, with each line starting after the previous one ended.
with per_person as (
    select person_id, min(line_number) as first_line, max(line_number) as last_line, count(*) as n_lines
    from {{ ref('int_lines_of_therapy') }}
    group by person_id
),
out_of_order as (
    select person_id
    from (
        select person_id, line_start_date,
               lag(line_end_date) over (partition by person_id order by line_number) as previous_line_end
        from {{ ref('int_lines_of_therapy') }}
    ) x
    where previous_line_end is not null and line_start_date <= previous_line_end
)
select person_id, first_line, last_line, n_lines
from per_person
where first_line <> 1 or last_line <> n_lines
union all
select person_id, null, null, null from out_of_order
