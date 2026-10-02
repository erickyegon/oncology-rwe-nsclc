# Kaplan-Meier overall survival by stage: Synthea NSCLC cohort (dbt mart) vs SEER observed survival.
# Run from the repository root:  Rscript analysis/km_synthea_vs_seer.R
#
# Synthea side : dbt.mart_nsclc_cohort (main cohort: staged NSCLC, age >= 50, censored at 120 months) and the
#                2010-2015 sensitivity cohort (dx_2010_2015). survfit(Surv(followup_months, event) ~ stage),
#                log(-log) confidence intervals (conf.type = "log-log"), as SEER*Stat uses.
# SEER side    : seer/nsclc_survival_by_stage_summary.csv ONLY (aggregate): observed survival S(t), SE, number at risk,
#                SEER's own exported 95% log(-log) confidence limits (months 12-60) and SEER's exact median observed
#                survival by stage. Nothing is recomputed for SEER.
# Outputs      : results/km_synthea_vs_seer.csv, results/km_median_survival_by_stage.csv,
#                results/km_followup_by_stage.csv, results/km_demographics_by_stage.csv,
#                results/km_console_output.txt, results/sessionInfo.txt, figures/km_synthea_vs_seer.png

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(survival)
  library(dplyr); library(tidyr); library(readr); library(ggplot2)
})
options(width = 200, digits = 5)
dir.create("results", showWarnings = FALSE); dir.create("figures", showWarnings = FALSE)
log_con <- file("results/km_console_output.txt", open = "wt"); sink(log_con, split = TRUE)

STAGES <- c("I", "II", "III", "IV")
TIMES  <- c(12, 24, 36, 48, 60)          # months: years 1-5

# ---- data -------------------------------------------------------------------------------------------------------
if (!nzchar(Sys.getenv("PG_HOST"))) readRenviron(".Renviron")
con <- dbConnect(Postgres(), host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT")),
                 dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"))
mart <- dbGetQuery(con, "select * from dbt.mart_nsclc_cohort")
dbDisconnect(con)
mart <- mart |> mutate(stage = factor(stage, levels = STAGES), followup_months = as.numeric(followup_months),
                       event = as.integer(event), age_at_dx = as.numeric(age_at_dx))
cohorts <- list(main = mart, sensitivity = filter(mart, dx_2010_2015))

seer <- read_csv("seer/nsclc_survival_by_stage_summary.csv", show_col_types = FALSE) |>
  mutate(S = observed_survival_pct / 100, se = se_pct / 100, lo = ci_lower_pct / 100, hi = ci_upper_pct / 100)

cat("==== COHORTS ====\n")
for (nm in names(cohorts)) {
  d <- cohorts[[nm]]
  cat(sprintf("%-12s n = %d, deaths = %d, censored = %d, max follow-up = %.1f months\n", nm, nrow(d), sum(d$event),
              sum(1 - d$event), max(d$followup_months)))
  print(d |> count(stage) |> mutate(pct = round(100 * n / sum(n), 1)), row.names = FALSE)
}

# ---- KM fits ----------------------------------------------------------------------------------------------------
fits <- lapply(cohorts, function(d) survfit(Surv(followup_months, event) ~ stage, data = d, conf.type = "log-log"))

# ---- comparison table: stage x year 1-5 -------------------------------------------------------------------------
RULE <- paste("Rule: S(t) comes from summary(fit, times = c(12, 24, 36, 48, 60), extend = TRUE). If nobody is at risk at t and",
              "the curve has already reached 0 (it ends on a death), S(t) = 0 with n at risk = 0 (CI shown as 0-0). A cell",
              "is left blank only if nobody is at risk at t and the curve ends on a censoring (S > 0 at its last",
              "observation), where survival at t is not estimable.")
cat("\n", RULE, "\n", sep = "")
syn_at <- function(fit, cohort) {
  s <- summary(fit, times = TIMES, extend = TRUE)
  strata_all <- rep(sub("stage=", "", names(fit$strata)), fit$strata)
  s_end <- vapply(split(fit$surv, strata_all), function(v) tail(v, 1), numeric(1))   # last KM value of each curve
  tibble(cohort = cohort, stage = sub("stage=", "", as.character(s$strata)), months = s$time, n_risk = s$n.risk,
         S = s$surv, lo = s$lower, hi = s$upper) |>
    mutate(ends_in_death = unname(s_end[stage]) == 0,
           note = case_when(
             n_risk == 0 & ends_in_death  ~ "S = 0: the curve ended on a death before this time (n at risk = 0; CI 0-0)",
             n_risk == 0 & !ends_in_death ~ "blank: the curve ends on a censoring before this time, so survival is not estimable",
             TRUE ~ ""),
           S  = case_when(n_risk == 0 & ends_in_death ~ 0, n_risk == 0 ~ NA_real_, TRUE ~ S),
           lo = case_when(n_risk == 0 & ends_in_death ~ 0, n_risk == 0 ~ NA_real_, TRUE ~ lo),
           hi = case_when(n_risk == 0 & ends_in_death ~ 0, n_risk == 0 ~ NA_real_, TRUE ~ hi))
}
syn <- bind_rows(lapply(names(fits), function(nm) syn_at(fits[[nm]], nm)))
fmt <- function(s, lo, hi) ifelse(is.na(s), NA_character_, sprintf("%.1f (%.1f-%.1f)", 100 * s, 100 * lo, 100 * hi))
cmp <- syn |>
  left_join(seer |> filter(months %in% TIMES) |>
              transmute(stage, months, seer_n_at_risk = n_at_risk, seer_S = S, seer_se = se, seer_lo = lo, seer_hi = hi),
            by = c("stage", "months")) |>
  mutate(year = months / 12,
         diff_pp = round(100 * (S - seer_S), 1),
         seer_outside_synthea_ci = ifelse(is.na(S), NA, seer_S < lo | seer_S > hi)) |>
  transmute(cohort, stage = factor(stage, levels = STAGES), year, months,
            synthea_n_at_risk = n_risk,
            synthea_S_pct = round(100 * S, 1), synthea_ci_lo_pct = round(100 * lo, 1), synthea_ci_hi_pct = round(100 * hi, 1),
            synthea_S_ci = fmt(S, lo, hi),
            seer_n_at_risk,
            seer_S_pct = round(100 * seer_S, 1), seer_se_pct = round(100 * seer_se, 1),
            seer_ci_lo_pct = round(100 * seer_lo, 1), seer_ci_hi_pct = round(100 * seer_hi, 1),
            seer_S_ci = fmt(seer_S, seer_lo, seer_hi),
            diff_pp, seer_outside_synthea_ci, note) |>
  arrange(factor(cohort, levels = c("main", "sensitivity")), stage, year)
write_csv(cmp, "results/km_synthea_vs_seer.csv", na = "")
cat("\n==== COMPARISON TABLE (results/km_synthea_vs_seer.csv) ====\n")
cat("S(t) in %, with 95% log-log CI. SEER values and CIs are SEER*Stat's own exported estimates. diff = Synthea - SEER, percentage points.\n")
print(as.data.frame(cmp |> select(cohort, stage, year, synthea_n_at_risk, synthea_S_ci, seer_n_at_risk, seer_S_ci, diff_pp,
                                  seer_outside_synthea_ci)), row.names = FALSE)
cat("\nCells with a note (see the 'note' column in the CSV):\n")
print(as.data.frame(cmp |> filter(note != "") |> count(cohort, note)), row.names = FALSE)

# ---- median survival, both sources -------------------------------------------------------------------------------
syn_med <- bind_rows(lapply(names(fits), function(nm) {
  tb <- summary(fits[[nm]])$table
  tibble(cohort = nm, stage = sub("stage=", "", rownames(tb)), synthea_n = tb[, "records"], synthea_events = tb[, "events"],
         synthea_median_months = tb[, "median"], synthea_median_lcl = tb[, "0.95LCL"], synthea_median_ucl = tb[, "0.95UCL"])
}))
seer_med <- seer |> filter(stage %in% STAGES) |> distinct(stage, seer_median_months = median_observed_survival_months)
med <- syn_med |> left_join(seer_med, by = "stage") |>
  mutate(stage = factor(stage, levels = STAGES), across(starts_with("synthea_median"), ~ round(.x, 1))) |>
  arrange(factor(cohort, levels = c("main", "sensitivity")), stage)
write_csv(med, "results/km_median_survival_by_stage.csv", na = "")
cat("\n==== MEDIAN SURVIVAL (months; results/km_median_survival_by_stage.csv) ====\n")
cat("Synthea: KM median with 95% log-log CI. SEER: exact median observed survival from the SEER*Stat export (first month with cumulative survival <= 50%).\n")
print(as.data.frame(med), row.names = FALSE)

# ---- log-rank test across stages within Synthea ------------------------------------------------------------------
cat("\n==== LOG-RANK TEST ACROSS STAGES (Synthea) ====\n")
for (nm in names(cohorts)) {
  lr <- survdiff(Surv(followup_months, event) ~ stage, data = cohorts[[nm]])
  p <- pchisq(lr$chisq, df = length(lr$n) - 1, lower.tail = FALSE)
  cat(sprintf("%-12s chi-square = %.1f on %d df, p = %s\n", nm, lr$chisq, length(lr$n) - 1,
              format.pval(p, digits = 3, eps = 1e-16)))
}

# ---- follow-up by stage -------------------------------------------------------------------------------------------
fu <- bind_rows(lapply(names(cohorts), function(nm) {
  d <- cohorts[[nm]]
  rk <- survfit(Surv(followup_months, 1 - event) ~ stage, data = d)           # reverse KM, used only to flag estimability
  med_rk <- summary(rk)$table[, "median"]
  d |> group_by(stage) |> summarise(n = n(), deaths = sum(event), .groups = "drop") |>
    mutate(cohort = nm, pct_followed_to_death = round(100 * deaths / n, 1),
           max_followup_months = as.numeric(tapply(d$followup_months, d$stage, max)[as.character(stage)]),
           median_followup = ifelse(is.na(med_rk[paste0("stage=", stage)]), "not estimable",
                                    sprintf("%.1f", med_rk[paste0("stage=", stage)])),
           .before = 1)
}))
fu$max_followup_months <- round(fu$max_followup_months, 1)
fu <- fu |> select(cohort, stage, n, deaths, pct_followed_to_death, max_followup_months, median_followup) |>
  arrange(factor(cohort, levels = c("main", "sensitivity")), stage)
write_csv(fu, "results/km_followup_by_stage.csv", na = "")
cat("\n==== FOLLOW-UP BY STAGE (results/km_followup_by_stage.csv) ====\n")
print(as.data.frame(fu), row.names = FALSE)
cat("'median follow-up not estimable' = the reverse-KM median is not reached, because fewer than half of the cohort is\n")
cat("censored (most patients are followed until death, so follow-up ends with the event, not with the study).\n")

# ---- age and sex mix by stage (background-mortality confounding) -------------------------------------------------
summ_age_sex <- function(d) tibble(
  n = nrow(d), deaths = sum(d$event), male_n = sum(d$sex == "M"), male_pct = round(100 * mean(d$sex == "M"), 1),
  age_mean = round(mean(d$age_at_dx), 1), age_sd = round(sd(d$age_at_dx), 1), age_median = round(median(d$age_at_dx), 1),
  age_q1 = round(quantile(d$age_at_dx, 0.25), 1), age_q3 = round(quantile(d$age_at_dx, 0.75), 1))
demo <- bind_rows(lapply(names(cohorts), function(nm) {
  d <- cohorts[[nm]]
  bind_rows(lapply(STAGES, function(st) bind_cols(tibble(stage = st), summ_age_sex(filter(d, stage == st)))),
            bind_cols(tibble(stage = "All"), summ_age_sex(d))) |> mutate(cohort = nm, .before = 1)
}))
write_csv(demo, "results/km_demographics_by_stage.csv", na = "")
cat("\n==== AGE AND SEX BY STAGE (Synthea; age at diagnosis in years) ====\n")
print(as.data.frame(demo), row.names = FALSE)
a <- summary(aov(age_at_dx ~ stage, data = cohorts$main))[[1]]
cat(sprintf("\nAge by stage, one-way ANOVA (main cohort): F = %.2f, p = %s\n", a[["F value"]][1], format.pval(a[["Pr(>F)"]][1], digits = 3)))
ct <- chisq.test(table(cohorts$main$stage, cohorts$main$sex))
cat(sprintf("Sex by stage, chi-square test (main cohort): X2 = %.2f on %d df, p = %s\n", ct$statistic, ct$parameter,
            format.pval(ct$p.value, digits = 3)))

# ---- figure: main cohort, one panel per stage ---------------------------------------------------------------------
fit_main <- fits$main
sm <- summary(fit_main, censored = FALSE)
km <- tibble(stage = sub("stage=", "", as.character(sm$strata)), t = sm$time / 12, S = sm$surv, lo = sm$lower, hi = sm$upper)
XMAX <- 6
stepify <- function(d, tmax_obs) {          # explicit step coordinates so the CI ribbon is a step ribbon too
  d <- arrange(d, t)
  d <- bind_rows(tibble(t = 0, S = 1, lo = 1, hi = 1), d)
  d$lo[d$S == 0] <- 0; d$hi[d$S == 0] <- 0  # a curve that has reached 0 has no uncertainty left
  d <- tidyr::fill(d, lo, hi, .direction = "down")
  n <- nrow(d)
  idx_prev <- c(1, as.vector(rbind(seq_len(n - 1), seq_len(n - 1) + 1)))
  out <- tibble(t = c(d$t[1], as.vector(rbind(d$t[-1], d$t[-1]))), S = d$S[idx_prev], lo = d$lo[idx_prev], hi = d$hi[idx_prev])
  last <- tail(out, 1)
  end_t <- if (last$S == 0) XMAX else tmax_obs          # ends in a death: carry the curve along 0 to the end of the axis
  if (last$t < end_t) out <- bind_rows(out, tibble(t = end_t, S = last$S, lo = last$lo, hi = last$hi))
  filter(out, t <= XMAX)
}
maxfu <- mart |> group_by(stage) |> summarise(tmax = min(max(followup_months) / 12, XMAX))
km_steps <- bind_rows(lapply(STAGES, function(st)
  stepify(filter(km, stage == st), maxfu$tmax[maxfu$stage == st]) |> mutate(stage = st)))
km_steps$stage <- factor(km_steps$stage, levels = STAGES)

risk <- summary(fit_main, times = 12 * (0:6), extend = TRUE)
risk_df <- tibble(stage = factor(sub("stage=", "", as.character(risk$strata)), levels = STAGES), t = risk$time / 12, n = risk$n.risk)
seer_pts <- seer |> filter(months %in% TIMES, stage %in% STAGES) |>
  transmute(stage = factor(stage, levels = STAGES), t = months / 12, S, lo, hi)
lab_syn  <- "Synthea (Kaplan-Meier, 95% log-log CI)"
lab_seer <- "SEER 17, observed survival"

p <- ggplot() +
  geom_ribbon(data = km_steps, aes(t, ymin = lo, ymax = hi, fill = lab_syn), alpha = 0.2) +
  geom_path(data = km_steps, aes(t, S, colour = lab_syn), linewidth = 0.6) +
  geom_pointrange(data = seer_pts, aes(t, S, ymin = lo, ymax = hi, colour = lab_seer), size = 0.35, linewidth = 0.5) +
  geom_text(data = risk_df, aes(t, -0.13, label = n), size = 2.8, colour = "grey25") +
  geom_text(data = tibble(stage = factor(STAGES, levels = STAGES), x = 0, y = -0.05, label = "Synthea number at risk"),
            aes(x, y, label = label), hjust = 0, size = 2.6, colour = "grey40") +
  facet_wrap(~ stage, nrow = 2, axes = "all_x", labeller = labeller(stage = function(x) paste("Stage", x))) +
  scale_colour_manual(NULL, values = setNames(c("#1f5fa8", "#d1495b"), c(lab_syn, lab_seer))) +
  scale_fill_manual(NULL, values = setNames("#1f5fa8", lab_syn), guide = "none") +
  scale_x_continuous(breaks = 0:6) +
  scale_y_continuous(breaks = seq(0, 1, 0.25), labels = scales::percent) +
  coord_cartesian(xlim = c(0, XMAX), ylim = c(-0.18, 1.02)) +
  labs(x = "Years since diagnosis", y = "Observed survival",
       caption = sprintf("Synthea: staged NSCLC, age >= 50 at diagnosis, n = %d. SEER 17: NSCLC diagnosed 2010-2015, age 50+; error bars are SEER's exported 95%% CI.", nrow(mart))) +
  theme_minimal() +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(), plot.caption = element_text(size = 8, colour = "grey35"))
ggsave("figures/km_synthea_vs_seer.png", p, width = 10, height = 6, dpi = 200, bg = "white")
cat("\nFigure saved: figures/km_synthea_vs_seer.png\n")

# ---- session info ----------------------------------------------------------------------------------------------
sink(); close(log_con)
writeLines(capture.output(sessionInfo()), "results/sessionInfo.txt")
cat("Done. Console output saved to results/km_console_output.txt; sessionInfo to results/sessionInfo.txt\n")
