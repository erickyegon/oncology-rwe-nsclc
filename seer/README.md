# SEER benchmark inputs (aggregate only)

No SEER record-level data is stored in this repository, per the SEER Research Data Use Agreement. Only aggregate counts are committed; all cells are far above SEER's small-number limit.

**Source.** Surveillance, Epidemiology, and End Results (SEER) Program (www.seer.cancer.gov) SEER*Stat Database: Incidence - SEER Research Data, 17 Registries, Nov 2025 Sub (2000-2023) - Linked To County Attributes - Time Dependent (1990-2024) Income/Rurality, 1969-2024 Counties, National Cancer Institute, DCCPS, Surveillance Research Program, released April 2026, based on the November 2025 submission.

## Pull 1: NSCLC stage mix (`nsclc_stage_mix_2010-2015.csv`)
SEER*Stat, SEER Research Data, 17 Registries, Nov 2025 Sub. NSCLC, diagnosed 2010-2015, age 50+, **first primary only**, AJCC 7th edition derived stage group. n = 160,258 with known stage. Shares: I 20.0%, II 8.4%, III 19.8%, IV 51.7% (sum 99.9% from rounding; scaled proportionally to sum to 1 in the module). These drive the patched Synthea module (see top-level README), so the synthetic stage mix matches SEER by construction. Only shares and the total n are stored; per-stage counts were not provided with this pull.

Superseded: an earlier same-day pull used "first matching record per person" and gave n = 213,428 (I 22.8%, II 8.7%, III 19.4%, IV 49.0%). The first-primary-only definition replaces it because it counts each person once at their first primary cancer.

## Pull 2: observed survival by stage (`nsclc_survival_by_stage_summary.csv`)
SEER*Stat survival session `nsclc_survival_by_stage_2010-2015` (Kaplan-Meier observed survival, 1-month intervals, 120 months, study cutoff 12/2023) for the same NSCLC definition: diagnosed 2010-2015, derived AJCC 7th edition stage group. N at diagnosis: Stage I 32,093; II 13,477; III 31,785; IV 82,903; unknown stage 12,324 (172,582 in all; 160,258 with known stage I-IV).

**What is committed:** only `nsclc_survival_by_stage_summary.csv`: stage (I-IV), months (0, 12, 24, ... 120), observed survival (%), standard error (%), number still at risk, SEER's exported 95% log(-log) confidence limits (`ci_lower_pct`, `ci_upper_pct`) and SEER's exact median observed survival in months (`median_observed_survival_months`, one value per stage, repeated on each row). SEER*Stat exports confidence limits only for the five summary points (12, 24, 36, 48 and 60 months), so the two CI columns are blank at month 0 and at months 72-120. The CI columns are percentages and the median is a duration in months; the only count column is `n_at_risk`. Month 0 is 100% with the full cohort at risk; at month m the survival and SE are the cumulative values at the end of interval m, and the number at risk is the number alive and under follow-up at month m. **Every count in the file is at least 16** (the smallest is 753).

**What is not committed:** the full SEER*Stat export (`nsclc_survival_by_stage_2010-2015.csv`, `.dic`) and the session and matrix files. The export has monthly died and lost-to-follow-up counts, some of them under 16, which the SEER Research Data Use Agreement does not allow to be published. Those files stay on the local machine and are gitignored.
