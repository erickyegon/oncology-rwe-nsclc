# Invariants of the committed results files and their agreement with the README. These tests need no database and no SEER
# record-level data: they read only files that are in the repository. They check internal consistency, not scientific validity.
# Run from the repository root:  Rscript -e 'testthat::test_dir("tests/testthat")'
library(testthat)

repo <- normalizePath(file.path(getwd(), "..", ".."))
rd <- function(...) read.csv(file.path(repo, ...), stringsAsFactors = FALSE)
fmt <- function(x) format(x, big.mark = ",", trim = TRUE)

attr_ <- rd("results", "mart_cohort_attrition.csv")
step <- function(i) attr_$n_persons[attr_$step_order == i]
km_med <- rd("results", "km_median_survival_by_stage.csv")
readme <- paste(readLines(file.path(repo, "README.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")

test_that("cohort attrition arithmetic is consistent", {
  expect_equal(step(1), step(2))                        # everyone in the export has a lung cancer code
  expect_equal(step(3) + step(4), step(2))              # small cell + NSCLC = lung cancer
  expect_equal(step(5) + step(6), step(4))              # NSCLC without a single stage + staged = NSCLC
  expect_equal(step(7) + step(8), step(6))              # under 50 + main cohort = staged
  expect_lte(step(9), step(8))                          # the 2010-2015 sensitivity cohort is a subset of the main cohort
})

test_that("stage-level sample sizes add up to the cohorts in the attrition table", {
  expect_equal(sum(km_med$synthea_n[km_med$cohort == "main"]), step(8))
  expect_equal(sum(km_med$synthea_n[km_med$cohort == "sensitivity"]), step(9))
  expect_equal(sort(unique(km_med$stage)), c("I", "II", "III", "IV"))
})

test_that("Kaplan-Meier medians are ordered and well formed", {
  m <- km_med[km_med$cohort == "main", ]
  m <- m[match(c("I", "II", "III", "IV"), m$stage), ]
  expect_true(all(diff(m$synthea_median_months) < 0))   # survival shortens with stage in the synthetic data (scripted by Synthea)
  expect_true(all(km_med$synthea_events <= km_med$synthea_n))
  expect_true(all(km_med$synthea_median_lcl <= km_med$synthea_median_months & km_med$synthea_median_months <= km_med$synthea_median_ucl))
})

test_that("Synthea and SEER survival curves are non-increasing and within 0-100", {
  km <- rd("results", "km_synthea_vs_seer.csv")
  for (g in split(km, list(km$cohort, km$stage), drop = TRUE)) {
    g <- g[order(g$months), ]
    expect_true(all(diff(g$synthea_S_pct) <= 1e-9), info = paste(g$cohort[1], g$stage[1], "Synthea"))
    expect_true(all(diff(g$seer_S_pct) <= 1e-9), info = paste(g$cohort[1], g$stage[1], "SEER"))
    expect_true(all(g$synthea_S_pct >= 0 & g$synthea_S_pct <= 100))
    expect_true(all(g$synthea_ci_lo_pct <= g$synthea_S_pct & g$synthea_S_pct <= g$synthea_ci_hi_pct))
  }
})

test_that("SEER stage mix inputs add up and the module shares are scaled copies", {
  mix <- rd("seer", "nsclc_stage_mix_2010-2015.csv")
  expect_equal(sum(mix$seer_share_pct), 100, tolerance = 0.2)            # reported shares are rounded and sum to 99.9
  expect_equal(sum(mix$share_used_in_module_pct), 100, tolerance = 0.02) # shares used in the module are rescaled to sum to 1
  expect_true(all(abs(mix$share_used_in_module_pct - mix$seer_share_pct) < 0.1))
  expect_equal(length(unique(mix$n_known_stage)), 1)
})

test_that("report inputs agree with the attrition table", {
  ri <- rd("results", "report_inputs.csv")
  v <- function(k) as.numeric(ri$value[ri$key == k])
  expect_equal(v("persons_in_cdm"), step(1))
  expect_equal(v("nsclc_persons"), step(4))
  expect_equal(v("true_small_cell_persons"), step(3))
})

test_that("Cox stage hazard ratios are ordered and each interval contains its estimate", {
  hr <- rd("results", "cox_os_hazard_ratios.csv")
  h <- hr[hr$model == "main", ]
  get <- function(t) h$hr[h$term == t]
  expect_true(get("stageII") > 1 && get("stageIII") > get("stageII") && get("stageIV") > get("stageIII"))
  expect_true(all(h$lcl <= h$hr & h$hr <= h$ucl))
})

test_that("README numbers match the results files", {
  expect_true(grepl(fmt(step(8)), readme, fixed = TRUE))                                   # main cohort size
  expect_true(grepl(fmt(step(6)), readme, fixed = TRUE))                                   # staged NSCLC
  expect_true(grepl(fmt(rd("seer", "nsclc_stage_mix_2010-2015.csv")$n_known_stage[1]), readme, fixed = TRUE))
  expect_true(grepl("Synthea", readme, fixed = TRUE) && grepl("not clinical evidence", readme, fixed = TRUE))
})

test_that("no environment, profile or credential files are tracked", {
  skip_if(system2("git", c("-C", shQuote(repo), "rev-parse", "--is-inside-work-tree"), stdout = FALSE, stderr = FALSE) != 0, "not a git checkout")
  files <- system2("git", c("-C", shQuote(repo), "ls-files"), stdout = TRUE)
  expect_false(any(basename(files) %in% c(".Renviron", "profiles.yml")))
})
