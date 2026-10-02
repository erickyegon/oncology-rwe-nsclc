-- Condition rows, unchanged apart from column selection. NOTE: a source code that maps to more than one standard
-- concept appears once per concept (e.g. SNOMED 422968005 appears twice), so downstream models work on
-- condition_source_value and aggregate per person; they never use condition_concept_id to identify histology.
select
    condition_occurrence_id,
    person_id,
    condition_start_date,
    condition_source_value,
    condition_source_concept_id,
    condition_concept_id,
    visit_occurrence_id
from {{ source('cdm', 'condition_occurrence') }}
