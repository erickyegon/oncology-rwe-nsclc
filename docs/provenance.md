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

**Version mismatch fix (NPI column).** The current Synthea export adds an `NPI` column to `organizations.csv` and `providers.csv` that the `v330` native tables in ETL-Synthea do not have. ETL-Synthea's own `LoadSyntheaTables()` also read ZIP codes as integers (losing leading zeros) and failed on `organizations.csv`. `etl/02a_load_native_copy.sh` replaces it: it loads each CSV with `psql \copy`, and when a CSV has columns the native table lacks it loads through a staging table and drops the extra columns (here only `NPI`, which is not used by the OMOP mapping). The ETL-Synthea SQL itself is unchanged, but `etl/02_etl_synthea.R` runs it in stages instead of calling `LoadEventTables()` in one go: `CreateMapAndRollupTables` and `LoadEventTables` are rendered with `sqlOnly = TRUE`, the two slow vocabulary maps are built once and reused, an index on `final_visit_ids.encounter_id` is added, and `ANALYZE` runs between steps. The reason: a first attempt spent over 6 hours in `insert_observation` on 2M observation rows. One cause found: the first ETL script called `CreateExtraIndices` with the CDM and Synthea schema arguments in the wrong order (its signature is `connectionDetails, cdmSchema, syntheaSchema`), so ETL-Synthea's performance indexes were never created on the right tables. The other changes (missing index, statistics) are precautions; which of them mattered is confirmed by the run time of the staged load.

**Reproducibility.** The analysis run pins the patient seed (`-s 2026`), the clinician seed (`-cs 2026`) and the reference date (`-r 20261001`, i.e. 2026-10-01 00:00 UTC), so it can be regenerated with `synthea/run_generate.ps1` using the same jar and modules. The clinician seed affects provider assignment only, not clinical outcomes (diagnoses, stage, treatment, death), which are driven by the patient seed and the modules. The first (superseded) 60k run did not pin the reference date or clinician seed (it used the clock: reference time 1790875995187, 2026-10-01 13:33:15 -04:00); that run is retained only as evidence for the veteran-module finding. Generated data are not committed (only settings, modules and code).
