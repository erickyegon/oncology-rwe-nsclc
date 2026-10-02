# Maps the `native` Synthea tables to OMOP CDM 5.4 in `cdm`. Run etl/02a_load_native_copy.sh first.
# Usage (from the repository root): Rscript etl/02_etl_synthea.R
source("etl/00_connect.R")
library(ETLSyntheaBuilder)
CreateMapAndRollupTables(cd, cdm_schema, synthea_schema, cdm_version, synthea_version)
CreateExtraIndices(cd, synthea_schema, cdm_schema, synthea_version)
LoadEventTables(cd, cdm_schema, synthea_schema, cdm_version, synthea_version)
cat("ETL DONE\n")
