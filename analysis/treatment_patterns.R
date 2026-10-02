# Descriptive treatment patterns in the NSCLC main cohort (dbt.mart_nsclc_cohort, n = 1,347), from drug_exposure and
# procedure_occurrence. Descriptive only: no line-of-therapy logic. Run from the repository root:
#   Rscript analysis/treatment_patterns.R
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(dplyr); library(tidyr) })
options(width = 200, digits = 4, dplyr.summarise.inform = FALSE)
if (!nzchar(Sys.getenv("PG_HOST"))) readRenviron(".Renviron")
con <- dbConnect(Postgres(), host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT")),
                 dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"))
q <- function(sql) dbGetQuery(con, sql)
STAGES <- c("I", "II", "III", "IV")
hdr <- function(x) cat("\n====", x, "====\n")

cohort <- q("select person_id, index_date, stage, sex, event from dbt.mart_nsclc_cohort") |> mutate(stage = factor(stage, STAGES))
N <- nrow(cohort)

# ---- antineoplastic / endocrine anticancer ingredients (ATC L01, L02) received by cohort members -----------------------
anti <- q("
  select de.person_id, de.drug_exposure_start_date as d, ing.concept_name as ingredient
  from cdm.drug_exposure de
  join dbt.mart_nsclc_cohort m using (person_id)
  join cdm.concept_ancestor ci on ci.descendant_concept_id = de.drug_concept_id
  join cdm.concept ing on ing.concept_id = ci.ancestor_concept_id and ing.concept_class_id = 'Ingredient'
  where exists (select 1 from cdm.concept_ancestor ca2
                join cdm.concept atc on atc.concept_id = ca2.ancestor_concept_id and atc.vocabulary_id = 'ATC'
                     and (atc.concept_code like 'L01%' or atc.concept_code like 'L02%')
                where ca2.descendant_concept_id = ing.concept_id)") |>
  mutate(d = as.Date(d)) |> distinct()
rad <- q("
  select po.person_id, po.procedure_date as d, po.procedure_source_value as code, c.concept_name as proc
  from cdm.procedure_occurrence po join dbt.mart_nsclc_cohort m using (person_id)
  join cdm.concept c on c.concept_id = po.procedure_concept_id
  where po.procedure_source_value in ('703423002', '33195004', '367336001', '394894008')") |> mutate(d = as.Date(d))
all_ing <- q("select count(distinct ing.concept_id) n from cdm.drug_exposure de join dbt.mart_nsclc_cohort m using (person_id)
              join cdm.concept_ancestor ci on ci.descendant_concept_id = de.drug_concept_id
              join cdm.concept ing on ing.concept_id = ci.ancestor_concept_id and ing.concept_class_id = 'Ingredient'")$n |> as.integer()
CORE <- c("cisplatin", "paclitaxel")                       # the NSCLC-directed agents in the Synthea module
idx <- cohort |> transmute(person_id, index_date = as.Date(index_date))
anti_all <- anti; rad_all <- rad
anti <- anti |> inner_join(idx, by = "person_id") |> filter(d >= index_date) |> select(-index_date)   # treatment = on or after the NSCLC index date
rad  <- rad  |> inner_join(idx, by = "person_id") |> filter(d >= index_date) |> select(-index_date)
pre_anti <- anti_all |> inner_join(idx, by = "person_id") |> filter(d < index_date)
pre_rad  <- rad_all  |> inner_join(idx, by = "person_id") |> filter(d < index_date)
hdr("0. EVENTS BEFORE THE NSCLC INDEX DATE (excluded from everything below: earlier cancers or hormone preparations)")
cat(sprintf("patients with any anticancer-ingredient exposure before the index date: %d (%.1f%%); with a chemotherapy/radiation procedure before the index date: %d (%.1f%%)
",
    n_distinct(pre_anti$person_id), 100 * n_distinct(pre_anti$person_id) / N, n_distinct(pre_rad$person_id), 100 * n_distinct(pre_rad$person_id) / N))
cat("pre-index procedures by code and how many days before the index date (median, range):
")
print(as.data.frame(pre_rad |> mutate(days_before = as.numeric(index_date - d)) |> group_by(proc) |>
  summarise(patients = n_distinct(person_id), median_days_before = median(days_before), min_days_before = min(days_before), max_days_before = max(days_before))), row.names = FALSE)

hdr("1. INGREDIENTS")
cat(sprintf("Distinct drug ingredients of any kind received by the %d patients: %d (mostly vaccines, cardiovascular and other chronic-disease drugs).\n", N, all_ing))
cat("Antineoplastic or endocrine anticancer ingredients (ATC L01 / L02): patients, administrations (distinct person-date-ingredient)\n")
ing_tab <- anti |> group_by(ingredient) |> summarise(patients = n_distinct(person_id), administrations = n(), pct_of_cohort = round(100 * n_distinct(person_id) / N, 1)) |>
  arrange(desc(patients)); print(as.data.frame(ing_tab), row.names = FALSE)

# ---- per-patient treatment summaries -----------------------------------------------------------------------------------------
core <- anti |> filter(ingredient %in% CORE)
per <- cohort |>
  left_join(core |> group_by(person_id) |> summarise(first_sys = min(d), last_sys = max(d), n_dates = n_distinct(d), n_core_ing = n_distinct(ingredient)), by = "person_id") |>
  left_join(anti |> group_by(person_id) |> summarise(first_anyanti = min(d), n_anti_ing = n_distinct(ingredient)), by = "person_id") |>
  left_join(rad |> filter(code == "703423002") |> group_by(person_id) |> summarise(first_cxrt = min(d), n_cxrt = n()), by = "person_id") |>
  left_join(rad |> filter(code == "33195004") |> group_by(person_id) |> summarise(n_ebrt = n()), by = "person_id") |>
  mutate(any_sys = !is.na(first_sys), any_rad = !is.na(first_cxrt) | !is.na(n_ebrt),
         days_to_sys = as.numeric(first_sys - index_date), days_to_rad = as.numeric(first_cxrt - index_date),
         first_tx = pmin(first_sys, first_cxrt, na.rm = TRUE), days_to_first_tx = as.numeric(first_tx - index_date),
         span_days = as.numeric(last_sys - first_sys))

hdr("2. SYSTEMIC TREATMENT AND RADIATION BY STAGE (core = cisplatin or paclitaxel; radiation = combined chemoradiation or external beam procedure)")
print(as.data.frame(per |> group_by(stage) |> summarise(n = n(), any_systemic_n = sum(any_sys), any_systemic_pct = round(100 * mean(any_sys), 1),
        any_radiation_n = sum(any_rad), any_radiation_pct = round(100 * mean(any_rad), 1),
        both_n = sum(any_sys & any_rad), neither_n = sum(!any_sys & !any_rad))), row.names = FALSE)
cat(sprintf("All: any systemic %d (%.1f%%), any radiation %d (%.1f%%), neither %d\n", sum(per$any_sys), 100 * mean(per$any_sys), sum(per$any_rad), 100 * mean(per$any_rad), sum(!per$any_sys & !per$any_rad)))
cat("Patients without a recorded systemic or radiation treatment:\n"); print(as.data.frame(per |> filter(!any_sys | !any_rad) |> select(person_id, stage, sex, any_sys, any_rad, n_cxrt, n_ebrt)), row.names = FALSE)

hdr("3. TIME FROM DIAGNOSIS TO FIRST TREATMENT (days)")
tt <- function(x) c(n = sum(!is.na(x)), median = median(x, na.rm = TRUE), q1 = unname(quantile(x, .25, na.rm = TRUE)), q3 = unname(quantile(x, .75, na.rm = TRUE)), min = min(x, na.rm = TRUE), max = max(x, na.rm = TRUE))
cat("first systemic (cisplatin/paclitaxel) after the index date:\n"); print(round(rbind(All = tt(per$days_to_sys), sapply(split(per$days_to_sys, per$stage), tt) |> t()), 1))
cat("first treatment of any kind (systemic or combined chemoradiation procedure):\n"); print(round(rbind(All = tt(per$days_to_first_tx), sapply(split(per$days_to_first_tx, per$stage), tt) |> t()), 1))
cat(sprintf("Patients whose first treatment is dated BEFORE the index date: %d\n", sum(per$days_to_first_tx < 0, na.rm = TRUE)))

hdr("4. REGIMENS PER PATIENT (regimen = the set of anticancer ingredients given on the same date)")
reg <- anti |> group_by(person_id, d) |> summarise(regimen = paste(sort(ingredient), collapse = " + "), .groups = "drop")
reg_pp <- reg |> group_by(person_id) |> summarise(n_regimens = n_distinct(regimen), regimens = paste(sort(unique(regimen)), collapse = " | "))
cat("distinct regimens per patient (all anticancer ingredients):\n"); print(table(factor(reg_pp$n_regimens)))
cat("most common regimen sets across patients:\n"); print(as.data.frame(reg_pp |> count(regimens, sort = TRUE) |> head(8)), row.names = FALSE)
reg_core <- reg |> mutate(regimen_core = vapply(strsplit(regimen, " [+] "), function(x) paste(sort(intersect(x, CORE)), collapse = " + "), "")) |> filter(nzchar(regimen_core))
cat("regimens containing only the core agents, by date: how often each combination is given on a date\n"); print(table(reg_core$regimen_core))

hdr("5. GAPS BETWEEN ADMINISTRATIONS (core agents; consecutive distinct administration dates within a patient)")
gaps <- core |> distinct(person_id, d) |> arrange(person_id, d) |> group_by(person_id) |> mutate(gap = as.numeric(d - lag(d))) |> ungroup() |> filter(!is.na(gap))
cat(sprintf("administration dates per patient: median %.0f (IQR %.0f-%.0f), max %d; days between first and last administration: median %.0f (IQR %.0f-%.0f), max %.0f\n",
    median(per$n_dates, na.rm = TRUE), quantile(per$n_dates, .25, na.rm = TRUE), quantile(per$n_dates, .75, na.rm = TRUE), max(per$n_dates, na.rm = TRUE),
    median(per$span_days, na.rm = TRUE), quantile(per$span_days, .25, na.rm = TRUE), quantile(per$span_days, .75, na.rm = TRUE), max(per$span_days, na.rm = TRUE)))
cat("gap lengths (days) between consecutive administrations:\n"); print(round(quantile(gaps$gap, c(0, .01, .05, .25, .5, .75, .95, .99, 1)), 1))
gp <- gaps |> group_by(person_id) |> summarise(max_gap = max(gap), any_gt28 = any(gap > 28), any_gt90 = any(gap > 90))
cat(sprintf("patients with any gap > 28 days: %d (%.1f%% of treated); any gap > 90 days: %d (%.1f%%); largest gap %.0f days\n",
    sum(gp$any_gt28), 100 * mean(gp$any_gt28), sum(gp$any_gt90), 100 * mean(gp$any_gt90), max(gp$max_gap)))
cat("gap histogram (days): "); print(table(cut(gaps$gap, c(-1, 0, 1, 7, 14, 28, 60, 90, 180, 365, Inf))))

hdr("6. LINE-2 CANDIDATES UNDER THE PLAN.md RULES (a gap > 90 days, or a new drug started > 28 days after first treatment)")
first_any  <- anti |> group_by(person_id) |> summarise(first_d = min(d))
first_core <- core |> group_by(person_id) |> summarise(first_core_d = min(d))
newdrug <- anti |> inner_join(first_any, by = "person_id") |> group_by(person_id, ingredient) |> summarise(first_ing = min(d), first_d = first(first_d), .groups = "drop") |>
  mutate(lag_days = as.numeric(first_ing - first_d)) |> filter(lag_days > 28)
newcore <- core |> inner_join(first_core, by = "person_id") |> group_by(person_id, ingredient) |> summarise(first_ing = min(d), first_core_d = first(first_core_d), .groups = "drop") |>
  mutate(lag_days = as.numeric(first_ing - first_core_d)) |> filter(lag_days > 28)
cand_new_all  <- unique(newdrug$person_id)
cand_new_core <- unique(newcore$person_id)
cand_gap      <- gp$person_id[gp$any_gt90]
cat(sprintf("naive rule, ANY anticancer/endocrine ingredient after the index date: new drug > 28 days after the first: %d patients (%.1f%%); gap > 90 days (core agents): %d (%.1f%%); either: %d (%.1f%%)
",
    length(cand_new_all), 100 * length(cand_new_all) / N, length(cand_gap), 100 * length(cand_gap) / N, length(union(cand_new_all, cand_gap)), 100 * length(union(cand_new_all, cand_gap)) / N))
cat(sprintf("restricted to the NSCLC-directed agents (cisplatin, paclitaxel), measured from the first cisplatin/paclitaxel date: new core drug > 28 days after the first: %d; gap > 90 days: %d; either: %d (%.1f%%)
",
    length(cand_new_core), length(cand_gap), length(union(cand_new_core, cand_gap)), 100 * length(union(cand_new_core, cand_gap)) / N))
cat("which ingredients create the 'new drug > 28 days' candidates:\n"); print(as.data.frame(newdrug |> count(ingredient, sort = TRUE) |> mutate(pct_of_cohort = round(100 * n / N, 1))), row.names = FALSE)
oth <- anti |> filter(!ingredient %in% CORE)
cat("\nthose non-core ingredients: sex of recipients and co-administered drugs (are they another cancer's regimen?)\n")
print(as.data.frame(oth |> inner_join(cohort |> select(person_id, sex), by = "person_id") |> group_by(ingredient) |> summarise(patients = n_distinct(person_id), pct_male = round(100 * mean(sex[!duplicated(person_id)] == "M"), 0),
        same_day_as_leuprolide = n_distinct(person_id[person_id %in% (anti$person_id[anti$ingredient == "leuprolide"])])) |> arrange(desc(patients)) |> head(8)), row.names = FALSE)
dl <- anti |> filter(ingredient == "docetaxel") |> inner_join(anti |> filter(ingredient == "leuprolide"), by = c("person_id", "d"))
cat(sprintf("docetaxel administrations on the same date as leuprolide: %d of %d docetaxel administrations; patients with both: %d of %d docetaxel patients\n",
    nrow(dl), sum(anti$ingredient == "docetaxel"), n_distinct(dl$person_id), n_distinct(anti$person_id[anti$ingredient == "docetaxel"])))

hdr("7. IS TREATMENT TYPE DETERMINED BY STAGE? (first-line type: chemoradiation if the combined procedure is within 28 days of the first systemic, else chemotherapy alone, else none)")
per <- per |> mutate(first_line = case_when(
  any_sys & !is.na(first_cxrt) & abs(as.numeric(first_cxrt - first_sys)) <= 28 ~ "chemotherapy + radiation",
  any_sys ~ "chemotherapy alone", !any_sys & any_rad ~ "radiation only", TRUE ~ "none recorded"))
tab <- table(Stage = per$stage, `First-line type` = per$first_line); print(tab)
cat("row percentages:\n"); print(round(100 * prop.table(tab, 1), 1))
cat(sprintf("Cramer's V (stage vs first-line type): %.3f; chi-square p = %s\n", {ct <- suppressWarnings(chisq.test(tab)); sqrt(ct$statistic / (sum(tab) * (min(dim(tab)) - 1)))},
    format.pval(suppressWarnings(chisq.test(tab))$p.value, digits = 3)))
cat(sprintf("patients in the largest first-line group: %d of %d (%.1f%%)\n", max(table(per$first_line)), N, 100 * max(table(per$first_line)) / N))
cat("treatment intensity, if everyone is treated alike: administrations (dates) per patient by stage\n")
print(as.data.frame(per |> group_by(stage) |> summarise(median_dates = median(n_dates, na.rm = TRUE), q1 = quantile(n_dates, .25, na.rm = TRUE), q3 = quantile(n_dates, .75, na.rm = TRUE),
        median_span_days = median(span_days, na.rm = TRUE), pct_died = round(100 * mean(event), 0))), row.names = FALSE)
dbDisconnect(con)
