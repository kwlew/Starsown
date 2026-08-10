<#
.SYNOPSIS
    Packages src/ into a runnable dist/TD-Idle.love.

.DESCRIPTION
    A .love file is just a zip whose ROOT contains main.lua — not a zip of the
    folder that contains main.lua. That distinction is the whole reason this
    script exists: zipping the src folder itself produces an archive LOVE will
    refuse, and it is an easy mistake to make by hand.

    It also guards a bug that was invisible for a long time. Everything the game
    requires has to live under src/, because src/ is what gets archived and
    love.filesystem's root is the archive. Code kept outside it (there used to
    be a lib/ beside src/) works in development purely because plain Lua's
    package.path resolves against the working directory — and then vanishes the
    moment the game is packaged. -Verify catches exactly that by launching the
    built archive from a directory that has nothing else in it.

.EXAMPLE
    pwsh tools/build.ps1
    pwsh tools/build.ps1 -Verify
#>
[CmdletBinding()]
param(
    # Launch the built archive from an empty directory and fail on a Lua error.
    [switch]$Verify,
    # Seconds to let the game run during -Verify before considering it healthy.
    [int]$VerifySeconds = 12
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$love = Join-Path $dist 'TD-Idle.love'

if (-not (Test-Path (Join-Path $src 'main.lua'))) {
    throw "No main.lua in $src - is this the right repo?"
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $love) { Remove-Item $love -Force }

# Compress the CONTENTS of src, so main.lua lands at the archive root.
$zip = Join-Path $dist 'TD-Idle.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zip -CompressionLevel Optimal
Move-Item $zip $love

# The archive must be able to stand alone: main.lua and conf.lua at the root,
# and every module the entry point pulls in present somewhere inside.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($love)
try {
    $names = $archive.Entries.FullName
} finally {
    $archive.Dispose()
}

foreach ($required in @('main.lua', 'conf.lua')) {
    if ($names -notcontains $required) {
        throw "$required is not at the root of the archive - LOVE will not run it."
    }
}

# Every `require "a.b"` in the tree must correspond to a file in the archive.
# This is the check that would have caught the old lib/ layout at build time
# instead of at "why does my released game not start".
$builtin = @('https', 'ffi', 'bit', 'socket', 'love')
$missing = @()
Get-ChildItem -Path $src -Recurse -Filter *.lua | ForEach-Object {
    foreach ($m in [regex]::Matches((Get-Content $_.FullName -Raw), 'require\s*\(?\s*"([^"]+)"')) {
        $mod = $m.Groups[1].Value
        if ($builtin -contains $mod) { continue }
        $path = ($mod -replace '\.', '/') + '.lua'
        $init = ($mod -replace '\.', '/') + '/init.lua'
        if (($names -notcontains $path) -and ($names -notcontains $init)) {
            $missing += "$mod  (required by $($_.Name))"
        }
    }
}
if ($missing.Count -gt 0) {
    throw ("These modules are required but are not in the archive:`n  " +
           (($missing | Sort-Object -Unique) -join "`n  "))
}

$kb = [math]::Round((Get-Item $love).Length / 1KB)
Write-Host "Built $love  ($kb KB, $($names.Count) entries)" -ForegroundColor Green

if (-not $Verify) { return }

$loveExe = (Get-Command love -ErrorAction SilentlyContinue)?.Source
if (-not $loveExe) {
    foreach ($candidate in @("$env:ProgramFiles\LOVE\lovec.exe", "$env:ProgramFiles\LOVE\love.exe")) {
        if (Test-Path $candidate) { $loveExe = $candidate; break }
    }
}
if (-not $loveExe) { throw 'Could not find love/lovec on PATH or in Program Files.' }

# Run it from a scratch directory containing nothing but the archive, so a
# module that only resolves via the repo's working directory cannot sneak in.
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("tdidle-verify-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
try {
    Copy-Item $love $sandbox
    $out = Join-Path $sandbox 'stdout.txt'
    $proc = Start-Process -FilePath $loveExe -ArgumentList 'TD-Idle.love' `
        -WorkingDirectory $sandbox -PassThru -NoNewWindow `
        -RedirectStandardOutput $out -RedirectStandardError (Join-Path $sandbox 'stderr.txt')

    if ($proc.WaitForExit($VerifySeconds * 1000)) {
        # Exiting on its own within the window means it crashed.
        $log = (Get-Content $out, (Join-Path $sandbox 'stderr.txt') -Raw -EA SilentlyContinue) -join "`n"
        throw "The packaged game exited after $($proc.ExitTime - $proc.StartTime):`n$log"
    }

    $proc.Kill()
    $log = (Get-Content $out, (Join-Path $sandbox 'stderr.txt') -Raw -EA SilentlyContinue) -join "`n"
    if ($log -match 'Error:|stack traceback') {
        throw "The packaged game reported an error:`n$log"
    }
    Write-Host "Verified: ran $VerifySeconds s from a clean directory with no errors." -ForegroundColor Green
} finally {
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
