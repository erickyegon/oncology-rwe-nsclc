-- No line of therapy may start before the person's lung cancer index date.
select l.person_id, l.line_number, l.line_start_date, dx.index_date
from {{ ref('int_lines_of_therapy') }} l
join {{ ref('int_lung_cancer_dx') }} dx using (person_id)
where l.line_start_date < dx.index_date
