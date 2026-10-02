# Data notes

[Back to README](../README.md)

## Analysis cohort and sensitivity analysis (detail)
Decided 2026-10-01, after the stage mix was verified against SEER (counts from the analysis run, `-s 2026 -cs 2026 -r 20261001`):

| Cohort | Definition | n | Male | Age at dx, mean (SD) | Stage I / II / III / IV |
|---|---|---|---|---|---|
| All staged NSCLC | NSCLC with a TNM stage code | 1,621 | 74.9% | 60.8 (9.8) | 21.8 / 7.4 / 19.2 / 51.5% |
| **Main analysis** | Staged NSCLC, **age >= 50 at diagnosis**, all diagnosis years; follow-up **censored at 120 months** | **1,347** | 76.6% | 63.5 (8.6) | 21.7 / 8.1 / 19.4 / 50.9% |
| **Sensitivity analysis** | Main cohort restricted to **diagnosed 2010-2015** | **305** | 81.6% | 65.9 (7.2) | 21.6 / 9.2 / 18.4 / 50.8% |

Notes:
- The age >= 50 rule matches the SEER pull and removes 274 staged NSCLC patients diagnosed younger (Synthea's 50-90 range applies to age at the reference date, not at diagnosis). The 2010-2015 window matches the SEER diagnosis years. (339 patients were diagnosed 2010-2015 before the age rule; 305 after.)
- The 120-month censoring rule is a protocol choice made up front. In this data it censors nobody: no staged NSCLC patient has more than 120 months of observed follow-up (1,563 of 1,621 died, and survivors are observed for a short time). It is kept so the analysis is specified before results are seen and does not depend on the simulation's follow-up.
- In the sensitivity cohort every patient died within 120 months, so there is no censoring there; survival estimates reduce to the observed death times.

**Synthea fidelity findings (to compare against SEER, not errors to fix).** The synthetic NSCLC cohort is about three-quarters male (74.9% of all staged; 76.6% in the main cohort) with mean age at diagnosis about 61 (60.8 all staged; 63.5 in the main cohort, because the age rule removes the youngest). These come from Synthea's demographic and risk model, not from the stage patch. They will be compared with the sex and age distribution from the SEER pull (survival by stage, age group and sex) in the benchmark, and reported as a representativeness limitation of the synthetic data. They are not adjusted or corrected.

## Filtering, storage and deaths

**Storage note.** Synthea's claims and imaging exports are excluded, and each export is filtered to patients with a lung cancer diagnosis (`tools/filter_lung_cancer.py`) before the OMOP ETL, because the full export is tens of gigabytes. The study cohort is lung cancer patients only, so the cohort is unchanged; the OHDSI Data Quality Dashboard therefore describes this filtered population.

**Filtering and "deaths".** Before the ETL each export is filtered to patients with a lung cancer diagnosis (`tools/filter_lung_cancer.py`). Every patient-keyed table is filtered on the same patient IDs; `organizations`, `providers` and `payers` are copied whole. Verified on the 20k export: 633 patients, and each of encounters, conditions, medications, procedures, observations, careplans, immunizations, devices, supplies and payer_transitions has rows for all 633 (allergies for the 80 who have any) with zero patient IDs outside the cohort. Synthea has no separate deaths table: death is `patients.DEATHDATE`, mapped to the OMOP `death` table by the ETL.

## Study design (from the original plan)

### Research question
Among patients diagnosed with non-small cell lung cancer (NSCLC), how does real-world overall survival differ by stage at diagnosis and by first-line treatment type?

### Design
Retrospective cohort. Index date = first recorded lung cancer diagnosis. Adults with at least one encounter after index.
Exposures: stage; first-line treatment (chemotherapy alone, chemo + radiation, none recorded).
Outcomes: overall survival (censored at last recorded activity); time to next treatment.
Covariates: age, sex, smoking history, comorbidity count, diagnosis year.

### Pipeline
1. Synthea -> OMOP CDM 5.4 (ETL-Synthea) -> PostgreSQL; OHDSI Data Quality Dashboard
2. dbt models (`stg_`, `int_`, `mart_nsclc_cohort`) + tests
3. Rule-based lines of therapy
4. Endpoints
5. KM, Cox, IPTW, sensitivity analyses (R)
6. SEER benchmark
