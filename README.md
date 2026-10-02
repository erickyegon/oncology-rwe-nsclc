# How realistic is synthetic oncology EHR data?
### NSCLC survival from Synthea, harmonized to OMOP and benchmarked against SEER

> **Data statement:** Synthetic patient-level EHR data (Synthea) and public SEER registry
> aggregates only. Structured to mirror commercial oncology EHR data; **not** Flatiron or
> any real patient data. A methods demonstration, not clinical evidence.

## Why this project
Oncology real-world evidence depends on messy patient-level EHR data that is rarely open.
This project builds the full workflow on synthetic data (OMOP harmonization, cohort
building, survival analysis) and then asks how far the synthetic data can be trusted,
by benchmarking it against 172,582 real U.S. NSCLC patients from SEER.

## Key findings so far
- **Silent stage bug found and fixed.** Unmodified Synthea staged every lung cancer as
  stage I. After patching one module, a second, hidden module (veteran path) still
  produced 51.5% stage I. Both are now patched to the SEER stage mix and verified
  (p = 0.50). [Details](docs/synthea-stage-patch.md)
- **Demographics differ from real NSCLC.** The synthetic cohort is 77% male, with a mean
  age at diagnosis of 63.5 (main cohort). These will be compared against SEER's age and
  sex distribution.
- **Survival benchmark:** in progress. *(Add the headline result here when ready.)*

## Pipeline
Synthea (Java) → filter to lung cancer → OMOP CDM 5.4 via ETL-Synthea → PostgreSQL →
dbt cohort models and tests → survival analysis in R (Kaplan–Meier, Cox, IPTW) →
SEER benchmark.

## Analysis cohorts
| Cohort | Definition | n |
|---|---|---|
| Main | Staged NSCLC, age ≥50 at diagnosis, all years, censored at 120 months | 1,347 |
| Sensitivity | Main cohort, diagnosed 2010–2015 | 305 |

## Status
Synthea cohort generated and stage mix verified against SEER; OMOP load in progress. Next: dbt cohort models, then survival analysis. See PLAN.md.

## Documentation
- [Synthea stage patch](docs/synthea-stage-patch.md): the all-stage-I bug, the hidden veteran module, the SEER stage mix and the verification
- [Software versions and provenance](docs/provenance.md): versions, the ETL-Synthea compatibility fixes, reproducibility
- [Data notes](docs/data-notes.md): cohort definitions and fidelity findings, filtering and storage, study design
- [SEER inputs](seer/README.md): aggregate-only SEER results and citation

## Running the code
Run everything from the repository root.
1. Copy [`.Renviron.example`](.Renviron.example) to `.Renviron` (gitignored) and set the PostgreSQL connection, a JDK 17+ `JAVA_HOME`, and the vocabulary and Synthea paths.
2. Create the database and role: `etl/setup_postgres.ps1`.
3. Generate the synthetic data: `synthea/run_generate.ps1`.
4. Keep only lung cancer patients: `python tools/filter_lung_cancer.py <csv_dir> <out_dir>`.
5. Load the OMOP vocabularies: `Rscript etl/01_load_vocab.R` (creates the tables), then `etl/01b_load_vocab_copy.sh` and `etl/01c_vocab_indexes.sql`.
6. Load the Synthea CSVs: `etl/02a_load_native_copy.sh <dir>`.
7. Map to OMOP CDM 5.4: `Rscript etl/02_etl_synthea.R`.
8. Check the cohort: `python tools/cohort_summary.py <dir>`.

Later stages (dbt models, survival analysis, report) are in progress.

## License and data terms
The **MIT License** (see [LICENSE](LICENSE)) covers **the code in this repository only**: the scripts, SQL/dbt models, R code, Synthea module edits and documentation I wrote.

It does **not** cover third-party data or content:
- **SEER data** are used under the SEER Research Data Use Agreement. No SEER record-level data are in this repository; only the small set of aggregate results listed in [`seer/`](seer/) is included, and SEER data cannot be redistributed.
- **OMOP standardized vocabularies** (downloaded from Athena) remain under their own terms and the licences of each source vocabulary (for example SNOMED CT, RxNorm, LOINC, CVX, ICDO3). They are not included here and are not redistributed.
- **Synthea** is open source under its own license; the generated synthetic data are not committed (only generation settings and the edited module files).
