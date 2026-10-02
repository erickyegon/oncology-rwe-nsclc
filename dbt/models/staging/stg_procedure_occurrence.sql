-- Procedure rows; procedures are identified by their SNOMED source code (procedure_source_value).
select
    procedure_occurrence_id,
    person_id,
    procedure_date,
    procedure_source_value
from {{ source('cdm', 'procedure_occurrence') }}
