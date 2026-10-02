-- A person has at most one line 1 (and so exactly one row per person and line number).
select person_id, line_number, count(*) as n_rows
from {{ ref('int_lines_of_therapy') }}
where line_number = 1
group by person_id, line_number
having count(*) > 1
