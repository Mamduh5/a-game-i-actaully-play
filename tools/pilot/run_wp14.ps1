param(
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Python,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [switch]$PauseForOtherRuntime
)
$ErrorActionPreference = 'Stop'
$Project = (Resolve-Path -LiteralPath $Project).Path
$Godot = (Resolve-Path -LiteralPath $Godot).Path
$Python = (Resolve-Path -LiteralPath $Python).Path
$assertionScript = Join-Path $PSScriptRoot 'verify_wp14.py'
$root = (New-Item -ItemType Directory -Path $EvidenceRoot).FullName
$env:GODOT_MCP_RUNTIME = 'off'

foreach ($name in 'alpha','beta','replay') {
    if ($PauseForOtherRuntime) {
        $existing = Get-CimInstance Win32_Process -Filter "name like 'Godot%' or name = 'qual.exe' or name like 'AGameIActuallyPlay%'" |
            Where-Object { $_.CommandLine -notmatch ' --editor ' }
        if ($existing) {
            Write-Output 'Another Godot runtime is active. Remaining cases were deferred.'
            exit 77
        }
    }
    $case = (New-Item -ItemType Directory -Path (Join-Path $root $name)).FullName
    $log = Join-Path $case 'run.log'
    $variant = if ($name -eq 'alpha') { 'alpha' } else { 'beta' }
    $args = @('--path', ('"' + $Project + '"'), '--log-file', ('"' + $log + '"'), '--max-fps', '60',
        'res://dev/fixtures/visible_pilot/pilot_fixture.tscn', '--', "--wp14-hidden=$variant",
        ('"--wp14-evidence=' + $case + '"'))
    if ($name -eq 'replay') {
        $args += @('--wp14-rebind', ('"--wp14-replay=' + (Join-Path $root 'alpha/evidence.jsonl') + '"'))
    } else {
        $args += ('"--wp14-policy=' + $Python + '"')
    }
    $task = Start-Process -FilePath $Godot -ArgumentList $args -PassThru -WindowStyle Hidden
    if (-not $task.WaitForExit(22000)) {
        Stop-Process -Id $task.Id
        throw "Fixture timed out in $name."
    }
    Get-Content -LiteralPath $log
    if ($task.ExitCode -ne 0) { exit $task.ExitCode }
    if (Select-String -LiteralPath $log -Pattern 'ERROR:' -Quiet) { exit 1 }
}

& $Python -B $assertionScript (Join-Path $root 'alpha') (Join-Path $root 'beta') (Join-Path $root 'replay') |
    Tee-Object -FilePath (Join-Path $root 'verify.json')
exit $LASTEXITCODE
