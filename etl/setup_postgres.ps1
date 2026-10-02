# One-time local setup: creates the `omop` database and a limited `omop_user` role.
# Prompts for the postgres superuser password (never stored). Writes the new role's
# generated password to the gitignored .Renviron at the repo root (other lines in it are preserved).
$ErrorActionPreference = 'Stop'
$psql = if ($env:PSQL_BIN) { $env:PSQL_BIN } elseif (Get-Command psql -ErrorAction SilentlyContinue) { (Get-Command psql).Source } else { 'C:\Program Files\PostgreSQLin\psql.exe' }
$root = Split-Path $PSScriptRoot -Parent

$sec = Read-Host 'postgres superuser password' -AsSecureString
$env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))

$pw = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })

& $psql -h localhost -U postgres -v ON_ERROR_STOP=1 -c "DO `$`$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='omop_user') THEN CREATE ROLE omop_user LOGIN PASSWORD '$pw'; ELSE ALTER ROLE omop_user PASSWORD '$pw'; END IF; END `$`$;"
$exists = & $psql -h localhost -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='omop'"
if (-not $exists) { & $psql -h localhost -U postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE omop OWNER omop_user" }
foreach ($s in 'native', 'cdm', 'results', 'dbt') {
    & $psql -h localhost -U postgres -d omop -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS $s AUTHORIZATION omop_user"
}

$envFile = Join-Path $root '.Renviron'
$keep = if (Test-Path $envFile) { Get-Content $envFile | Where-Object { $_ -notmatch '^PG_' } } else { @() }
$keep + @('PG_HOST=localhost', 'PG_PORT=5432', 'PG_DB=omop', 'PG_USER=omop_user', "PG_PASSWORD=$pw") | Set-Content $envFile -Encoding ascii

Remove-Item Env:PGPASSWORD
Write-Host "Done. Database 'omop' with schemas native, cdm, results, dbt; credentials saved to $root\.Renviron"
