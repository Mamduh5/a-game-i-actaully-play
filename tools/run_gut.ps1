<#
.SYNOPSIS
  Runs the GUT suite headlessly and propagates the result as the process exit code.

.DESCRIPTION
  Default: runs .gutconfig.json (tests/unit). Exit 0 only when every test passes
  and at least one test executed; an empty discovery exits 3 (QAS §2).
  -Probe: runs only tests/probes (an intentional failure). Exit 0 only when GUT
  reports the failure with a nonzero exit, proving failure propagation.

.EXAMPLE
  powershell -File tools/run_gut.ps1 -JUnit .qa-evidence/WP01/gut-unit.xml
#>
param(
    [string]$Project = '',
    [string]$JUnit = '',
    [string]$Log = '',
    [switch]$Probe,
    [string]$Godot = ''
)
. (Join-Path $PSScriptRoot 'agip_common.ps1')

if (-not $Project) { $Project = Get-AgipRoot }
$Project = (Resolve-Path $Project).Path
$engine = Get-AgipGodot $Godot
Assert-AgipEngineVersion $engine | Out-Null

if (-not $JUnit) { $JUnit = Join-Path ([IO.Path]::GetTempPath()) ("agip-gut-{0}.xml" -f [guid]::NewGuid()) }
$JUnit = [IO.Path]::GetFullPath($JUnit)
New-Item -ItemType Directory -Force -Path (Split-Path $JUnit) | Out-Null
if (Test-Path $JUnit) { Remove-Item $JUnit }

$arguments = @('--headless', '--path', $Project, '-s', 'res://addons/gut/gut_cmdln.gd', '-gexit', "-gjunit_xml_file=$JUnit")
if ($Probe) {
    $arguments += @('-gconfig=', '-gdir=res://tests/probes', '-ginclude_subdirs', '-gprefix=test_')
}

$code = Invoke-AgipGodot -Godot $engine -Arguments $arguments -LogPath $Log

$tests = 0; $failures = 0
if (Test-Path $JUnit) {
    [xml]$report = Get-Content $JUnit -Raw
    foreach ($suite in $report.testsuites) {
        $tests += [int]$suite.tests
        $failures += [int]$suite.failures
    }
}
Write-Host ("GUT exit={0} tests={1} failures={2} junit={3}" -f $code, $tests, $failures, $JUnit)

if ($Probe) {
    if ($code -ne 0 -and $failures -ge 1) { Write-Host 'PROBE PASS: failing test propagated to a nonzero exit.'; exit 0 }
    Write-Host 'PROBE FAIL: an intentionally failing test did not produce a failing exit.'; exit 4
}
if ($code -ne 0) { exit $code }
if ($tests -lt 1) { Write-Host 'FAIL: zero tests discovered.'; exit 3 }
exit 0
