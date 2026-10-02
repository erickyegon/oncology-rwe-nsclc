#!/bin/bash
# Loads Synthea CSVs into the `native` schema with psql \copy (replaces ETLSyntheaBuilder::LoadSyntheaTables,
# which mis-types ZIP codes as integers and is ~10x slower). Truncates native tables first.
# If a CSV has columns the ETL-Synthea native table lacks (current Synthea adds some, e.g. organizations.NPI),
# the file is loaded through a staging table and the extra columns are dropped.
# Usage: bash etl/02a_load_native_copy.sh <csv_dir>   (a path psql can read, e.g. a Windows-style path or a path relative to the repo root)
set -e
DIR=${1:?csv dir}
cd "$(dirname "$0")/.."
# load KEY=VALUE lines from .Renviron safely (values may contain spaces; do not `source` it)
while IFS='=' read -r k v; do [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && export "$k=$v"; done < <(grep -v '^[[:space:]]*#' .Renviron | tr -d '')
export PGPASSWORD=$PG_PASSWORD
PSQL_BIN=${PSQL_BIN:-$(command -v psql || echo "/c/Program Files/PostgreSQL/17/bin/psql.exe")}
PSQL=("$PSQL_BIN" -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1)
for f in "$DIR"/*.csv; do
  t=$(basename "$f" .csv)
  csvcols=$(head -1 "$f" | tr -d '\r"' | tr ',' '\n' | tr 'A-Z' 'a-z')
  tblcols=$("${PSQL[@]}" -tAc "select column_name from information_schema.columns where table_schema='native' and table_name='$t' order by ordinal_position" | tr -d '\r')
  if [ -z "$tblcols" ]; then echo "skip $t (no native table)"; continue; fi
  extra=$(comm -23 <(echo "$csvcols" | sort) <(echo "$tblcols" | sort) | paste -sd, -)
  common=$(echo "$csvcols" | grep -Fxf <(echo "$tblcols") | paste -sd, -)
  allcols=$(echo "$csvcols" | paste -sd, -)
  "${PSQL[@]}" -q -c "truncate native.$t"
  if [ -z "$extra" ]; then
    echo "loading native.$t"
    "${PSQL[@]}" -q -c "\copy native.$t ($allcols) FROM '$f' WITH (FORMAT csv, HEADER true)"
  else
    echo "loading native.$t via staging (dropping extra: $extra)"
    {
      echo "create temp table stg (like native.$t including defaults);"
      for c in ${extra//,/ }; do echo "alter table stg add column $c text;"; done
      echo "\copy stg ($allcols) FROM '$f' WITH (FORMAT csv, HEADER true)"
      echo "insert into native.$t ($common) select $common from stg;"
    } | "${PSQL[@]}" -q
  fi
done
echo NATIVE LOAD DONE
