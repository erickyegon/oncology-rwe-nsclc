# Maps the `native` Synthea tables to OMOP CDM 5.4 in `cdm` (ETL-Synthea SQL, run in stages).
# Run etl/02a_load_native_copy.sh first. Usage (from the repository root): Rscript etl/02_etl_synthea.R
#
# Why not LoadEventTables(): it runs ~20 INSERT...SELECT steps back to back. The helper tables it joins
# (final_visit_ids, person, provider) are created seconds earlier with no statistics and no index on
# final_visit_ids.encounter_id, and one run spent 6 hours in insert_observation. Here the same
# ETL-Synthea SQL is rendered with sqlOnly = TRUE and executed with an index and ANALYZE between steps.
source("etl/00_connect.R")
library(ETLSyntheaBuilder)
cdm <- cdm_schema; nat <- synthea_schema
con <- connect(cd); on.exit(disconnect(con), add = TRUE)
run <- function(sql) executeSql(con, sql, progressBar = FALSE, reportOverallTime = FALSE)
q <- function(sql) querySql(con, sql)
stamp <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n")

render_steps <- function(fun, ..., order = NULL) {   # render ETL-Synthea steps to SQL files, return them in execution order
  tmp <- tempfile("etlsql"); dir.create(tmp); owd <- setwd(tmp); on.exit(setwd(owd))
  out <- capture.output(fun(..., sqlOnly = TRUE))
  files <- list.files(file.path(tmp, "output"), pattern = "[.]sql$")
  if (is.null(order)) {   # CreateMapAndRollupTables prints "Saving to output/<file>" in execution order
    files <- sub("^Saving to output/", "", grep("^Saving to output/.*[.]sql$", out, value = TRUE))
  } else {                # LoadEventTables prints the SQL text instead of the name, so use the known step order
    files <- c(intersect(order, files), setdiff(files, order))
  }
  stopifnot(length(files) > 0)
  setNames(file.path(tmp, "output", files), files)
}
event_order <- c("insert_location.sql", "insert_care_site.sql", "insert_person.sql", "insert_observation_period.sql",
                 "insert_provider.sql", "insert_visit_occurrence.sql", "insert_visit_detail.sql", "insert_condition_occurrence.sql",
                 "insert_observation.sql", "insert_measurement.sql", "insert_procedure_occurrence.sql", "insert_drug_exposure.sql",
                 "insert_condition_era.sql", "insert_drug_era.sql", "insert_cdm_source.sql", "insert_device_exposure.sql",
                 "insert_death.sql", "insert_payer_plan_period.sql", "insert_cost_v270.sql", "insert_cost_v300.sql")
exists_tbl <- function(schema, tbl) nrow(q(sprintf("select 1 from information_schema.tables where table_schema='%s' and table_name='%s'", schema, tbl))) > 0

# 0. fresh load: empty the clinical CDM tables (vocabulary tables are untouched)
clinical <- c("person", "observation_period", "visit_occurrence", "visit_detail", "condition_occurrence", "drug_exposure",
              "procedure_occurrence", "device_exposure", "measurement", "observation", "death", "note", "note_nlp", "specimen",
              "fact_relationship", "location", "care_site", "provider", "payer_plan_period", "cost", "drug_era", "dose_era",
              "condition_era", "episode", "episode_event", "metadata", "cdm_source")
for (t in clinical) if (exists_tbl(cdm, t)) run(sprintf("truncate table %s.%s", cdm, t))
stamp("clinical CDM tables emptied")

# 1. source-to-standard maps and visit roll-ups (the two vocabulary maps depend only on the vocabulary: build once)
vocab_maps <- c("create_source_to_standard_vocab_map.sql", "create_source_to_source_vocab_map.sql")
have_maps <- exists_tbl(cdm, "source_to_standard_vocab_map") && exists_tbl(cdm, "source_to_source_vocab_map") &&
  isTRUE(as.numeric(q(sprintf("select count(*) from %s.source_to_source_vocab_map", cdm))[[1]]) > 0)
steps <- render_steps(CreateMapAndRollupTables, cd, cdm, nat, cdm_version, synthea_version)
for (f in names(steps)) {
  if (have_maps && f %in% vocab_maps) { stamp("skip (already built)", f); next }
  stamp("running", f); run(SqlRender::readSql(steps[[f]]))
}
CreateExtraIndices(cd, cdm, nat, synthea_version)   # signature: (connectionDetails, cdmSchema, syntheaSchema, ...)
run(sprintf("create index if not exists idx_fvi_encounter on %s.final_visit_ids (encounter_id)", cdm))
for (t in q(sprintf("select table_name from information_schema.tables where table_schema='%s'", nat))[[1]]) run(sprintf("analyze %s.%s", nat, t))
for (t in c("final_visit_ids", "all_visits", "assign_all_visit_ids", "source_to_standard_vocab_map", "source_to_source_vocab_map")) run(sprintf("analyze %s.%s", cdm, t))
stamp("maps, indexes and statistics ready")

# 2. event tables, one step at a time, with ANALYZE after each target table
steps <- render_steps(LoadEventTables, cd, cdm, nat, cdm_version, synthea_version, order = event_order)
for (f in names(steps)) {
  stamp("running", f); run(SqlRender::readSql(steps[[f]]))
  tbl <- sub("^insert_", "", sub("[.]sql$", "", f))
  if (exists_tbl(cdm, tbl)) run(sprintf("analyze %s.%s", cdm, tbl))
}
stamp("event tables loaded")
cnt <- q(sprintf("select relname, n_live_tup from pg_stat_user_tables where schemaname='%s' and n_live_tup>0 and relname in ('%s') order by 1", cdm, paste(clinical, collapse = "','")))
print(cnt)
cat("ETL DONE\n")
