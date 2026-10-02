# Data dictionary: `mart_nsclc_cohort`

The analysis cohort table built by dbt (`dbt/models/marts/mart_nsclc_cohort.sql`, schema `dbt` in the `omop` database). One row per person: staged non-small cell lung cancer (NSCLC), age at diagnosis 50 or older, all diagnosis years, follow-up censored at 120 months. 1,347 rows. All data are synthetic (Synthea); the OMOP tables are loaded by `etl/02_etl_synthea.R`.

## Columns

| Column | Type | Definition | Source (OMOP CDM 5.4) | Derivation | Missing |
|---|---|---|---|---|---|
| `person_id` | integer | OMOP person identifier. Primary key of the table. | `person.person_id` | Carried through from `person`; enforced unique and not null by dbt tests. | 0 of 1,347 (0%) |
| `index_date` | date | Index date: the first recorded lung cancer diagnosis. | `condition_occurrence.condition_start_date`, where `condition_source_value` is one of the 10 lung cancer SNOMED codes below | `min(condition_start_date)` per person over all rows with a lung cancer source code (`int_lung_cancer_dx`). Range 1987-02-10 to 2026-09-10. | 0 (0%) |
| `age_at_dx` | numeric (2 decimals) | Age in years at the index date. | `person.birth_datetime` (fallback: `year_of_birth`, `month_of_birth`, `day_of_birth`) and `index_date` | `(index_date - birth_date) / 365.25`, rounded to 2 decimals for display. The cohort filter `age >= 50` uses the unrounded value. Range 50.05 to 84.96. | 0 (0%) |
| `sex` | text | Sex recorded at birth, `M` or `F`. | `person.gender_concept_id` | 8507 maps to `M`, 8532 maps to `F`, anything else to `U` (none present). 1,032 M, 315 F. | 0 (0%) |
| `stage` | text | TNM stage group at diagnosis, `I`, `II`, `III` or `IV`. | `condition_occurrence.condition_source_value` | From the stage-specific NSCLC **source code** (see the code table below), never from the standard concept: `424132000` is I, `425048006` is II, `422968005` is III, `423121009` is IV (`int_stage_histology`). A person with no stage code, or with conflicting stage codes, has a null stage and is excluded from the cohort. Counts: I 292, II 109, III 261, IV 685. | 0 (0%) in the cohort |
| `death_date` | date | Date of death, if the person died. | `death.death_date` | Left join on `person_id`; null for persons not recorded as dead. Range 1987-08-25 to 2026-09-16. | 56 of 1,347 (4.2%). Not a data defect: these are the survivors, who are censored. |
| `followup_months` | numeric (3 decimals) | Months from the index date to death (event) or to the last recorded activity (censoring), capped at 120. | `death.death_date`, `observation_period.observation_period_end_date` | `greatest(coalesce(death_date, observation_period_end_date) - index_date, 0) / 30.4375`, then `least(..., 120)`, rounded to 3 decimals. Range 0.690 to 71.984. | 0 (0%) |
| `event` | integer (0/1) | 1 if the person died within 120 months of the index date, else 0 (censored). | `death.death_date` | `death_date is not null and uncapped follow-up <= 120`. 1,291 events. | 0 (0%) |
| `censored_at_120` | boolean | True if follow-up was truncated at the 120-month cap. | derived | `uncapped follow-up > 120 months`. All false in this data: no person has more than 72 months of follow-up. | 0 (0%) |
| `dx_2010_2015` | boolean | Flag for the sensitivity cohort: diagnosed in 2010 to 2015. | derived from `index_date` | `extract(year from index_date) between 2010 and 2015`. 305 true. | 0 (0%) |

### Histology and stage come from source codes, not standard concepts
In the Athena vocabulary release v20260829 loaded here, SNOMED `422968005` ("NSCLC, TNM stage 3") maps to two Condition concepts, NSCLC and "Small cell carcinoma of lung". ETL-Synthea writes one `condition_occurrence` row per target concept, so 312 persons carry a spurious small cell concept (see `docs/provenance.md`). The cohort therefore never uses `condition_concept_id`. Histology and stage are taken from `condition_source_value` through the code map `int_lung_cancer_codes`, which a dbt test checks against the SNOMED concept names in `cdm.concept`.

| Source code (SNOMED) | Histology | Stage | Meaning |
|---|---|---|---|
| `254637007` | NSCLC | (none) | Non-small cell lung cancer, parent diagnosis |
| `424132000` | NSCLC | I | Non-small cell carcinoma of lung, TNM stage 1 |
| `425048006` | NSCLC | II | Non-small cell carcinoma of lung, TNM stage 2 |
| `422968005` | NSCLC | III | Non-small cell carcinoma of lung, TNM stage 3 |
| `423121009` | NSCLC | IV | Non-small cell carcinoma of lung, TNM stage 4 |
| `254632001` | SCLC | (none) | Small cell carcinoma of lung, parent diagnosis |
| `67811000119102` | SCLC | I | Primary small cell malignant neoplasm of lung, TNM stage 1 |
| `67821000119109` | SCLC | II | Primary small cell malignant neoplasm of lung, TNM stage 2 |
| `67831000119107` | SCLC | III | Primary small cell malignant neoplasm of lung, TNM stage 3 |
| `67841000119103` | SCLC | IV | Primary small cell malignant neoplasm of lung, TNM stage 4 |

A person is NSCLC if they have at least one NSCLC code and no SCLC code. No person has both (0 with mixed histology).

### Cohort rules (dbt variables in `dbt/dbt_project.yml`)
- Histology NSCLC and a single TNM stage code (I to IV).
- Age at diagnosis >= `min_age_at_dx` (50), matching the SEER extraction.
- Follow-up capped at `followup_cap_months` (120); `days_per_month` 30.4375, `days_per_year` 365.25.
- Sensitivity cohort: `dx_2010_2015`, years `sensitivity_start_year` to `sensitivity_end_year`.

### Data-quality tests on this table (dbt)
`unique` and `not_null` on `person_id`; `not_null` on every other column; `accepted_values` for `sex` (M, F), `stage` (I to IV) and `event` (0, 1); follow-up between 0 and 120; death date not before the index date; no small cell source code among the cohort's persons; `event`, `death_date` and `censored_at_120` consistent with each other; every person with source code `422968005` classified NSCLC stage III; the code map agrees with the vocabulary.

## `mart_cohort_attrition`

The cohort flow (attrition) table used for the report. One row per step; `n_persons` is the number of people remaining or excluded at that step.

| Column | Type | Definition |
|---|---|---|
| `step_order` | integer | Order of the step, 1 to 9. |
| `step` | text | Description of the step. |
| `n_persons` | bigint | Number of persons at that step (for "Excluded" steps, the number removed). |

| step_order | step | n_persons |
|---|---|---|
| 1 | People in the OMOP CDM (lung cancer export) | 1,886 |
| 2 | With a lung cancer diagnosis code | 1,886 |
| 3 | Excluded: small cell (source code) | 264 |
| 4 | NSCLC (source code) | 1,622 |
| 5 | Excluded: NSCLC without a single TNM stage code | 1 |
| 6 | Staged NSCLC | 1,621 |
| 7 | Excluded: age at diagnosis under 50 | 274 |
| 8 | Main analysis cohort | 1,347 |
| 9 | Sensitivity cohort (diagnosed 2010-2015) | 305 |

The source export holds only patients with a lung cancer diagnosis (`tools/filter_lung_cancer.py`), so steps 1 and 2 are equal by construction.
