-- Drug exposure rows. Only the start date is used downstream: ETL-Synthea writes quantity as 0 and computes
-- days_supply as stop minus start, so neither is reliable (docs/data_quality.md).
select
    drug_exposure_id,
    person_id,
    drug_concept_id,
    drug_exposure_start_date
from {{ source('cdm', 'drug_exposure') }}
