# Plan and status

Study: how real-world overall survival differs by stage (and first-line treatment) in synthetic NSCLC data, and how far the synthetic data can be trusted when benchmarked against SEER. Analysis cohorts are defined in the [README](README.md).

| Stage | Work | Status |
|---|---|---|
| 1 | Generate synthetic patients with Synthea (60,000 alive, ages 50-90), with the lung cancer modules patched to the SEER stage mix | Done; stage mix verified against SEER ([details](docs/synthea-stage-patch.md)) |
| 2 | Filter to lung cancer patients; load into OMOP CDM 5.4 with ETL-Synthea on PostgreSQL | Done: loaded and verified against the source CSVs (`drug_era` skipped); see [provenance](docs/provenance.md) |
| 3 | OHDSI Data Quality Dashboard on the OMOP tables | To do |
| 4 | dbt models (`stg_`, `int_`, `mart_nsclc_cohort`) with uniqueness, missing-value and date-order tests | Done: main cohort n = 1,347 (sensitivity n = 305); all 28 models and tests pass; histology and stage come from source codes ([provenance](docs/provenance.md)) |
| 5 | Rule-based lines of therapy (28-day window, 90-day gap) and endpoints (overall survival, time to next treatment) | To do |
| 6 | Kaplan-Meier with log-rank tests, Cox models with Schoenfeld checks, IPTW (WeightIt, cobalt), multiple imputation and gap sensitivity analyses | To do |
| 7 | SEER benchmark: synthetic survival by stage against SEER observed survival | SEER inputs pulled (aggregates in `seer/`); comparison to do |
| 8 | Quarto report, one-page summary, LinkedIn post | To do |

Protocol decisions made before analysis: main cohort = staged NSCLC, age >= 50 at diagnosis, all diagnosis years, follow-up censored at 120 months; sensitivity analysis = diagnosed 2010-2015 ([data notes](docs/data-notes.md)).
