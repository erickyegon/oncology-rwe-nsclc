# Data quality: OHDSI Data Quality Dashboard

[Back to README](../README.md)

## What was run
- **Tool:** OHDSI DataQualityDashboard 2.8.9 (`executeDqChecks`), CDM version 5.4, on the `cdm` schema of the `omop` PostgreSQL database (lung-cancer-filtered Synthea export, 1,886 persons). Vocabulary: Athena release v20260829.
- **Scope:** table, field and concept level checks; the vocabulary tables themselves (`CONCEPT`, `VOCABULARY`, `CONCEPT_ANCESTOR`, `CONCEPT_RELATIONSHIP`, `CONCEPT_CLASS`, `CONCEPT_SYNONYM`, `RELATIONSHIP`, `DOMAIN`) were excluded, as is the DQD default.
- **Run:** 2026-10-02, 9 minutes, 4 threads. The results JSON is saved locally and not committed.
- **Population:** the export holds only patients with a lung cancer diagnosis (`tools/filter_lung_cancer.py`), so this describes that population, not all Synthea patients. `drug_era` was deliberately not loaded (see [provenance](provenance.md)).

## Result: 2,374 checks

| Category | Checks | Passed | Failed | Not applicable | Errored |
|---|---:|---:|---:|---:|---:|
| Conformance | 1,060 | 815 | 4 | 223 | 18 |
| Completeness | 501 | 354 | 8 | 128 | 11 |
| Plausibility | 813 | 321 | 6 | 482 | 4 |
| **Total** | **2,374** | **1,490** | **18** | **833** | **33** |

- **Passed:** 1,490 of the 1,508 checks that could run (98.8%). DQD's own headline of 99.24% passed also counts the not-applicable and errored checks as passed, so it is not used here.
- **Not applicable (833):** the check does not apply because the table is empty. Synthea does not produce these tables: `EPISODE`, `NOTE`, `NOTE_NLP`, `SPECIMEN`, `DOSE_ERA`, `DRUG_ERA`, `FACT_RELATIONSHIP`, `SOURCE_TO_CONCEPT_MAP` and similar.
- **Errored (33) and 2 of the 18 failures:** all 35 are checks on the optional OMOP tables `COHORT` and `COHORT_DEFINITION`, which this CDM does not create (DQD looks for them in the `results` schema). They are "table absent", not data findings.
- **Threshold failures (16):** explained below.

## The 16 threshold failures

Cause key: **Synthea** = how Synthea simulates data; **ETL** = how ETL-Synthea writes the OMOP tables; **Vocabulary** = content of the Athena release. None is a real data problem for the NSCLC cohort.

| Category | Check and field | Violated | Cause | Explanation |
|---|---|---|---|---|
| Completeness | `CONDITION_OCCURRENCE.CONDITION_STATUS_CONCEPT_ID` unpopulated | 52,832 of 52,832 (100%) | ETL | Optional field; ETL-Synthea leaves it null and Synthea has no condition status. Not used by the cohort. |
| Completeness | `DRUG_ERA` has no rows for any person | 1,886 of 1,886 (100%) | ETL (deliberate) | The `drug_era` step was skipped because the OHDSI query ran over an hour without finishing; lines of therapy use `drug_exposure`. |
| Completeness | `MEASUREMENT.UNIT_CONCEPT_ID` unpopulated | 1,094,453 of 2,954,339 (37.0%) | Synthea | Many Synthea observations are text or panel results without a unit. |
| Completeness | `OBSERVATION.UNIT_CONCEPT_ID` unpopulated | 1,059,337 of 1,059,337 (100%) | ETL | The `observation` table is filled from allergies, conditions and non-numeric observations, none with units. |
| Completeness | `VISIT_DETAIL.ADMITTED_FROM_CONCEPT_ID`, `DISCHARGED_TO_CONCEPT_ID` | 174,498 of 174,498 (100%) each | Synthea | Synthea does not record admission source or discharge destination. |
| Completeness | `VISIT_OCCURRENCE.ADMITTED_FROM_CONCEPT_ID`, `DISCHARGED_TO_CONCEPT_ID` | 174,498 of 174,498 (100%) each | Synthea | As above. |
| Conformance | `OBSERVATION.OBSERVATION_TYPE_CONCEPT_ID` is not a standard valid concept | 1,058,644 of 1,059,337 (99.9%) | ETL | ETL-Synthea hard-codes type concept 38000280 ("Observation recorded from EHR") for 1,058,644 rows, and this release does not treat it as a standard concept; the other 693 rows use the standard 32827. Not used by the cohort. |
| Conformance | `DRUG_STRENGTH.INGREDIENT_CONCEPT_ID` foreign-key class | 3,587 of 2,966,568 (0.1%) | Vocabulary | A small share of rows in the Athena `DRUG_STRENGTH` file point to a concept that is not an ingredient. Not used by this project. |
| Plausibility | `DRUG_EXPOSURE.DAYS_SUPPLY` below 1 | 376,733 of 496,822 (75.8%) | ETL / Synthea | ETL-Synthea computes `days_supply` as stop minus start (0 when there is no stop), so single-day administrations such as injections are 0 (375,128 rows), and a few records have a stop before the start (minimum -6). Treat `days_supply` as unreliable; use start dates. |
| Plausibility | `DRUG_EXPOSURE.DAYS_SUPPLY` above 365 | 12,863 of 496,822 (2.6%) | Synthea | Long-running chronic medications (maximum 14,720 days). |
| Plausibility | `DRUG_EXPOSURE.QUANTITY` below the plausible minimum | 496,822 of 496,822 (100%) | ETL | ETL-Synthea hard-codes `quantity` to 0 for every drug exposure. |
| Plausibility | `MEASUREMENT` value units not among the plausible units for the concept | 21,922 of 23,871 (91.8%) | Synthea | Synthea reports some results in units that differ from the units DQD expects. |
| Plausibility | `OBSERVATION_PERIOD.OBSERVATION_PERIOD_START_DATE` before 1950-01-01 | 252 of 1,886 (13.4%) | Synthea | Records start in childhood (about age 14 on average), so people born in the 1930s start before 1950. |
| Plausibility | `PAYER_PLAN_PERIOD.PAYER_PLAN_PERIOD_END_DATE` after death | 1,496 of 75,056 (2.0%) | Synthea | Insurance periods continue after the death date. Not used by the cohort. |

## Failures that touch the NSCLC cohort tables

The cohort is built from `person`, `condition_occurrence`, `death` and `observation_period`.

| Table | Passed | Failed | Not applicable |
|---|---:|---:|---:|
| `person` | 81 | 0 | 4 |
| `death` | 41 | 0 | 0 |
| `condition_occurrence` | 97 | 1 | 205 |
| `observation_period` | 39 | 1 | 0 |

Two failures touch these tables, and neither affects a field the cohort uses:
1. **`condition_occurrence.condition_status_concept_id`** is 100% empty (an optional field). The cohort uses `person_id`, `condition_start_date` and `condition_source_value` (all 19 checks on them pass).
2. **`observation_period.observation_period_start_date`** is before 1950 for 252 persons, 200 of them in the main cohort. The cohort uses only the *end* date (all 9 checks on it pass), so follow-up is unaffected. The start date is not used.

Every check on the other fields the cohort uses passes: `person.person_id`, `gender_concept_id`, `year_of_birth` and `birth_datetime`, and `death.person_id` and `death_date`.

## For the treatment analysis
`drug_exposure` has 3 failed checks (`days_supply` too low and too high, `quantity` always 0). Dose, quantity and days supply are therefore not usable; treatment timing has to come from `drug_exposure_start_date`.

## What this dashboard does not catch
DQD checks structure, completeness and plausibility, not meaning. It did **not** flag the stage III vocabulary mapping problem (NSCLC stage 3 also mapping to the small cell concept; see [provenance](provenance.md)): the extra rows are well-formed, populated and plausible. That problem was found by the cohort-level checks in `dbt/tests` and by comparing the load with the source CSVs (`tools/verify_omop.py`).
