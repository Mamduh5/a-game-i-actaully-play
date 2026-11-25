param(
    [Parameter(Mandatory)][string]$Aseprite,
    [string]$Ffmpeg = 'ffmpeg',
    [switch]$RegenerateMasters
)
$ErrorActionPreference = 'Stop'
$derived = Join-Path (Split-Path $PSScriptRoot) 'derived'
New-Item -ItemType Directory -Force $derived | Out-Null

function Invoke-Aseprite([string[]]$Arguments) {
    $quoted = $Arguments | ForEach-Object { '"' + $_ + '"' }
    $task = Start-Process -FilePath $Aseprite -ArgumentList $quoted -PassThru -WindowStyle Hidden
    if (-not $task.WaitForExit(30000)) {
        Stop-Process -Id $task.Id
        throw 'Aseprite timed out.'
    }
    if ($task.ExitCode -ne 0) { throw "Aseprite exit $($task.ExitCode)" }
}

if ($RegenerateMasters) {
    Invoke-Aseprite @('--batch', '--script-param', "output=$PSScriptRoot", '--script', (Join-Path $PSScriptRoot 'waystone.lua'))
}
foreach ($name in 'waystone', 'waystone_alternate') {
    Invoke-Aseprite @('--batch', (Join-Path $PSScriptRoot "$name.aseprite"), '--sheet-type', 'horizontal',
        '--list-tags', '--format', 'json-array', '--sheet', (Join-Path $derived "$name.png"),
        '--data', (Join-Path $derived "$name.json"))
}

$source = 'aevalsrc=0.19*(sin(2*PI*656*t)+0.33*sin(2*PI*984*t))*exp(-17*t)*(1-exp(-200*t)):s=48000:d=0.24'
& $Ffmpeg -hide_banner -loglevel error -y -f lavfi -i $source -af 'afade=t=out:st=0.18:d=0.06' -c:a libvorbis -q:a 5 -fflags +bitexact -flags:a +bitexact -map_metadata -1 (Join-Path $derived 'waystone_cue.ogg')
if ($LASTEXITCODE -ne 0) { throw "FFmpeg exit $LASTEXITCODE" }
