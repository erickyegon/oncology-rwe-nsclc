-- Lung cancer diagnosis codes in the Synthea export (SNOMED), with histology and TNM stage.
-- Histology and stage are taken from these SOURCE codes, never from the standard concept: in Athena v20260829
-- SNOMED 422968005 (NSCLC, TNM stage 3) also maps to the standard concept 'Small cell carcinoma of lung'
-- (see docs/provenance.md). tests/assert_code_map_matches_vocabulary.sql checks this map against cdm.concept.
select * from (values
    ('254637007',      'NSCLC', cast(null as varchar), 'Non-small cell lung cancer (parent diagnosis)'),
    ('424132000',      'NSCLC', 'I',   'Non-small cell carcinoma of lung, TNM stage 1'),
    ('425048006',      'NSCLC', 'II',  'Non-small cell carcinoma of lung, TNM stage 2'),
    ('422968005',      'NSCLC', 'III', 'Non-small cell carcinoma of lung, TNM stage 3'),
    ('423121009',      'NSCLC', 'IV',  'Non-small cell carcinoma of lung, TNM stage 4'),
    ('254632001',      'SCLC',  cast(null as varchar), 'Small cell carcinoma of lung (parent diagnosis)'),
    ('67811000119102', 'SCLC',  'I',   'Primary small cell malignant neoplasm of lung, TNM stage 1'),
    ('67821000119109', 'SCLC',  'II',  'Primary small cell malignant neoplasm of lung, TNM stage 2'),
    ('67831000119107', 'SCLC',  'III', 'Primary small cell malignant neoplasm of lung, TNM stage 3'),
    ('67841000119103', 'SCLC',  'IV',  'Primary small cell malignant neoplasm of lung, TNM stage 4')
) as t(source_code, histology, stage, description)
