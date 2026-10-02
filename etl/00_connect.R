# Shared connection settings. Run scripts from the repository root.
# Credentials and local paths come from the gitignored .Renviron (see .Renviron.example).
if (!file.exists(".Renviron")) stop("Run from the repository root, with a .Renviron (see .Renviron.example).")
readRenviron(".Renviron")
library(DatabaseConnector)
jdbc_dir <- Sys.getenv("JDBC_DIR", "jdbc")
dir.create(jdbc_dir, showWarnings = FALSE, recursive = TRUE)
if (length(list.files(jdbc_dir, pattern = "postgresql")) == 0) downloadJdbcDrivers("postgresql", pathToDriver = jdbc_dir)
cd <- createConnectionDetails(
  dbms = "postgresql",
  server = paste0(Sys.getenv("PG_HOST"), "/", Sys.getenv("PG_DB")),
  port = as.integer(Sys.getenv("PG_PORT")),
  user = Sys.getenv("PG_USER"), password = Sys.getenv("PG_PASSWORD"),
  pathToDriver = jdbc_dir)
cdm_schema <- "cdm"; synthea_schema <- "native"
synthea_version <- "3.3.0"; cdm_version <- "5.4"
