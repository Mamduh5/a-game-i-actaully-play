<#
.SYNOPSIS
  Lists the files inside a Godot 4.x .pck and checks a release boundary.

.DESCRIPTION
  Parses the PCK directory (format v2/v3/v4) and writes a sorted manifest. Fails
  (exit 1) if any path matches a -Forbid pattern or any -Require pattern is
  unmatched. With -ForbidInProjectBinary, also fails if those strings appear in
  the exported project settings (catches a leaked autoload registration).
  Comma-separated lists are accepted in each array parameter so both interactive
  PowerShell calls and `powershell -File` invocations work identically.

.EXAMPLE
  powershell -File tools/inspect_pack.ps1 -Pack build/windows-player/AGameIActuallyPlay.pck `
    -Forbid 'addons/gut/*,addons/godot_mcp_toolkit/*,tests/*,dev/*,.gutconfig.json' `
    -Require 'src/app/main.tscn*' -ForbidInProjectBinary 'MCPRuntimeServer'
#>
param(
    [Parameter(Mandatory)][string]$Pack,
    [string[]]$Forbid = @(),
    [string[]]$Require = @(),
    [string[]]$ForbidInProjectBinary = @(),
    [string]$Manifest = ''
)
$ErrorActionPreference = 'Stop'

function Expand-PatternList([string[]]$Items) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Items) {
        foreach ($part in ($item -split ',')) {
            $trimmed = $part.Trim()
            if ($trimmed) { $out.Add($trimmed) }
        }
    }
    return $out.ToArray()
}

$Forbid = Expand-PatternList $Forbid
$Require = Expand-PatternList $Require
$ForbidInProjectBinary = Expand-PatternList $ForbidInProjectBinary

function Read-PckDirectory([string]$path) {
    $stream = [IO.File]::OpenRead((Resolve-Path $path).Path)
    try {
        $r = New-Object IO.BinaryReader($stream)
        $magic = $r.ReadUInt32()
        if ($magic -ne 0x43504447) { throw "Not a standalone PCK (magic 0x{0:X8})" -f $magic }
        $format = $r.ReadUInt32()
        $major = $r.ReadUInt32(); $minor = $r.ReadUInt32(); $patch = $r.ReadUInt32()
        $flags = $r.ReadUInt32()
        $fileBase = $r.ReadUInt64()
        if ($format -ge 3) {
            $dirOffset = $r.ReadUInt64()
            $stream.Position = [int64]$dirOffset
        } elseif ($format -eq 2) {
            $null = $r.ReadBytes(16 * 4)
        } else { throw "Unsupported PCK format $format" }
        if ($flags -band 1) { throw 'PCK directory is encrypted; cannot inspect.' }
        $count = $r.ReadUInt32()
        if ($count -gt 1000000) { throw "Implausible file count $count" }
        $entries = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $count; $i++) {
            $len = $r.ReadUInt32()
            if ($len -gt 4096) { throw "Implausible path length $len at entry $i" }
            $name = [Text.Encoding]::UTF8.GetString($r.ReadBytes($len)).TrimEnd([char]0)
            $offset = $r.ReadUInt64(); $size = $r.ReadUInt64()
            $null = $r.ReadBytes(16); $entryFlags = $r.ReadUInt32()
            $relative = $name -replace '^res://', ''
            $entries.Add([pscustomobject]@{ Path = $relative; Offset = $offset; Size = $size; Flags = $entryFlags })
        }
        $relBase = ($flags -band 2) -ne 0
        return [pscustomobject]@{ Format = $format; Engine = "$major.$minor.$patch"; Flags = $flags; FileBase = $fileBase; RelativeBase = $relBase; Entries = $entries }
    } finally { $stream.Dispose() }
}

function Read-PckFile($pck, [string]$path, $entry) {
    $stream = [IO.File]::OpenRead((Resolve-Path $path).Path)
    try {
        $start = [int64]$entry.Offset
        if ($pck.RelativeBase) { $start += [int64]$pck.FileBase }
        $stream.Position = $start
        $buffer = New-Object byte[] ([int]$entry.Size)
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -ne $buffer.Length) { throw "Short read for $($entry.Path)" }
        return $buffer
    } finally { $stream.Dispose() }
}

$pck = Read-PckDirectory $Pack
$paths = $pck.Entries | ForEach-Object Path | Sort-Object
$violations = @()
foreach ($pattern in $Forbid) {
    foreach ($p in $paths) { if ($p -like $pattern) { $violations += "forbidden '$pattern': $p" } }
}
foreach ($pattern in $Require) {
    if (-not ($paths | Where-Object { $_ -like $pattern })) { $violations += "required '$pattern' missing" }
}
if ($ForbidInProjectBinary.Count -gt 0) {
    $projectEntry = $pck.Entries | Where-Object { $_.Path -eq 'project.binary' } | Select-Object -First 1
    if (-not $projectEntry) { $violations += 'project.binary missing from pack' }
    else {
        $text = [Text.Encoding]::UTF8.GetString((Read-PckFile $pck $Pack $projectEntry))
        foreach ($needle in $ForbidInProjectBinary) {
            if ($text.Contains($needle)) { $violations += "project.binary contains '$needle'" }
        }
    }
}

$header = "pck=$((Resolve-Path $Pack).Path | Split-Path -Leaf) format=$($pck.Format) engine=$($pck.Engine) files=$($paths.Count)"
if ($Manifest) {
    New-Item -ItemType Directory -Force -Path (Split-Path ([IO.Path]::GetFullPath($Manifest))) | Out-Null
    @($header) + $paths | Set-Content -Path $Manifest -Encoding utf8
}
Write-Host $header
if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Host "VIOLATION $_" }
    exit 1
}
Write-Host "PACK PASS: $($Forbid.Count) forbidden pattern(s) absent, $($Require.Count) required pattern(s) present."
exit 0
