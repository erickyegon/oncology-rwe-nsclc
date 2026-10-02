# Software versions and provenance

[Back to README](../README.md)

| Component | Version / detail |
|---|---|
| Synthea | `master-branch-latest` release, `synthea-with-dependencies.jar`, build version `d9d07a6`, built 2026-08-18 (JDK 17.0.20). Local module override via `-d synthea/modules` |
| Synthea run (60k, analysis run) | `-s 2026 -cs 2026 -r 20261001 -p 60000 -a 50-90 -d synthea/modules`, location Massachusetts (default), CSV export only (claims and imaging excluded); both lung cancer modules patched. `run_generate.ps1` defaults to these values |
| ETL-Synthea (`ETLSyntheaBuilder`) | R package 2.1, installed from `OHDSI/ETL-Synthea` HEAD, commit `9ee6eb1b933c70af7b80711332aa92327af1f7c5` (2026-10-01); CommonDataModel 1.0.1 (`4a91030`) |
| OMOP CDM / Synthea table schema | CDM 5.4; Synthea table definitions `v330` (ETL-Synthea's newest) |
| OMOP vocabularies | Athena release v20260829: SNOMED, RxNorm, LOINC, CVX, ICDO3, Cancer Modifier plus Athena defaults; CPT4 excluded |
| Database | PostgreSQL 17, schemas `native`, `cdm`, `results`, `dbt` |
| R | 4.6.1; DatabaseConnector 7.2.0, SqlRender 1.19.7, survival 3.8.6, WeightIt 2.1.0, cobalt 5.0.0, mice 3.19.0 |
| dbt | dbt-postgres (dbt-core 1.12.5) |

**Version mismatch fix (NPI column).** The current Synthea export adds an `NPI` column to `organizations.csv` and `providers.csv` that the `v330` native tables in ETL-Synthea do not have. ETL-Synthea's own `LoadSyntheaTables()` also read ZIP codes as integers (losing leading zeros) and failed on `organizations.csv`. `etl/02a_load_native_copy.sh` replaces it: it loads each CSV with `psql \copy`, and when a CSV has columns the native table lacks it loads through a staging table and drops the extra columns (here only `NPI`, which is not used by the OMOP mapping). The ETL-Synthea SQL itself is unchanged, but `etl/02_etl_synthea.R` runs it in stages instead of calling `LoadEventTables()` in one go: `CreateMapAndRollupTables` and `LoadEventTables` are rendered with `sqlOnly = TRUE`, the two slow vocabulary maps are built once and reused, an index on `final_visit_ids.encounter_id` is added, `ANALYZE` runs between steps, and the OHDSI `drug_era` step is skipped by default (see below). The full event load of the 60k cohort takes about 10 minutes without `drug_era` (about 4 of them for the `cost` table).

**Reproducibility.** The analysis run pins the patient seed (`-s 2026`), the clinician seed (`-cs 2026`) and the reference date (`-r 20261001`, i.e. 2026-10-01 00:00 UTC), so it can be regenerated with `synthea/run_generate.ps1` using the same jar and modules. The clinician seed affects provider assignment only, not clinical outcomes (diagnoses, stage, treatment, death), which are driven by the patient seed and the modules. The first (superseded) 60k run did not pin the reference date or clinician seed (it used the clock: reference time 1790875995187, 2026-10-01 13:33:15 -04:00); that run is retained only as evidence for the veteran-module finding. Generated data are not committed (only settings, modules and code).

## OMOP load notes (2026-10-01)

### `CreateExtraIndices` argument order: a real bug, but not shown to explain the 6-hour stall
`CreateExtraIndices` has the signature `(connectionDetails, cdmSchema, syntheaSchema, ...)`. The first ETL script passed the schemas the other way round, so all six indexes in ETL-Synthea's `extra_indices.sql` (five on CDM tables, including `person.person_source_value` and `provider.provider_source_value`, and one on `claims_transactions`) targeted nonexistent `native.*` tables and failed; the errors were printed but did not stop the run. This is fixed.

A first attempt at the event load, run on a 20k-patient test export while Synthea generation was also running and the machine had under 1 GB of free memory, spent over 6 hours in `insert_observation` before it was cancelled. I tested whether the missing indexes or missing statistics explain that, by timing the heaviest part of that step (the LOINC observations join, 991,199 rows out of 3.8M source rows) on the full 60k data, one factor at a time, on copies of the tables:

| Run | Tables in the join | Time |
|---|---|---|
| 1 | helper tables (`person`, `provider`, `final_visit_ids`) never analyzed, no indexes | 4.8 s |
| 2 | helper tables analyzed, no indexes | 4.8 s |
| 3 | helper tables analyzed, with `person_psv`, `provider_psv` and an index on `final_visit_ids.encounter_id` | 17.0 s |
| 4 | every table in the join freshly created and never analyzed, no extra indexes | 11.6 s |

None of these reproduces a multi-hour run (the indexes made it slower, not faster). So the swapped arguments are **not confirmed as the cause**; the cause of the stall is not established. The machine was under heavy memory pressure and running Synthea at the time, which I did not test. In an idle state the staged loader runs the same step on twice the observations in about 77 seconds.

### `drug_era` skipped
The OHDSI `insert_drug_era.sql` (a recursive query over `drug_exposure`) ran for 63 minutes on 496,822 drug exposures in PostgreSQL without finishing and was cancelled. Lines of therapy in this project are derived from `drug_exposure`, so `cdm.drug_era` is left empty. `condition_era` loaded normally (49,826 rows). The step can be run with `ETL_SKIP_STEPS=none`.

### Vocabulary mapping finding: stage III NSCLC also maps to small cell lung cancer
In the Athena vocabulary release v20260829 as downloaded, the SNOMED concept for code `422968005` ("Non-small cell carcinoma of lung, TNM stage 3", concept 4311997) has three `Maps to` targets: 4115276 "Non-small cell lung cancer", 1633650 "AJCC/UICC Stage 3" (Measurement domain, so the ETL drops it) and **4110591 "Small cell carcinoma of lung"**. ETL-Synthea writes one condition row per Condition-domain target, so each of the 312 stage III NSCLC diagnoses appears twice in `cdm.condition_occurrence`, once as NSCLC and once as small cell carcinoma. The other lung cancer source codes (NSCLC stages 1, 2 and 4, the NSCLC parent code, and all small cell codes) map one-to-one to the right histology.

Consequence: 576 persons carry standard concept 4110591: 264 true small cell patients plus the 312 stage III NSCLC patients. A cohort defined by standard concept would wrongly count stage III NSCLC patients as small cell. **The dbt cohort models therefore define histology and stage from the source codes (`condition_source_value` / `condition_source_concept_id`), not from the standard concept**, and deduplicate on person, date and source code. The same one-to-many effect appears elsewhere: `cdm.drug_exposure` has 496,822 rows from 475,987 medication rows.

### Verification of the OMOP load against the source CSVs
`tools/verify_omop.py` compares the loaded CDM with the filtered Synthea CSVs (60k analysis run, 1,886 lung cancer patients). All hard checks pass:

| Check | Source | OMOP |
|---|---|---|
| Persons | 1,886 | 1,886 |
| Observation periods | 1,886 | 1,886 |
| Deaths (patients with a death date) | 1,818 | 1,818 |
| Lung cancer condition events (distinct person, date, source code) | 3,771 | 3,771 |
| Persons with an NSCLC condition | 1,622 | 1,622 |
| Persons with an NSCLC TNM stage condition | 1,621 | 1,621 |
| Lung cancer rows with an unmapped concept (id 0) | | 0 |
| Condition rows pointing at a missing visit | | 0 |

Lung cancer `condition_occurrence` rows are 4,083 against 3,771 source rows; the 312 extra are the stage III fan-out above.

