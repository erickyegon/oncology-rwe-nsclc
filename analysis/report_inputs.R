# Aggregate result files that the study report (report/report.qmd) reads, so the report contains no hand-typed figures.
# Run from the repository root:  Rscript analysis/report_inputs.R
# Reads the OMOP CDM and the dbt models in PostgreSQL (PG_* from .Renviron) and, if the environment variable DQD_JSON points to
# the local OHDSI Data Quality Dashboard results file, that file (it is not committed). Writes only small aggregate tables:
#   results/mart_cohort_attrition.csv, results/omop_table_counts.csv, results/report_inputs.csv,
#   results/treatment_first_line_by_stage.csv, results/treatment_patterns_summary.csv, results/lines_of_therapy_by_gap.csv,
#   results/dqd_summary.csv, results/dqd_failures.csv
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(dplyr); library(tidyr); library(readr) })
options(width = 200, dplyr.summarise.inform = FALSE)
dir.create("results", showWarnings = FALSE)
if (!nzchar(Sys.getenv("PG_HOST"))) readRenviron(".Renviron")
con <- dbConnect(Postgres(), host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT")),
                 dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"))
q <- function(sql) dbGetQuery(con, sql)
STAGES <- c("I", "II", "III", "IV")

# ---- cohort flow and key facts -------------------------------------------------------------------------------------------------
write_csv(q("select step_order, step, n_persons from dbt.mart_cohort_attrition order by 1") |> mutate(n_persons = as.integer(n_persons)), "results/mart_cohort_attrition.csv")
counts <- sapply(c("person", "visit_occurrence", "condition_occurrence", "drug_exposure", "procedure_occurrence", "measurement", "observation", "death", "observation_period"),
                 function(t) as.numeric(q(sprintf("select count(*) from cdm.%s", t))[[1]]))
write_csv(tibble(table = names(counts), rows = as.integer(counts)), "results/omop_table_counts.csv")
mart <- q("select * from dbt.mart_nsclc_cohort") |> mutate(stage = factor(stage, STAGES), followup_months = as.numeric(followup_months), age_at_dx = as.numeric(age_at_dx))
scalar <- function(sql) as.numeric(q(sql)[[1]])
kv <- tibble::tribble(~key, ~value,
  "vocabulary_version", q("select vocabulary_version from cdm.vocabulary where vocabulary_id = 'None'")[[1]],
  "persons_in_cdm", as.character(counts[["person"]]),
  "stage3_code_persons", as.character(scalar("select count(distinct person_id) from cdm.condition_occurrence where condition_source_value = '422968005'")),
  "stage3_code_rows", as.character(scalar("select count(*) from cdm.condition_occurrence where condition_source_value = '422968005'")),
  "persons_with_small_cell_concept", as.character(scalar("select count(distinct person_id) from cdm.condition_occurrence where condition_concept_id = 4110591")),
  "true_small_cell_persons", as.character(scalar("select count(*) from dbt.int_stage_histology where histology = 'SCLC'")),
  "nsclc_persons", as.character(scalar("select count(*) from dbt.int_stage_histology where histology = 'NSCLC'")),
  "max_age_at_dx_main", as.character(max(mart$age_at_dx)),
  "max_followup_months_main", as.character(max(mart$followup_months)),
  "prior_other_cancer_n", as.character(sum(mart$prior_other_cancer)),
  "prior_by_drug_n", as.character(scalar("select count(*) from dbt.mart_nsclc_cohort m join dbt.int_prior_cancer p using (person_id) where p.prior_anticancer_drug")),
  "prior_by_procedure_n", as.character(scalar("select count(*) from dbt.mart_nsclc_cohort m join dbt.int_prior_cancer p using (person_id) where p.prior_chemo_radiation_procedure")),
  "prior_by_diagnosis_n", as.character(scalar("select count(*) from dbt.mart_nsclc_cohort m join dbt.int_prior_cancer p using (person_id) where p.prior_other_malignancy_dx")))
write_csv(kv, "results/report_inputs.csv")

# ---- treatment patterns (main cohort) ------------------------------------------------------------------------------------------
adm <- q("select a.person_id, a.administration_date as d, a.ingredient from dbt.int_nsclc_systemic_administrations a join dbt.mart_nsclc_cohort m using (person_id)") |> mutate(d = as.Date(d))
rad <- q("select p.person_id, p.procedure_date as d from dbt.stg_procedure_occurrence p join dbt.mart_nsclc_cohort m using (person_id)
          where p.procedure_source_value = '703423002' and p.procedure_date >= m.index_date") |> mutate(d = as.Date(d))
per <- mart |> transmute(person_id, stage, index_date = as.Date(index_date), event) |>
  left_join(adm |> group_by(person_id) |> summarise(first_sys = min(d), n_dates = n_distinct(d), n_ing = n_distinct(ingredient)), by = "person_id") |>
  left_join(rad |> group_by(person_id) |> summarise(first_cxrt = min(d)), by = "person_id") |>
  mutate(first_line = case_when(!is.na(first_sys) & !is.na(first_cxrt) & abs(as.numeric(first_cxrt - first_sys)) <= 28 ~ "chemotherapy + radiation",
                                !is.na(first_sys) ~ "chemotherapy alone", TRUE ~ "none recorded"),
         days_to_first = as.numeric(first_sys - index_date))
write_csv(per |> count(stage, first_line, name = "n") |> complete(stage, first_line = c("chemotherapy + radiation", "chemotherapy alone", "none recorded"), fill = list(n = 0L)),
          "results/treatment_first_line_by_stage.csv")
ct <- suppressWarnings(chisq.test(table(per$stage, per$first_line)))
cramers_v <- unname(sqrt(ct$statistic / (nrow(per) * (min(dim(table(per$stage, per$first_line))) - 1))))
gaps <- adm |> distinct(person_id, d) |> arrange(person_id, d) |> group_by(person_id) |> mutate(gap = as.numeric(d - lag(d))) |> ungroup() |> filter(!is.na(gap))
pat_gap <- function(th) n_distinct(gaps$person_id[gaps$gap > th])
lines_for_gap <- function(th) {                                       # same rule as dbt.int_lines_of_therapy
  adm |> distinct(person_id, d) |> arrange(person_id, d) |> group_by(person_id) |> mutate(gap = as.numeric(d - lag(d)), new = is.na(gap) | gap > th, line = cumsum(new)) |>
    summarise(n_lines = max(line))
}
by_gap <- bind_rows(lapply(c(60, 90, 120), function(th) { l <- lines_for_gap(th)
  tibble(gap_days = th, treated_patients = nrow(l), patients_with_line2 = sum(l$n_lines >= 2), patients_with_3plus_lines = sum(l$n_lines >= 3), total_lines = sum(l$n_lines)) }))
dbt_lines <- q("select count(*) n, count(distinct person_id) p from dbt.int_lines_of_therapy l join dbt.mart_nsclc_cohort m using (person_id)")
stopifnot(by_gap$total_lines[by_gap$gap_days == 90] == as.numeric(dbt_lines$n))     # agrees with the dbt model at the default gap (90)
write_csv(by_gap, "results/lines_of_therapy_by_gap.csv")
line1_reg <- q("select regimen, count(*) n from dbt.int_lines_of_therapy l join dbt.mart_nsclc_cohort m using (person_id) where line_number = 1 group by 1 order by 2 desc")
l2_n <- scalar("select count(*) from dbt.int_lines_of_therapy l join dbt.mart_nsclc_cohort m using (person_id) where line_number = 2")
pst <- per |> filter(!is.na(first_sys)); iqr <- function(x) quantile(x, c(.25, .5, .75), names = FALSE)
summ <- tibble::tribble(~measure, ~value,
  "main_cohort_n", nrow(per), "treated_n", nrow(pst), "untreated_n", sum(is.na(per$first_sys)),
  "first_line_modal_type_n", max(table(per$first_line)), "cramers_v_stage_vs_first_line", cramers_v, "chisq_p_stage_vs_first_line", ct$p.value,
  "days_to_first_median", iqr(pst$days_to_first)[2], "days_to_first_q1", iqr(pst$days_to_first)[1], "days_to_first_q3", iqr(pst$days_to_first)[3],
  "days_to_first_max", max(pst$days_to_first), "admin_dates_median", iqr(pst$n_dates)[2], "admin_dates_q1", iqr(pst$n_dates)[1], "admin_dates_q3", iqr(pst$n_dates)[3],
  "gaps_total", nrow(gaps), "gap_1day_n", sum(gaps$gap == 1), "gap_median_days", median(gaps$gap), "gap_p99_days", unname(quantile(gaps$gap, .99)), "gap_max_days", max(gaps$gap),
  "patients_gap_gt28", pat_gap(28), "patients_gap_gt60", pat_gap(60), "patients_gap_gt90", pat_gap(90), "patients_gap_gt120", pat_gap(120),
  "line1_single_regimen_n", as.numeric(line1_reg$n[line1_reg$regimen == "cisplatin + paclitaxel"]), "line2_n", l2_n,
  "ttnt_event_n", sum(mart$ttnt_event == 1, na.rm = TRUE), "ttnt_median_months", median(mart$ttnt_months, na.rm = TRUE))
for (st in STAGES) summ <- bind_rows(summ, tibble(measure = paste0("admin_dates_median_stage_", st), value = median(pst$n_dates[pst$stage == st])))
write_csv(summ |> mutate(value = as.numeric(value)), "results/treatment_patterns_summary.csv")

# ---- OHDSI Data Quality Dashboard (local JSON; not committed) ----------------------------------------------------------------
dqd_path <- Sys.getenv("DQD_JSON", "")
if (nzchar(dqd_path) && file.exists(dqd_path)) {
  d <- jsonlite::fromJSON(dqd_path, simplifyVector = FALSE)$CheckResults
  g <- function(r, k, default = NA) { v <- r[[k]]; if (is.null(v)) default else v }
  df <- bind_rows(lapply(d, function(r) tibble(category = g(r, "category"), check = g(r, "checkName"), table = g(r, "cdmTableName"), field = g(r, "cdmFieldName", ""),
          failed = g(r, "failed", 0), passed = g(r, "passed", 0), is_error = g(r, "isError", 0), not_applicable = g(r, "notApplicable", 0),
          violated = g(r, "numViolatedRows", NA), denom = g(r, "numDenominatorRows", NA))))
  df$status <- with(df, ifelse(is_error == 1, "errored", ifelse(not_applicable == 1, "not applicable", ifelse(failed == 1, "failed", "passed"))))
  write_csv(df |> count(category, status) |> pivot_wider(names_from = status, values_from = n, values_fill = 0L) |> mutate(total = rowSums(across(where(is.numeric)))), "results/dqd_summary.csv")
  cause <- function(check, table, field) case_when(
    table %in% c("COHORT", "COHORT_DEFINITION") ~ "optional table absent",
    table == "DRUG_ERA" ~ "ETL (deliberate: step skipped)",
    check == "isStandardValidConcept" | (table == "DRUG_EXPOSURE" & field == "QUANTITY") ~ "ETL",
    table == "DRUG_EXPOSURE" & field == "DAYS_SUPPLY" ~ "ETL / Synthea",
    table == "CONDITION_OCCURRENCE" & field == "CONDITION_STATUS_CONCEPT_ID" ~ "ETL",
    table == "OBSERVATION" & field == "UNIT_CONCEPT_ID" ~ "ETL",
    table == "DRUG_STRENGTH" ~ "vocabulary release",
    TRUE ~ "Synthea")
  fl <- df |> filter(status == "failed") |> mutate(pct_violated = round(100 * violated / denom, 1), cause = cause(check, table, field),
        touches_cohort_source_table = table %in% c("PERSON", "CONDITION_OCCURRENCE", "DEATH", "OBSERVATION_PERIOD")) |>
    select(category, check, table, field, violated, denom, pct_violated, cause, touches_cohort_source_table)
  write_csv(fl, "results/dqd_failures.csv")
  tb <- df |> filter(table %in% c("PERSON", "CONDITION_OCCURRENCE", "DEATH", "OBSERVATION_PERIOD")) |> count(table, status) |> pivot_wider(names_from = status, values_from = n, values_fill = 0L)
  write_csv(tb, "results/dqd_cohort_tables.csv")
  cat("DQD results written (", nrow(df), "checks).\n")
} else cat("DQD_JSON not set or not found: the committed results/dqd_*.csv files are left unchanged.\n")
dbDisconnect(con)
cat("Report inputs written to results/.\n")
