# Creates CDM + native tables and loads Athena vocabularies via ETLSyntheaBuilder (slow, memory-hungry).
# Prefer etl/01b_load_vocab_copy.sh for the vocabulary load; this script is kept for table creation.
# Run from the repository root.
source("etl/00_connect.R")
library(ETLSyntheaBuilder)
CreateCDMTables(cd, cdm_schema, cdm_version)
CreateSyntheaTables(cd, synthea_schema, synthea_version)
if (identical(Sys.getenv("LOAD_VOCAB_IN_R"), "1")) LoadVocabFromCsv(cd, cdm_schema, Sys.getenv("VOCAB_DIR", "vocab"))
cat("TABLES CREATED\n")
