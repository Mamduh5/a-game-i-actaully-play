<#
.SYNOPSIS
  Imports the project with the WP05 cold bootstrap when SQLite is present.
#>
param(
    [string]$Project = '',
    [string]$Godot = '',
    [string]$LogDirectory = ''
)
. (Join-Path $PSScriptRoot 'agip_common.ps1')

if (-not $Project) { $Project = Get-AgipRoot }
$Project = (Resolve-Path -LiteralPath $Project).Path
if (-not (Test-Path -LiteralPath (Join-Path $Project 'project.godot') -PathType Leaf)) {
    throw "No project.godot in '$Project'."
}
$engine = Get-AgipGodot $Godot
Assert-AgipEngineVersion $engine | Out-Null

if (-not $LogDirectory) {
    $LogDirectory = Join-Path ([IO.Path]::GetTempPath()) ("agip-import-" + [guid]::NewGuid().ToString('N'))
}
$LogDirectory = [IO.Path]::GetFullPath($LogDirectory)
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

$descriptor = 'addons/godot-sqlite/gdsqlite.gdextension'
$registry = Join-Path $Project '.godot/extension_list.cfg'
$hasSqlite = Test-Path -LiteralPath (Join-Path $Project $descriptor) -PathType Leaf
$registered = (Test-Path -LiteralPath $registry -PathType Leaf) -and
    ((Get-Content -LiteralPath $registry) -contains "res://$descriptor")
if ($hasSqlite -and -not $registered) {
    $editor = $engine -replace '_console\.exe$', '.exe'
    if ($editor -eq $engine -or -not (Test-Path -LiteralPath $editor -PathType Leaf)) {
        throw 'Select the pinned Windows console executable and its adjacent GUI editor for the SQLite bootstrap.'
    }
    $bootstrapLog = Join-Path $LogDirectory 'bootstrap.log'
    $bootstrapArgs = @('--headless', '--path', ('"' + $Project + '"'), '--editor', '--quit-after', '180',
        '--log-file', ('"' + $bootstrapLog + '"'))
    $process = Start-Process -FilePath $editor -ArgumentList $bootstrapArgs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $bootstrapLog) -or
            (Select-String -LiteralPath $bootstrapLog -Pattern 'ERROR:' -Quiet)) {
        throw "SQLite bootstrap failed. See '$bootstrapLog'."
    }
}

$importLog = Join-Path $LogDirectory 'import.log'
$code = Invoke-AgipGodot -Godot $engine -Arguments @('--headless', '--path', $Project, '--import') -LogPath $importLog
if ($code -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'ERROR:' -Quiet)) {
    throw "Godot import failed. See '$importLog'."
}
if ($hasSqlite -and (-not (Test-Path -LiteralPath $registry) -or
        (Get-Content -LiteralPath $registry) -notcontains "res://$descriptor")) {
    throw "Godot did not register the SQLite extension. See '$importLog'."
}
Write-Host "Imported '$Project'. Logs are in '$LogDirectory'."
