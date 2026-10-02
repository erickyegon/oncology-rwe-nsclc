{{ config(materialized='table') }}
-- Administrations of the NSCLC-directed drugs (var nsclc_systemic_ingredients) on or after the person's lung cancer
-- index date. Other cancers' regimens (for example docetaxel with leuprolide) and anything before diagnosis are excluded.
select
    a.person_id,
    a.administration_date,
    a.ingredient
from {{ ref('int_anticancer_exposures') }} a
join {{ ref('int_lung_cancer_dx') }} dx on dx.person_id = a.person_id
where a.ingredient in ({% for x in var('nsclc_systemic_ingredients') %}'{{ x | lower }}'{% if not loop.last %}, {% endif %}{% endfor %})
  and a.administration_date >= dx.index_date
