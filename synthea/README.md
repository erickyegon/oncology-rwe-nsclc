# Synthea generation settings

- `run_generate.ps1`: reproducible run (seed 2026, clinician seed 2026, reference date 20261001, ages 50-90, CSV only; claims and imaging excluded).
- `modules/lung_cancer.json`, `modules/veteran_lung_cancer.json`: local overrides loaded with `-d`. Only the stage-assignment state (`Schedule Follow Up III`) differs from upstream; see the top-level README for the finding, the SEER stage mix and why both modules are patched.
- `synthea.properties`: base exporter settings.
- `evidence/`: summary tables of the first (superseded, veteran module unpatched) run and the analysis run.
