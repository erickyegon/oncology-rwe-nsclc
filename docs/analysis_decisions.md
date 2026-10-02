# Analysis decisions

[Back to README](../README.md)

Decisions taken before the survival models were run, and the evidence behind them. Numbers are from the analysis run (`-s 2026 -cs 2026 -r 20261001`, 60,000 alive patients, 1,886 with a lung cancer diagnosis).

## Cohorts and endpoints
- **Main cohort:** staged NSCLC, age 50 or older at diagnosis, all diagnosis years, follow-up censored at 120 months (n = 1,347). **Sensitivity cohort:** the same, diagnosed 2010 to 2015 (n = 305). Details in [data notes](data-notes.md).
- **Overall survival:** from the index date (first recorded lung cancer diagnosis) to death; survivors are censored at the end of their observation period.
- **Histology and stage** come from SNOMED source codes, never from standard concepts, because of the stage III small-cell mapping problem ([provenance](provenance.md)).

## Lines of therapy (rules approved 2026-10-02)
Built in dbt as `int_lines_of_therapy` from `drug_exposure`. Rules:
1. **Scope:** only NSCLC-directed systemic drugs (a whitelist, here cisplatin and paclitaxel), and only administrations on or after the NSCLC index date. Other cancers' regimens (for example docetaxel with leuprolide, oxaliplatin) and hormone preparations are excluded.
2. **Line 1** starts at the first whitelisted administration; its regimen is the set of drugs started within 28 days of the line start.
3. **A gap of more than 90 days** between consecutive administrations starts the next line (a restart after the gap is the next line).
4. **A new drug alone does not start a line.**

The gap (default 90) and the window (default 28) are dbt variables (`line_gap_days`, `line_window_days`), so sensitivity runs need no code change (`dbt run --vars '{line_gap_days: 60}'`).

Why these thresholds, from the data: consecutive administrations are 1 day apart in 76,008 of about 99,000 gaps, and cycles are separated by 29 to 60 days (99th percentile 46 days). A 28-day gap would therefore start a new line in 99.6% of patients; a 90-day gap isolates 47 of 1,346 treated patients (3.5%). The 28-day line-1 window changes nothing here, because cisplatin and paclitaxel are always started together; it is kept for generality.

| Gap | Patients with a line 2 | With 3 or more lines | Total lines |
|---|---:|---:|---:|
| 60 days | 168 | 32 | 1,559 |
| **90 days (default)** | **47** | **1** | **1,394** |
| 120 days | 20 | 0 | 1,366 |

Every line 1 and every line 2 regimen is cisplatin + paclitaxel.

**Time to next treatment** (`ttnt_months`, `ttnt_event` in `mart_nsclc_cohort`): from the start of line 1 to the start of line 2 or death, whichever is first, censored at the end of observation. It is null for the one patient with no recorded treatment. Because line 2 occurs in only 3.5% of patients, of the 1,293 events only 47 are line 2 starts and the rest are deaths without a line 2, so time to next treatment is essentially time to death (median 9.4 months).

## Prior other cancer
`prior_other_cancer` is a flag, not an exclusion. It is true if, before the NSCLC index date, the person had an anticancer drug (ATC L01 or L02, excluding contraceptives and hormone preparations and one mis-coded ingredient), a chemotherapy or radiation procedure, or a non-lung malignancy diagnosis. 241 of 1,347 patients (17.9%) are flagged: 199 by a drug, 30 by a procedure and 73 by a diagnosis (these overlap). The Cox model is re-fitted without them as a sensitivity analysis.

## Cox proportional hazards model
`coxph(Surv(followup_months, event) ~ stage + age_at_dx + sex)` on the main cohort (`analysis/cox_os.R`), with proportional hazards tested by `cox.zph` and the Schoenfeld residuals plotted (`figures/cox_schoenfeld_residuals*.png`). Hazard ratios with 95% CIs are in `results/cox_os_hazard_ratios.csv`.

Caution on reading it: in the Synthea lung cancer module the time of death is scripted by stage, so the survival times of the stages barely overlap. That makes the stage hazard ratios numerically extreme and unstable, and the proportional-hazards assumption does not hold for stage (global test p < 2e-16; by coefficient, stage II p = 0.0025 and stage III p = 9.2e-5; age and sex are consistent with proportional hazards). The model demonstrates the pipeline; its estimates are not clinical evidence.

## Interpreting the Cox model
- **The stage hazard ratios (22 for stage II, 290 for III and 9,488 for IV, against stage I) reflect near-complete separation of survival times by stage, not clinical effect sizes.** Synthea assigns each stage's death inside a scripted window after diagnosis (stage I 2 to 6 years, II 16 to 28 months, III 9 to 18 months, IV 6 to 10 months), and neighbouring windows overlap only at their edges: 12% of stage III deaths fall at or before the last stage IV death, 22% of stage II deaths at or before the last stage III death, and 15% of stage I deaths at or before the last stage II death. The partial likelihood is therefore close to separation, which makes the estimates and their confidence intervals numerically extreme.
- **The proportional-hazards failure for stage confirms the Kaplan-Meier finding** (global test p < 2e-16; stage II p = 0.0025, stage III p = 9.2e-5): survival falls within a stage-specific time window instead of declining gradually, so the relative hazard between stages changes sharply over time.
- **Age (HR 1.05 per 10 years, 95% CI 0.98 to 1.12) and sex (HR 1.01, 0.89 to 1.16) have essentially no effect in Synthea.** Mean time to death is also the same in women and men within every stage. In real NSCLC, observed survival worsens with age and is generally lower in men. The simulator does not reproduce this because, after diagnosis, its survival depends on stage alone (apart from a few early deaths from other causes).

## Restricted mean survival time
RMST to 60 months by stage (`analysis/rmst.R`, `results/rmst_synthea_vs_seer.csv`) summarises each survival curve as one number, the area under it, which does not need proportional hazards. Synthea: from the Kaplan-Meier fit (`summary(survfit, rmean = 60)`), with a normal 95% CI. SEER: the area under the monthly observed-survival curve from the SEER*Stat life-table export, by the trapezoid rule over the 60 monthly intervals (survival is 100% at diagnosis). The monthly export is not in the repository; only the four resulting values are.

## IPTW is not identifiable in this data
The planned inverse probability of treatment weighting needs variation in first-line treatment. There is none. Among the 1,347 main-cohort patients, 1,346 received the same first line: cisplatin and paclitaxel together with the combined chemotherapy and radiation procedure, started a median 2 days (IQR 2 to 3) after diagnosis. First-line type is defined as chemoradiation if the combined procedure falls within 28 days of the first systemic dose, else chemotherapy alone, else none.

| Stage | Chemotherapy + radiation | Chemotherapy alone | None recorded | Total |
|---|---:|---:|---:|---:|
| I | 292 | 0 | 0 | 292 |
| II | 109 | 0 | 0 | 109 |
| III | 261 | 0 | 0 | 261 |
| IV | 684 | 0 | 1 | 685 |

First-line type is not even associated with stage (Cramér's V 0.027, chi-square p = 0.81); it is simply constant. Positivity requires every treatment level to be possible within each covariate stratum. Here the probability of chemoradiation is about 1 in every stratum, there is no chemotherapy-alone or untreated comparison group (one untreated patient in all), propensity scores would be degenerate, and any weights would be undefined or dominated by that single patient. A treatment comparison (the original research question) therefore **cannot be identified in this data**. It would need a source with real treatment variation, which is the point of benchmarking a synthetic cohort before using real EHR data.

For the same reason no dose-response or treatment-duration analysis is attempted: the number of administrations rises with survival (median 181, 94, 56 and 32 administration dates in stages I to IV), because treatment simply continues until death, which would be immortal-time bias if used as an exposure.
