{{ config(materialized='table') }}
-- Prior other cancer, one row per person with a lung cancer diagnosis. A flag for analysis, never an exclusion.
-- prior_other_cancer is true if, strictly before the lung cancer index date, the person had any of:
--   * an anticancer drug administration (ATC L01/L02 ingredient, see int_anticancer_exposures);
--   * a chemotherapy or radiation procedure (var anticancer_procedure_codes);
--   * a diagnosis of a malignant neoplasm other than lung cancer (descendant of SNOMED 'Malignant neoplastic disease',
--     excluding the lung cancer source codes).
-- Set-based on purpose: the malignancy concepts are resolved once through the ancestor index, not per person.
with dx as (
    select person_id, index_date from {{ ref('int_lung_cancer_dx') }}
),
malignancy_concepts as (
    select descendant_concept_id as concept_id
    from {{ source('cdm', 'concept_ancestor') }}
    where ancestor_concept_id = {{ var('malignant_neoplasm_concept_id') }}
),
drug as (
    select distinct dx.person_id
    from dx join {{ ref('int_anticancer_exposures') }} a on a.person_id = dx.person_id and a.administration_date < dx.index_date
),
procedure as (
    select distinct dx.person_id
    from dx join {{ ref('stg_procedure_occurrence') }} p on p.person_id = dx.person_id and p.procedure_date < dx.index_date
    where p.procedure_source_value in ({% for c in var('anticancer_procedure_codes') %}'{{ c }}'{% if not loop.last %}, {% endif %}{% endfor %})
),
malignancy as (
    select distinct dx.person_id
    from dx
    join {{ ref('stg_condition_occurrence') }} c on c.person_id = dx.person_id and c.condition_start_date < dx.index_date
    join malignancy_concepts m on m.concept_id = c.condition_concept_id
    where c.condition_source_value not in (select source_code from {{ ref('int_lung_cancer_codes') }})
)
select
    dx.person_id,
    (drug.person_id is not null)                                                                  as prior_anticancer_drug,
    (procedure.person_id is not null)                                                             as prior_chemo_radiation_procedure,
    (malignancy.person_id is not null)                                                            as prior_other_malignancy_dx,
    (drug.person_id is not null or procedure.person_id is not null or malignancy.person_id is not null) as prior_other_cancer
from dx
left join drug      on drug.person_id      = dx.person_id
left join procedure on procedure.person_id = dx.person_id
left join malignancy on malignancy.person_id = dx.person_id
