#!/bin/bash
# Fast vocabulary load with psql \copy (streams files; R-based loader is too memory-hungry).
# Usage (any directory): bash etl/01b_load_vocab_copy.sh [vocab_dir]   (default: $VOCAB_DIR from .Renviron, else ./vocab)
set -e
cd "$(dirname "$0")/.."
# load KEY=VALUE lines from .Renviron safely (values may contain spaces; do not `source` it)
while IFS='=' read -r k v; do [[ $k =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && export "$k=$v"; done < <(grep -v '^[[:space:]]*#' .Renviron | tr -d '')
export PGPASSWORD=$PG_PASSWORD
VOC=${1:-${VOCAB_DIR:-vocab}}
PSQL_BIN=${PSQL_BIN:-$(command -v psql || echo "/c/Program Files/PostgreSQL/17/bin/psql.exe")}
PSQL=("$PSQL_BIN" -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -v ON_ERROR_STOP=1)
for t in vocabulary domain concept_class relationship concept concept_relationship concept_synonym concept_ancestor drug_strength; do
  f="$VOC/$(echo $t | tr a-z A-Z).csv"
  echo "loading $t"
  "${PSQL[@]}" -c "\copy cdm.$t FROM '$f' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, QUOTE E'\b')"
done
echo VOCAB COPY DONE
