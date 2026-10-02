# SEER age x sex by stage, the Synthea vs SEER demographics comparison, and a direct-standardisation (reweighting)
# sensitivity analysis of the Kaplan-Meier survival curves. Run from the repository root:
#   Rscript analysis/seer_age_sex_reweighting.R
#
# SEER input: the local SEER*Stat frequency export seer/nsclc_age_sex_by_stage_2010-2015.csv (NSCLC diagnosed 2010-2015,
#   age 50+). It is NOT in the repository. Only its Cumulative Summary (lines 1-316; patient counts N) is read: the
#   life tables that follow contain small monthly counts that must never be published, so they are never read or printed.
#   Codes: stage 0-4 = I, II, III, IV, Unknown; sex 0 = both, 1 = male, 2 = female; age code 11-13 = 50-64, 14-15 = 65-74,
#   16-17 = 75-84, 18-19 = 85+ (20 = unknown age, 0 patients).
# Outputs: seer/nsclc_age_sex_by_stage_summary.csv (counts and percentages; every count >= 16 is asserted),
#   results/demographics_synthea_vs_seer.csv, results/km_synthea_vs_seer_reweighted.csv,
#   results/age_sex_reweighting_console_output.txt
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(survival); library(dplyr); library(tidyr); library(readr) })
options(width = 200, digits = 5)
dir.create("results", showWarnings = FALSE)
log_con <- file("results/age_sex_reweighting_console_output.txt", open = "wt"); sink(log_con, split = TRUE)
STAGES <- c("I", "II", "III", "IV"); BANDS <- c("50-64", "65-74", "75-84", "85+")
TIMES <- c(12, 24, 36, 48, 60)

# ---- 1. SEER age x sex x stage counts: Cumulative Summary only ---------------------------------------------------------------
f <- "seer/nsclc_age_sex_by_stage_2010-2015.csv"
if (!file.exists(f)) stop("The local SEER*Stat export ", f, " is needed (it is not in the repository).")
summ <- read_csv(I(readLines(f, n = 316)), show_col_types = FALSE) |>      # lines 1-316 only
  transmute(stage_code = .data[["Stage I-IV (AJCC 7th grouped)"]], age_code = .data[["Age recode with <1 year olds and 90+"]],
            sex_code = Sex, n = N)
stopifnot(nrow(summ) == 315, all(summ$n[summ$age_code < 11 | summ$age_code == 20] == 0))
stage_names <- c("0" = "I", "1" = "II", "2" = "III", "3" = "IV", "4" = "Unknown")
band_of <- function(a) ifelse(a %in% 11:13, "50-64", ifelse(a %in% 14:15, "65-74", ifelse(a %in% 16:17, "75-84", ifelse(a %in% 18:19, "85+", NA))))
sex_names <- c("0" = "both", "1" = "male", "2" = "female")
cells <- summ |> filter(!is.na(band_of(age_code))) |>
  mutate(stage = stage_names[as.character(stage_code)], age_band = band_of(age_code), sex = sex_names[as.character(sex_code)]) |>
  group_by(stage, age_band, sex) |> summarise(n = sum(n), .groups = "drop")
# internal consistency: both = male + female in every cell
chk <- cells |> pivot_wider(names_from = sex, values_from = n); stopifnot(all(chk$both == chk$male + chk$female))
# add the all-ages rows, and the percentages
all_ages <- cells |> group_by(stage, sex) |> summarise(n = sum(n), age_band = "All 50+", .groups = "drop")
out <- bind_rows(cells, all_ages)
stage_tot <- out |> filter(age_band == "All 50+", sex == "both") |> select(stage, stage_total = n)
out <- out |> left_join(stage_tot, by = "stage") |>
  mutate(pct_of_stage = round(100 * n / stage_total, 2)) |> select(stage, age_band, sex, n, pct_of_stage) |>
  arrange(factor(stage, levels = c(STAGES, "Unknown")), factor(age_band, levels = c(BANDS, "All 50+")), factor(sex, levels = c("both", "male", "female")))
cat("SEER counts: totals by stage (both sexes):\n"); print(as.data.frame(stage_tot), row.names = FALSE)
cat(sprintf("Smallest count in the output file: %d (must be >= 16); cells: %d\n", min(out$n), nrow(out)))
stopifnot(min(out$n) >= 16)                                                # DUA: no count under 16 may be published
write_csv(out, "seer/nsclc_age_sex_by_stage_summary.csv")

seer_cell <- cells |> filter(stage %in% STAGES, sex != "both")           # male and female cells, I-IV
seer_stage_n <- stage_tot |> filter(stage %in% STAGES)

# ---- 2. Synthea cohorts --------------------------------------------------------------------------------------------------------
if (!nzchar(Sys.getenv("PG_HOST"))) readRenviron(".Renviron")
con <- dbConnect(Postgres(), host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT")),
                 dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"))
mart <- dbGetQuery(con, "select * from dbt.mart_nsclc_cohort"); dbDisconnect(con)
mart <- mart |> mutate(followup_months = as.numeric(followup_months), event = as.integer(event), age_at_dx = as.numeric(age_at_dx),
  stage = factor(stage, levels = STAGES), sexl = ifelse(sex == "M", "male", "female"),
  age_band = cut(age_at_dx, c(50, 65, 75, 85, Inf), right = FALSE, labels = BANDS))
stopifnot(!anyNA(mart$age_band))
cohorts <- list(main = mart, sensitivity = filter(mart, dx_2010_2015))

# ---- 3. demographics, Synthea vs SEER ------------------------------------------------------------------------------------------
dem_one <- function(d_synthea, seer_cells, label) {
  syn_n <- nrow(d_synthea); sn <- sum(seer_cells$n[seer_cells$sex == "male"]) + sum(seer_cells$n[seer_cells$sex == "female"])
  syn_band <- table(factor(d_synthea$age_band, levels = BANDS)) / syn_n * 100
  seer_band <- sapply(BANDS, function(b) sum(seer_cells$n[seer_cells$age_band == b])) / sn * 100
  tibble(stage = label, synthea_n = syn_n, seer_n = sn,
         synthea_pct_male = 100 * mean(d_synthea$sexl == "male"), seer_pct_male = 100 * sum(seer_cells$n[seer_cells$sex == "male"]) / sn,
         synthea_pct_50_64 = syn_band[[1]], seer_pct_50_64 = seer_band[[1]], synthea_pct_65_74 = syn_band[[2]], seer_pct_65_74 = seer_band[[2]],
         synthea_pct_75_84 = syn_band[[3]], seer_pct_75_84 = seer_band[[3]], synthea_pct_85plus = syn_band[[4]], seer_pct_85plus = seer_band[[4]])
}
dem <- bind_rows(lapply(names(cohorts), function(nm) {
  d <- cohorts[[nm]]
  bind_rows(lapply(STAGES, function(st) dem_one(filter(d, stage == st), filter(seer_cell, stage == st), st)),
            dem_one(d, seer_cell, "All staged (I-IV)")) |> mutate(cohort = nm, .before = 1)
}))
dem_out <- dem |> mutate(diff_pct_male_pp = synthea_pct_male - seer_pct_male, diff_50_64_pp = synthea_pct_50_64 - seer_pct_50_64,
  diff_65_74_pp = synthea_pct_65_74 - seer_pct_65_74, diff_75_84_pp = synthea_pct_75_84 - seer_pct_75_84, diff_85plus_pp = synthea_pct_85plus - seer_pct_85plus) |>
  mutate(across(where(is.numeric) & !c(synthea_n, seer_n), ~ round(.x, 1)))
write_csv(dem_out, "results/demographics_synthea_vs_seer.csv")
cat("\n==== DEMOGRAPHICS, Synthea vs SEER (percent; SEER = diagnosed 2010-2015, age 50+, known stage) ====\n")
print(as.data.frame(dem_out |> select(cohort, stage, synthea_n, seer_n, synthea_pct_male, seer_pct_male, synthea_pct_50_64, seer_pct_50_64,
  synthea_pct_65_74, seer_pct_65_74, synthea_pct_75_84, seer_pct_75_84, synthea_pct_85plus, seer_pct_85plus)), row.names = FALSE)

# ---- 4. direct standardisation of the main cohort to SEER's age x sex distribution within each stage -------------------------------
make_weights <- function(d, merge_75plus) {
  d <- d |> mutate(cell_band = if (merge_75plus) ifelse(age_band %in% c("75-84", "85+"), "75+", as.character(age_band)) else as.character(age_band))
  sc <- seer_cell |> mutate(cell_band = if (merge_75plus) ifelse(age_band %in% c("75-84", "85+"), "75+", age_band) else age_band) |>
    group_by(stage, cell_band, sex) |> summarise(seer_n = sum(n), .groups = "drop")
  syn_cells <- d |> count(stage, cell_band, sexl, name = "syn_n") |> rename(sex = sexl)
  cc <- full_join(sc, syn_cells, by = c("stage", "cell_band", "sex")) |> mutate(syn_n = coalesce(syn_n, 0L))
  cc <- cc |> group_by(stage) |> mutate(seer_prop = seer_n / sum(seer_n), supported = syn_n > 0,
                                        seer_prop_used = ifelse(supported, seer_n, 0) / sum(ifelse(supported, seer_n, 0)),
                                        coverage = sum(seer_prop[supported])) |> ungroup()
  d |> left_join(cc |> select(stage, cell_band, sex, syn_n, seer_prop_used), by = c("stage", "cell_band", "sexl" = "sex")) |>
    group_by(stage) |> mutate(w = seer_prop_used * n() / syn_n) |> ungroup() |> list(cells = cc)
}
wt_runs <- list("4 age bands" = FALSE, "3 age bands (75+ merged)" = TRUE)
weights_list <- lapply(wt_runs, function(m) make_weights(cohorts$main, m))
cat("\n==== REWEIGHTING: coverage and weight diagnostics (main cohort) ====\n")
cat("Cells where SEER has patients but Synthea has none cannot be weighted: they are dropped and SEER's distribution is renormalised over the supported cells.\n")
for (nm in names(weights_list)) {
  w <- weights_list[[nm]]; cc <- w$cells
  cat(sprintf("\n-- %s\n", nm))
  print(as.data.frame(cc |> filter(!supported) |> select(stage, cell_band, sex, seer_n, syn_n)), row.names = FALSE)
  d <- w[[1]]
  diag <- d |> group_by(stage) |> summarise(n = n(), seer_share_covered_pct = round(100 * first(cc$coverage[cc$stage == first(stage)]), 1),
    max_weight = round(max(w), 2), min_weight = round(min(w), 2), effective_n = round(sum(w)^2 / sum(w^2), 0), .groups = "drop")
  print(as.data.frame(diag), row.names = FALSE)
}

km_at <- function(d, weighted) {
  fit <- if (weighted) survfit(Surv(followup_months, event) ~ stage, data = d, weights = w, id = person_id, robust = TRUE, conf.type = "log-log")
         else survfit(Surv(followup_months, event) ~ stage, data = d, conf.type = "log-log")
  unw <- survfit(Surv(followup_months, event) ~ stage, data = d)           # unweighted number at risk, for the S = 0 rule
  s <- summary(fit, times = TIMES, extend = TRUE); u <- summary(unw, times = TIMES, extend = TRUE)
  s_end <- vapply(split(fit$surv, rep(sub("stage=", "", names(fit$strata)), fit$strata)), function(v) tail(v, 1), numeric(1))
  tibble(stage = sub("stage=", "", as.character(s$strata)), months = s$time, n_risk = u$n.risk, S = s$surv, lo = s$lower, hi = s$upper) |>
    mutate(ends0 = unname(s_end[stage]) < 1e-9,
           across(c(S, lo, hi), ~ case_when(n_risk == 0 & ends0 ~ 0, n_risk == 0 ~ NA_real_, TRUE ~ .x)))
}
seer_km <- read_csv("seer/nsclc_survival_by_stage_summary.csv", show_col_types = FALSE) |>
  filter(months %in% TIMES) |> transmute(stage, months, seer_S = observed_survival_pct)
unw <- km_at(cohorts$main, FALSE)
rw <- bind_rows(lapply(names(weights_list), function(nm) km_at(weights_list[[nm]][[1]], TRUE) |> mutate(weighting = nm)))
fmt <- function(s, lo, hi) ifelse(is.na(s), NA_character_, sprintf("%.1f (%.1f-%.1f)", 100 * s, 100 * lo, 100 * hi))
res <- rw |> left_join(unw |> select(stage, months, u_S = S, u_lo = lo, u_hi = hi, u_n = n_risk), by = c("stage", "months")) |>
  left_join(seer_km, by = c("stage", "months")) |>
  mutate(stage = factor(stage, levels = STAGES), year = months / 12,
         unweighted_S_ci = fmt(u_S, u_lo, u_hi), reweighted_S_ci = fmt(S, lo, hi),
         change_pp = round(100 * (S - u_S), 1), diff_to_seer_unweighted_pp = round(100 * u_S - seer_S, 1), diff_to_seer_reweighted_pp = round(100 * S - seer_S, 1)) |>
  transmute(weighting, stage, year, synthea_n_at_risk_unweighted = u_n, unweighted_S_pct = round(100 * u_S, 1), unweighted_S_ci,
            reweighted_S_pct = round(100 * S, 1), reweighted_S_ci, change_pp, seer_S_pct = seer_S, diff_to_seer_unweighted_pp, diff_to_seer_reweighted_pp) |>
  arrange(factor(weighting, levels = names(wt_runs)), stage, year)
write_csv(res, "results/km_synthea_vs_seer_reweighted.csv", na = "")
cat("\n==== WEIGHTED KAPLAN-MEIER AT YEARS 1-5 (main cohort; S in %, 95% log-log CI from a robust variance) ====\n")
print(as.data.frame(res |> select(weighting, stage, year, synthea_n_at_risk_unweighted, unweighted_S_ci, reweighted_S_ci, change_pp, seer_S_pct)), row.names = FALSE)
cat("\n==== CHANGE IN 5-YEAR SURVIVAL AFTER REWEIGHTING (percentage points) ====\n")
print(as.data.frame(res |> filter(year == 5) |> select(weighting, stage, unweighted_S_pct, reweighted_S_pct, change_pp, seer_S_pct)), row.names = FALSE)
sink(); close(log_con)
