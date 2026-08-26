<#
.SYNOPSIS
    Packages src/ into a runnable dist/TD-Idle.love, and optionally an .exe.

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

    -Fuse concatenates love.exe with the .love to make a standalone
    dist/TD-Idle.exe, copies the runtime DLLs it needs alongside it, and (via
    a downloaded rcedit, see Get-RcEdit) sets the exe's own icon to
    src/assets/TD-Idle.ico -- fusing only appends bytes, so without this the
    exe keeps carrying love.exe's icon. None of this is protection against
    modification — a fused exe is a zip with an exe stub glued on the front,
    and 7-Zip opens it exactly like it would a .love. It exists purely so
    players don't need LÖVE installed separately.

    -Bytecode replaces every .lua file's source with LuaJIT bytecode before
    packaging (whichever of .love/.exe you asked for). Raises the bar past
    "open it in a text editor," not real protection either. Compiled through
    this LÖVE install's own runtime rather than a standalone luajit.exe —
    see tools/bytecode/main.lua for why that distinction matters, and why
    the source gets copied into a game/ subfolder of a throwaway project
    rather than mounted from src/ directly.

.EXAMPLE
    pwsh tools/build.ps1
    pwsh tools/build.ps1 -Verify
    pwsh tools/build.ps1 -Fuse -Verify
    pwsh tools/build.ps1 -Fuse -Bytecode -Verify
#>
[CmdletBinding()]
param(
    # Launch the built artifact (.love, or the .exe with -Fuse) from an empty
    # directory and fail on a Lua error.
    [switch]$Verify,
    # Seconds to let the game run during -Verify before considering it healthy.
    [int]$VerifySeconds = 12,
    # Also produce dist/TD-Idle.exe (love.exe + the .love, concatenated) plus
    # the DLLs it needs alongside it. Distribution convenience only — see
    # the .DESCRIPTION above.
    [switch]$Fuse,
    # Compile every .lua file to LuaJIT bytecode before packaging.
    [switch]$Bytecode,
    # Seconds to let the bytecode compile step run before treating it as hung.
    [int]$CompileSeconds = 30,
    # Strip debug info (line numbers, local names) from the bytecode. Smaller,
    # but pcall/traceback messages lose their file:line — off by default so
    # a bug report is still debuggable.
    [switch]$StripDebug
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$love = Join-Path $dist 'Starsown.love'
$exe  = Join-Path $dist 'Starsown.exe'

if (-not (Test-Path (Join-Path $src 'main.lua'))) {
    throw "No main.lua in $src - is this the right repo?"
}

# The LÖVE install directory: PATH first, then the usual Windows install
# location. Shared by -Bytecode (needs a runtime to compile through), -Fuse
# (needs love.exe and its DLLs), and -Verify (needs something to launch).
function Find-LoveHome {
    $cmd = Get-Command love -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path -Parent $cmd.Source }
    foreach ($candidate in @("$env:ProgramFiles\LOVE", "${env:ProgramFiles(x86)}\LOVE")) {
        if (Test-Path (Join-Path $candidate 'love.exe')) { return $candidate }
    }
    return $null
}

# rcedit sets a compiled exe's PE icon resource -- LÖVE has no built-in way
# to do this itself, since love.exe's own icon is baked in at LÖVE's own
# build time, long before it's fused with this game. Downloaded once into a
# gitignored cache (pinned to a release, not "latest", so this behaves the
# same next year as it does today) rather than vendored into the repo.
$RCEDIT_VERSION = 'v2.0.0'
function Get-RcEdit {
    $cacheDir = Join-Path $root '.tools'
    $rcedit = Join-Path $cacheDir 'rcedit.exe'
    if (Test-Path $rcedit) { return $rcedit }

    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $url = "https://github.com/electron/rcedit/releases/download/$RCEDIT_VERSION/rcedit-x64.exe"
    Write-Host "Downloading rcedit..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $url -OutFile $rcedit
    return $rcedit
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $love) { Remove-Item $love -Force }
if (Test-Path $exe) { Remove-Item $exe -Force }

# What actually gets zipped: src/ itself, or a bytecode-compiled mirror of it.
$packageSrc = $src

if ($Bytecode) {
    $loveHome = Find-LoveHome
    if (-not $loveHome) { throw 'Could not find a LÖVE install (needed to compile bytecode through its own runtime).' }

    $staging = Join-Path $dist '.bytecode-staging'
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null

    # io.open (in tools/bytecode/main.lua) won't create directories, so every
    # subdirectory src/ has needs to exist before that script runs.
    Get-ChildItem -Path $src -Recurse -Directory | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length + 1)
        New-Item -ItemType Directory -Force -Path (Join-Path $staging $rel) | Out-Null
    }

    # A throwaway LÖVE project: the compiler harness at its root, and a copy
    # of every .lua file under game/ for it to read through a plain relative
    # path. Not mounted from src/ directly — love.filesystem.mount() returned
    # false for every absolute path tried while building this (even "." and
    # the harness's own directory), so the source is copied in as a
    # subdirectory instead, which sidesteps whatever that was entirely.
    $work = Join-Path $dist '.bytecode-work'
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'bytecode\*') $work -Recurse -Force

    $gameDir = Join-Path $work 'game'
    Get-ChildItem -Path $src -Recurse -Filter *.lua | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length + 1)
        $dest = Join-Path $gameDir $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item $_.FullName $dest -Force
    }

    $env:TDIDLE_COMPILE_OUT = $staging
    $env:TDIDLE_COMPILE_STRIP = if ($StripDebug) { '1' } else { '0' }

    $compileOut = Join-Path ([System.IO.Path]::GetTempPath()) 'tdidle-compile-out.txt'
    $compileErr = Join-Path ([System.IO.Path]::GetTempPath()) 'tdidle-compile-err.txt'
    # -PassThru + a bounded WaitForExit, NOT Start-Process -Wait: -Wait waits
    # on the whole Job Object the process launched into, not just the exe
    # itself, and lovec.exe (a console-subsystem binary) leaves a conhost.exe
    # helper that can outlive it -- -Wait then hangs forever even though
    # lovec.exe has already exited. This is the same reason -Verify below
    # already uses WaitForExit(ms) instead of -Wait.
    # $work quoted explicitly: -ArgumentList with an unquoted path containing
    # spaces gets split into separate argv tokens, and lovec.exe silently
    # finds no game at the truncated path instead of erroring.
    $proc = Start-Process -FilePath (Join-Path $loveHome 'lovec.exe') `
        -ArgumentList "`"$work`"" `
        -PassThru -NoNewWindow `
        -RedirectStandardOutput $compileOut -RedirectStandardError $compileErr
    $finished = $proc.WaitForExit($CompileSeconds * 1000)
    if (-not $finished) { $proc.Kill() }
    $compileLog = (Get-Content $compileOut, $compileErr -Raw -ErrorAction SilentlyContinue) -join "`n"
    Write-Host $compileLog

    Remove-Item Env:\TDIDLE_COMPILE_OUT, Env:\TDIDLE_COMPILE_STRIP -ErrorAction SilentlyContinue
    Remove-Item $work -Recurse -Force

    if (-not $finished) {
        throw "Bytecode compilation did not finish within $CompileSeconds s:`n$compileLog"
    }
    if ($proc.ExitCode -ne 0) {
        throw "Bytecode compilation failed (exit $($proc.ExitCode)):`n$compileLog"
    }

    # Everything that isn't .lua ships unchanged — fonts, audio, json, icons.
    Get-ChildItem -Path $src -Recurse -File | Where-Object { $_.Extension -ne '.lua' } | ForEach-Object {
        $rel = $_.FullName.Substring($src.Length + 1)
        $dest = Join-Path $staging $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item $_.FullName $dest -Force
    }

    $packageSrc = $staging
}

# Compress the CONTENTS of packageSrc, so main.lua lands at the archive root.
$zip = Join-Path $dist 'TD-Idle.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $packageSrc '*') -DestinationPath $zip -CompressionLevel Optimal
Move-Item $zip $love

if ($Bytecode) { Remove-Item (Join-Path $dist '.bytecode-staging') -Recurse -Force }

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
# instead of at "why does my released game not start". Always scanned from
# the real source, not the (possibly bytecode) package — the module graph is
# identical either way, and bytecode isn't text a regex can read.
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
$bytecodeNote = if ($Bytecode) { ', bytecode' } else { '' }
Write-Host "Built $love  ($kb KB, $($names.Count) entries$bytecodeNote)" -ForegroundColor Green

if ($Fuse) {
    $loveHome = Find-LoveHome
    if (-not $loveHome) { throw 'Could not find a LÖVE install to fuse against.' }

    # The icon has to be set on a plain copy of love.exe BEFORE the .love
    # bytes are appended, never after: rcedit rewrites the PE file it's
    # given, and running it on the already-fused exe silently discards
    # everything appended past the recognized PE structure -- i.e. the
    # entire game. (Found by actually checking the output size: a "fused"
    # exe rcedit had touched came back at 436 KB, not the ~21 MB it should
    # have been.) Worked on a copy, not loveHome's own love.exe, so a build
    # never mutates the shared LÖVE install.
    $loveExeStaged = Join-Path $dist 'love-staged.exe'
    Copy-Item (Join-Path $loveHome 'love.exe') $loveExeStaged -Force

    $icon = Join-Path $src 'assets\TD-Idle.ico'
    if (Test-Path $icon) {
        $rcedit = Get-RcEdit
        & $rcedit $loveExeStaged --set-icon $icon
        if ($LASTEXITCODE -ne 0) { throw "rcedit failed to set the icon (exit $LASTEXITCODE)." }
    } else {
        Write-Host "No icon at $icon -- exe keeps LÖVE's default icon." -ForegroundColor Yellow
    }

    # A fused exe is love.exe (icon already set above) with the .love's bytes
    # appended — zip readers find archives by scanning backward from EOF for
    # the central directory record, so this is NOT protection, just a single
    # file to hand out instead of "install LÖVE, then double-click this .love".
    $loveExeBytes = [System.IO.File]::ReadAllBytes($loveExeStaged)
    $loveDataBytes = [System.IO.File]::ReadAllBytes($love)
    $combined = New-Object byte[] ($loveExeBytes.Length + $loveDataBytes.Length)
    [System.Array]::Copy($loveExeBytes, 0, $combined, 0, $loveExeBytes.Length)
    [System.Array]::Copy($loveDataBytes, 0, $combined, $loveExeBytes.Length, $loveDataBytes.Length)
    [System.IO.File]::WriteAllBytes($exe, $combined)
    Remove-Item $loveExeStaged -Force

    # The exe still dynamically loads these at runtime — it has to ship
    # alongside them, in the same folder, same as a normal LÖVE install.
    Get-ChildItem -Path $loveHome -Filter *.dll | Copy-Item -Destination $dist -Force
    $license = Join-Path $loveHome 'license.txt'
    if (Test-Path $license) { Copy-Item $license (Join-Path $dist 'love-license.txt') -Force }

    $exeKb = [math]::Round((Get-Item $exe).Length / 1KB)
    Write-Host "Built $exe  ($exeKb KB) + DLLs in $dist" -ForegroundColor Green
}

if (-not $Verify) { return }

$loveHome = Find-LoveHome
if (-not $loveHome) { throw 'Could not find a LÖVE install to verify against.' }

# Run it from a scratch directory containing nothing but the built artifact
# (and its DLLs, for -Fuse), so a module that only resolves via the repo's
# working directory cannot sneak in.
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("tdidle-verify-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
try {
    if ($Fuse) {
        Copy-Item $exe $sandbox
        Get-ChildItem -Path $dist -Filter *.dll | Copy-Item -Destination $sandbox
        $target = Join-Path $sandbox 'TD-Idle.exe'
        $launchArgs = @()
    } else {
        Copy-Item $love $sandbox
        $target = Join-Path $loveHome 'lovec.exe'
        $launchArgs = @('TD-Idle.love')
    }

    $out = Join-Path $sandbox 'stdout.txt'
    $proc = Start-Process -FilePath $target -ArgumentList $launchArgs `
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
