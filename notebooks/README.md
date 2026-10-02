# R Markdown notebooks

Step-by-step versions of the R scripts in `analysis/` and `etl/`, with explanations next to the code. The code is the same as the scripts; the notebooks add prose, show the output inline, and (for the analysis notebooks) are safe to knit from RStudio.

Start with [`00_start_here.Rmd`](00_start_here.Rmd), then go in order.

| # | Notebook | Source script |
|---|---|---|
| 0 | `00_start_here.Rmd` | Overview, setup check and database check |
| 1 | `01_etl_create_tables.Rmd` | `etl/01_load_vocab.R` (off by default) |
| 2 | `02_etl_synthea_to_omop.Rmd` | `etl/02_etl_synthea.R` (off by default) |
| 3 | `03_km_synthea_vs_seer.Rmd` | `analysis/km_synthea_vs_seer.R` |
| 4 | `04_rmst.Rmd` | `analysis/rmst.R` |
| 5 | `05_cox_os.Rmd` | `analysis/cox_os.R` |
| 6 | `06_age_sex_reweighting.Rmd` | `analysis/seer_age_sex_reweighting.R` |
| 7 | `07_treatment_patterns.Rmd` | `analysis/treatment_patterns.R` |
| 8 | `08_report_inputs.Rmd` | `analysis/report_inputs.R` |

**To run:** open `oncology-rwe-nsclc.Rproj` in RStudio, open a notebook, and click **Knit** (or run the chunks top to bottom). Each notebook points R at the repository root itself.

**Needs:** PostgreSQL running with the `dbt` schema built, and a `.Renviron` in the repository root (see `.Renviron.example`). Notebooks 4 and 6 also need two local SEER*Stat exports that are not in the repository (see the notes inside).

**Notes**
- Notebooks 3 to 8 also include charts that are not in the scripts (for example death-time histograms with the scripted windows, a forest plot of hazard ratios, an age and sex pyramid, and treatment and data-quality summaries). They only read data the notebook already has and write no files.
- Notebook 8 reads the local Data Quality Dashboard results file if `DQD_JSON` is set in `.Renviron` (see `.Renviron.example`); otherwise it leaves the `dqd_*.csv` files unchanged.
- Notebooks 1 and 2 change the database, so their code cells are switched off (`run_etl <- FALSE`) until you set it to `TRUE`.
- Notebooks 3 to 6 and 8 rewrite files in `results/`, `figures/` and `seer/` with the same content as the committed ones.
- The `.R` scripts remain the way to run everything unattended (`Rscript analysis/<name>.R`); they also write console logs, which the notebooks do not.
