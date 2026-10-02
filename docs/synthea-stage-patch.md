# Synthea stage assignment: finding and patch

[Back to README](../README.md)

**Finding.** In an unmodified Synthea run (`master-branch-latest`, jar built 2026-08-18, seed 2026, ages 50-90, 20,000 patients) every lung cancer case was **stage 1**: 535 NSCLC and 98 small cell, none at stages 2-4. A stage comparison and a stage-level SEER benchmark are impossible on that output.

**Why.** In `lung_cancer.json`, the state `Schedule Follow Up III` assigns stage from the attribute `lung_cancer_nondiagnosis_counter` (Stage I if <= 36, II if <= 72, III if <= 108, otherwise IV). The counter increments once per loop in `Undiagnosed_Lung_Cancer`, where a patient has a 20% chance of seeking care each pass. The chance of exceeding 36 passes is about 0.8^36, roughly 0.03%, so nearly everyone is stage I. Separately, survival is scripted by stage in the module (stage I death 2-6 years after diagnosis, stage IV 6-10 months), so survival differences by stage are built in, not discovered.

**What changed.** Only that one state, in the local override [`synthea/modules/lung_cancer.json`](../synthea/modules/lung_cancer.json), loaded with `-d synthea/modules` (`lung_cancer.json` and `veteran_lung_cancer.json`). The `conditional_transition` on the counter was replaced by an explicit `distributed_transition` using SEER-derived shares:

| Stage | SEER share (reported) | Share used in module |
|---|---|---|
| I | 20.0% | 20.02% |
| II | 8.4% | 8.41% |
| III | 19.8% | 19.82% |
| IV | 51.7% | 51.75% |

The reported shares sum to 99.9% because of rounding, so they are scaled proportionally to sum to 1 (Synthea requires it).

**Source of the shares.** SEER Research Data, 17 Registries, Nov 2025 Sub (SEER*Stat; National Cancer Institute, DCCPS, Surveillance Research Program): NSCLC diagnosed 2010-2015, age 50+, first primary only, AJCC 7th edition derived stage group; n = 160,258 with known stage. Unknown stage is excluded from the mix. Full citation and notes are in [`seer/`](../seer/). The same shares apply to the small cell branch because the state is shared; small cell is excluded from the cohort. Nothing else in the module (treatment, death timing) was altered. The same edit is applied to `veteran_lung_cancer.json` (see below). (Earlier iterations used a 20/5/25/50 placeholder and then an interim SEER pull; both are superseded.)

**Consequences to keep in mind.** Because the stage mix is set from SEER, agreement with SEER on stage mix is by construction; the benchmark is informative about survival by stage, not stage distribution. SEER's 9.5% unknown stage is not reproduced in the synthetic data (every synthetic patient has a stage), so missing-stage sensitivity analyses will use simulated missingness. Synthea uses TNM stage 1-4 and SEER derived AJCC 7th stage groups collapse to the same four labels, so no summary-stage (Localized/Regional/Distant) mapping is needed for this benchmark.

**Second stage path: the veteran module (found after the first 60k run).** Patching `lung_cancer.json` alone was not enough. Synthea also runs `veteran_lung_cancer.json` for patients with the `veteran` attribute, and that module carries its own copy of the original counter rule (all stage I). The first 60k run (both modules at the time: patched `lung_cancer.json`, unpatched veteran module) therefore missed the SEER input:

| First run, veteran module unpatched (n = 1,584 staged NSCLC) | I | II | III | IV |
|---|---|---|---|---|
| Observed | **51.5%** | 5.8% | 11.6% | **31.1%** |
| SEER input | 20.0% | 8.4% | 19.8% | 51.7% |

The skew tracked the veteran path: men born 1930-1949 were 68% stage I; men born 1970 or later (mostly non-veterans) were 22 / 11 / 17 / 50%, close to the input. Stage I patients were about 13 years older than the others (median 67 vs 54), and the stage I share depended on diagnosis era (49% in the 2000s, 65% in the 2010s). Applying the same `distributed_transition` to the veteran module in a validation run (8,000 alive patients, 200 staged NSCLC) gave I 19.0% / II 13.5% / III 15.5% / IV 52.0%, close to the input. A full 60,000-patient run was then regenerated with both modules patched (`synthea/modules/lung_cancer.json` and `synthea/modules/veteran_lung_cancer.json`) and pinned `-r 20261001 -cs 2026`; its results are below.

**Analysis run, both modules patched** (86,734 records: 60,000 alive, 26,734 dead; 1,886 with a lung cancer diagnosis: 1,622 NSCLC, 264 small cell only; 1,621 NSCLC staged). Stage mix against the SEER input:

| | n | I | II | III | IV |
|---|---|---|---|---|---|
| SEER input (reported) | | 20.0% | 8.4% | 19.8% | 51.7% |
| All staged NSCLC | 1,621 | 21.8% | 7.4% | 19.2% | 51.5% |
| Age >= 50 at diagnosis (SEER cohort definition) | 1,347 | 21.7% | 8.1% | 19.4% | 50.9% |
| Diagnosed 2010-2015 | 339 | 22.1% | 8.3% | 17.7% | 51.9% |

Chi-square against the input: p = 0.18 (all), 0.50 (age >= 50), 0.68 (2010-2015). Stage II is consistent with the 8.4% input in every slice (7.4%, 95% CI 6.2-8.8 overall; 8.1%, CI 6.8-9.7 for age >= 50), so the 13.5% seen in the 200-patient validation run was sampling noise. The stage mix no longer varies by sex (F 21/8/19/51, M 22/7/19/52) or materially by era. Full output: [`synthea/evidence/run2_summary.txt`](../synthea/evidence/run2_summary.txt). 274 staged NSCLC patients (17%) were diagnosed under age 50, because Synthea's 50-90 range applies to age at the reference date, not at diagnosis.

**Evidence retained.** The first run's lung-cancer-filtered export is kept locally (not committed; 1.2 GB) as `evidence_run1_lc_unpatched_veteran`, and its full summary table is committed at [`synthea/evidence/run1_summary.txt`](../synthea/evidence/run1_summary.txt) (stage mix, 95% CIs, chi-square vs input, diagnosis-year distribution, sex and age by stage). That run is **not used for analysis**.


Generation is reproducible with `synthea/run_generate.ps1` (population 60,000, seed 2026).
