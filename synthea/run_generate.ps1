# Reproducible Synthea generation with the patched lung cancer modules (lung_cancer.json, veteran_lung_cancer.json).
# Claims and imaging files are excluded: ~25 GB and ~2.5 GB per 20k patients, unused by this project.
# Paths: SYNTHEA_JAR (default synthea/synthea-with-dependencies.jar), SYNTHEA_OUT (default synthea/output),
# Java 17+ from SYNTHEA_JAVA, else JAVA_HOME, else `java` on PATH.
# Usage: .\synthea\run_generate.ps1 [-Population 60000] [-Seed 2026]
param([int]$Population = 60000, [int]$Seed = 2026,
      [string]$ReferenceDate = '20261001', [int]$ClinicianSeed = 2026,   # pinned for reproducibility (clear with '' and 0 to use the clock)
      [string]$Jar = '', [string]$Out = '', [string]$Java = '')
if (-not $Jar)  { $Jar  = if ($env:SYNTHEA_JAR) { $env:SYNTHEA_JAR } else { Join-Path $PSScriptRoot 'synthea-with-dependencies.jar' } }
if (-not $Out)  { $Out  = if ($env:SYNTHEA_OUT) { $env:SYNTHEA_OUT } else { Join-Path $PSScriptRoot 'output' } }
if (-not $Java) { $Java = if ($env:SYNTHEA_JAVA) { $env:SYNTHEA_JAVA } elseif ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { 'java' } }
$Out = $Out.Replace('\', '/').TrimEnd('/')
$props = Join-Path $env:TEMP 'synthea_run.properties'
@"
exporter.csv.export = true
exporter.fhir.export = false
exporter.csv.excluded_files = claims.csv,claims_transactions.csv,imaging_studies.csv
exporter.baseDirectory = $Out/
"@ | Set-Content $props -Encoding ascii
$extra = @()
if ($ReferenceDate) { $extra += @("-r", $ReferenceDate) }
if ($ClinicianSeed) { $extra += @("-cs", $ClinicianSeed) }
& $Java -Xmx6g -jar $Jar -c $props -d "$PSScriptRoot\modules" -s $Seed -p $Population -a 50-90 @extra
