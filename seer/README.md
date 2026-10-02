# SEER benchmark inputs (aggregate only)

No SEER record-level data is stored in this repository, per the SEER Research Data Use Agreement. Only aggregate counts are committed; all cells are far above SEER's small-number limit.

**Source.** Surveillance, Epidemiology, and End Results (SEER) Program (www.seer.cancer.gov) SEER*Stat Database: Incidence - SEER Research Data, 17 Registries, Nov 2025 Sub (2000-2023) - Linked To County Attributes - Time Dependent (1990-2024) Income/Rurality, 1969-2024 Counties, National Cancer Institute, DCCPS, Surveillance Research Program, released April 2026, based on the November 2025 submission.

## Pull 1: NSCLC stage mix (`nsclc_stage_mix_2010-2015.csv`)
SEER*Stat, SEER Research Data, 17 Registries, Nov 2025 Sub. NSCLC, diagnosed 2010-2015, age 50+, **first primary only**, AJCC 7th edition derived stage group. n = 160,258 with known stage. Shares: I 20.0%, II 8.4%, III 19.8%, IV 51.7% (sum 99.9% from rounding; scaled proportionally to sum to 1 in the module). These drive the patched Synthea module (see top-level README), so the synthetic stage mix matches SEER by construction. Only shares and the total n are stored; per-stage counts were not provided with this pull.

Superseded: an earlier same-day pull used "first matching record per person" and gave n = 213,428 (I 22.8%, II 8.7%, III 19.4%, IV 49.0%). The first-primary-only definition replaces it because it counts each person once at their first primary cancer.

## Pull 2 (pending): survival by stage
Survival session for the same NSCLC definition, by stage group, age group and sex, for the benchmark against the synthetic cohort.
