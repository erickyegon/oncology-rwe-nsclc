# Restricted mean survival time (RMST) to 60 months by stage: Synthea vs SEER. Run from the repository root:
#   Rscript analysis/rmst.R
# Synthea: dbt.mart_nsclc_cohort (main cohort and the 2010-2015 sensitivity cohort); RMST from the Kaplan-Meier fit,
#   summary(survfit, rmean = 60), with a normal 95% CI (estimate +/- 1.96 se).
# SEER: the local monthly SEER*Stat life-table export seer/nsclc_survival_by_stage_2010-2015.csv. That file is NOT in the
#   repository (SEER's data use agreement does not allow publishing its small monthly counts); this script reads only the
#   cumulative observed-survival column, and only the resulting RMST values are written to results/.
#   RMST = area under the monthly observed-survival curve to 60 months, trapezoid rule over the 60 intervals, with survival 100%
#   at diagnosis (month 0).
# Output: results/rmst_synthea_vs_seer.csv
suppressPackageStartupMessages({ library(DBI); library(RPostgres); library(survival); library(dplyr); library(readr); library(stringr) })
options(width = 200, digits = 5)
TAU <- 60
STAGES <- c("I", "II", "III", "IV")
dir.create("results", showWarnings = FALSE)

if (!nzchar(Sys.getenv("PG_HOST"))) readRenviron(".Renviron")
con <- dbConnect(Postgres(), host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT")),
                 dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"))
mart <- dbGetQuery(con, "select * from dbt.mart_nsclc_cohort")
dbDisconnect(con)
mart <- mart |> mutate(stage = factor(stage, levels = STAGES), followup_months = as.numeric(followup_months), event = as.integer(event))
cohorts <- list(main = mart, sensitivity = filter(mart, dx_2010_2015))

# ---- Synthea: RMST from the KM fit ---------------------------------------------------------------------------------------------
syn <- bind_rows(lapply(names(cohorts), function(nm) {
  d <- cohorts[[nm]]
  fit <- survfit(Surv(followup_months, event) ~ stage, data = d)
  tb <- summary(fit, rmean = TAU)$table
  est <- tb[, grep("^[*]?rmean$", colnames(tb))]; se <- tb[, grep("se\\(rmean\\)", colnames(tb))]
  # independent check: area under the KM step function, integrated by hand
  chk <- vapply(STAGES, function(st) {
    s <- summary(fit[paste0("stage=", st)], censored = TRUE); t <- c(0, s$time[s$time < TAU], TAU); v <- c(1, s$surv[s$time < TAU])
    sum(diff(t) * v)
  }, numeric(1))
  stopifnot(all(abs(chk - est) < 1e-6))
  tibble(cohort = nm, stage = sub("stage=", "", rownames(tb)), n = tb[, "records"], synthea_rmst = est, se = se,
         lcl = pmax(est - 1.96 * se, 0), ucl = pmin(est + 1.96 * se, TAU))
}))

# ---- SEER: area under the monthly observed-survival curve --------------------------------------------------------------------
f <- "seer/nsclc_survival_by_stage_2010-2015.csv"
if (!file.exists(f)) stop("The local SEER*Stat monthly export ", f, " is needed (it is not in the repository).")
raw <- read_lines(f)
starts <- which(str_starts(raw, '"Page type"'))
life <- read_csv(I(raw[starts[2]:length(raw)]), show_col_types = FALSE) |>
  rename(stage_code = 2, month = Interval, surv = `Observed Survival (Cum)`) |>
  mutate(stage = c("0" = "I", "1" = "II", "2" = "III", "3" = "IV", "4" = "Unknown")[as.character(stage_code)],
         surv = parse_number(as.character(surv)) / 100) |>
  filter(stage %in% STAGES, month <= TAU) |> select(stage, month, surv)
seer <- bind_rows(lapply(STAGES, function(st) {
  s <- life |> filter(stage == st) |> arrange(month)
  stopifnot(identical(as.integer(s$month), 1:TAU))
  s_all <- c(1, s$surv)                                   # survival at months 0, 1, ..., 60
  tibble(stage = st, seer_rmst = sum((head(s_all, -1) + tail(s_all, -1)) / 2))   # trapezoid over 60 one-month intervals
}))

# ---- comparison table ------------------------------------------------------------------------------------------------------------
out <- syn |> left_join(seer, by = "stage") |>
  mutate(stage = factor(stage, levels = STAGES), difference_months = synthea_rmst - seer_rmst,
         synthea_rmst_ci = sprintf("%.1f (%.1f-%.1f)", synthea_rmst, lcl, ucl)) |>
  arrange(factor(cohort, levels = c("main", "sensitivity")), stage) |>
  transmute(cohort, stage, synthea_n = n, synthea_rmst_months = round(synthea_rmst, 2), synthea_ci_lo = round(lcl, 2), synthea_ci_hi = round(ucl, 2),
            synthea_rmst_ci, seer_rmst_months = round(seer_rmst, 2), difference_months = round(difference_months, 2))
write_csv(out, "results/rmst_synthea_vs_seer.csv")
cat(sprintf("RMST to %d months (months). Synthea: Kaplan-Meier, normal 95%% CI. SEER: area under the monthly observed-survival curve (trapezoid). difference = Synthea - SEER.\n\n", TAU))
print(as.data.frame(out |> select(cohort, stage, synthea_n, synthea_rmst_ci, seer_rmst_months, difference_months)), row.names = FALSE)
cat("\nCheck: the Synthea RMST equals the hand-integrated KM area in every stratum (asserted in the script).\n")
