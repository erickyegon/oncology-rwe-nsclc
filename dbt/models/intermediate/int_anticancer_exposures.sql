{{ config(materialized='table') }}
-- Anticancer drug administrations at ingredient level: ingredients under ATC L01 (antineoplastic) or L02 (endocrine
-- therapy), minus the preparations listed in var excluded_hormone_ingredients (contraceptives and hormone therapy
-- that sit under L02, and one ingredient with a stray L01 combination code). One row per person, date and ingredient.
with ingredients as (
    select distinct ing.concept_id as ingredient_concept_id, lower(ing.concept_name) as ingredient
    from {{ source('cdm', 'concept') }} ing
    join {{ source('cdm', 'concept_ancestor') }} a on a.descendant_concept_id = ing.concept_id
    join {{ source('cdm', 'concept') }} atc on atc.concept_id = a.ancestor_concept_id
    where ing.concept_class_id = 'Ingredient'
      and ing.vocabulary_id = 'RxNorm'
      and ing.standard_concept = 'S'
      and atc.vocabulary_id = 'ATC'
      and (atc.concept_code like 'L01%' or atc.concept_code like 'L02%')
      and lower(ing.concept_name) not in ({% for x in var('excluded_hormone_ingredients') %}'{{ x | lower }}'{% if not loop.last %}, {% endif %}{% endfor %})
)
select distinct
    de.person_id,
    de.drug_exposure_start_date as administration_date,
    i.ingredient
from {{ ref('stg_drug_exposure') }} de
join {{ source('cdm', 'concept_ancestor') }} ca on ca.descendant_concept_id = de.drug_concept_id
join ingredients i on i.ingredient_concept_id = ca.ancestor_concept_id
