# Note on cox_os_hazard_ratios.csv

The stage hazard ratios in this file are **scripted, not discovered**. Synthea assigns time of death from stage-specific windows, so survival times are nearly separated by stage and the estimates (about 22, 290 and 9,488 against stage I) are numerically extreme and unstable. They are not clinical effect sizes. See `docs/analysis_decisions.md`, section "Interpreting the Cox model".
