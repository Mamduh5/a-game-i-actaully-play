# Shared helpers for repository tooling. Dot-source from other scripts.
# The engine path comes from the AGIP_GODOT environment variable or a `godot`
# command on PATH, so no machine-specific path is stored in the repository.

$ErrorActionPreference = 'Stop'

function Get-AgipRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-AgipGodot {
    param([string]$Explicit = '')
    $candidate = $Explicit
    if (-not $candidate) { $candidate = $env:AGIP_GODOT }
    if (-not $candidate) {
        $cmd = Get-Command godot -ErrorAction SilentlyContinue
        if ($cmd) { $candidate = $cmd.Source }
    }
    if (-not $candidate -or -not (Test-Path $candidate)) {
        throw 'Godot 4.7-stable not found. Set AGIP_GODOT to the console editor executable (Godot_v4.7-stable_win64_console.exe).'
    }
    return (Resolve-Path $candidate).Path
}

function Assert-AgipEngineVersion {
    param([Parameter(Mandatory)][string]$Godot)
    $version = (& $Godot --version 2>$null | Select-Object -Last 1).Trim()
    if ($version -notlike '4.7.stable.*') {
        throw "Pinned engine is 4.7-stable; found '$version' at $Godot"
    }
    return $version
}

# Runs Godot with arguments, tees combined output to a log file and returns the exit code.
function Invoke-AgipGodot {
    param(
        [Parameter(Mandatory)][string]$Godot,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$LogPath = ''
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($LogPath) {
            $LogPath = [IO.Path]::GetFullPath($LogPath)
            New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
            & $Godot @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $LogPath | Out-Null
        } else {
            & $Godot @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}
