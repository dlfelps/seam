# Drive one condition of the Seam benchmark end-to-end. Resumable on rate-limit.
#
# Usage:
#   ./harness/run.ps1 baseline
#   ./harness/run.ps1 seam
#
# Run from any directory; the script resolves benchmarks/ relative to its own location.
# Assumes the `claude` CLI is on PATH and authenticated, and `pytest` is installed in the
# active environment.
#
# State lives in benchmarks/.cache/ (gitignored). Layout:
#   .cache/base/<mode>.tar.gz                     base src/ for this mode (built once)
#   .cache/base/<mode>.json                       raw Claude output for the base build
#   .cache/base/<mode>.status                     pass | fail (base test result)
#   .cache/<mode>/<NN>-<perm>/<NN>-<feature>/
#       claude.json    raw Claude output for this step
#       tests.log      pytest output
#       status         pass | fail
#       src.tar.gz     snapshot of workdir/src AFTER this step
#
# Resume semantics: any step whose directory contains a `status` file is treated as
# complete and is skipped. To force a step to re-run, delete its directory. To force
# the base to rebuild, delete .cache/base/<mode>.tar.gz.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

if ($Mode -notin @('baseline', 'seam')) {
    Write-Error "usage: $($MyInvocation.MyCommand.Name) baseline|seam"
    exit 2
}

$BenchDir     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Cache        = Join-Path $BenchDir '.cache'
$WorkDir      = Join-Path $BenchDir 'workdir'
$BaseArchive  = Join-Path $Cache "base/$Mode.tar.gz"
$BaseJson     = Join-Path $Cache "base/$Mode.json"
$BaseStatus   = Join-Path $Cache "base/$Mode.status"

New-Item -ItemType Directory -Force -Path (Join-Path $Cache 'base') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Cache $Mode)  | Out-Null

# ---------- helpers ----------

# Invoke Claude Code in $WorkDir with a prompt; wrap in /seam-gen in seam mode.
function Invoke-Claude {
    param(
        [string]$Prompt,
        [string]$Out
    )
    Push-Location $WorkDir
    try {
        if ($Mode -eq 'seam') {
            claude -p "/seam-gen $Prompt" --permission-mode acceptEdits --output-format json | Set-Content -Path $Out -Encoding utf8
        } else {
            claude -p $Prompt --permission-mode acceptEdits --output-format json | Set-Content -Path $Out -Encoding utf8
        }
        if ($LASTEXITCODE -ne 0) {
            throw "claude exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

# Run cumulative pytest for [base] + [given features]; write pass/fail to $StatusOut.
# Test log goes to $StatusOut.log.
function Invoke-Tests {
    param(
        [string[]]$Features,
        [string]$StatusOut
    )
    $testArgs = @((Join-Path $BenchDir 'tests/test_base.py'))
    foreach ($f in $Features) {
        $testArgs += (Join-Path $BenchDir "tests/test_$f.py")
    }
    Push-Location $WorkDir
    try {
        & python -m pytest -q @testArgs *> "$StatusOut.log"
        if ($LASTEXITCODE -eq 0) {
            'pass' | Set-Content -Path $StatusOut
        } else {
            'fail' | Set-Content -Path $StatusOut
        }
    } finally {
        Pop-Location
    }
}

# Restore a tarball into $WorkDir/src, replacing whatever is there.
function Restore-Archive {
    param([string]$Archive)
    $srcPath = Join-Path $WorkDir 'src'
    if (Test-Path $srcPath) {
        Remove-Item -Recurse -Force $srcPath
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    & tar -xzf $Archive -C $WorkDir
    if ($LASTEXITCODE -ne 0) {
        throw "tar extract failed for $Archive"
    }
}

# Snapshot $WorkDir/src into $Archive.
function Save-Archive {
    param([string]$Archive)
    $srcPath = Join-Path $WorkDir 'src'
    if (-not (Test-Path $srcPath)) {
        throw @"
expected '$srcPath' to exist, but it does not. Claude did not produce a ./src/ tree.
Common causes:
  - 'claude -p' ran without permission to write files. Try adding
    '--permission-mode acceptEdits' (or '--dangerously-skip-permissions') to the
    claude invocations in Invoke-Claude.
  - The model produced a textual response instead of using its editing tools.
    Inspect the JSON output for this run to see what happened.
"@
    }
    & tar -czf $Archive -C $WorkDir src
    if ($LASTEXITCODE -ne 0) {
        throw "tar create failed for $Archive"
    }
}

# ---------- step 0: build (or reuse) the base ----------

if (Test-Path $BaseArchive) {
    Write-Host "==> base build ($Mode) - cached: $BaseArchive"
} else {
    Write-Host "==> base build ($Mode) - building"
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse -Force $WorkDir
    }
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    $specText = Get-Content -Raw -Path (Join-Path $BenchDir 'spec.md')
    Invoke-Claude -Prompt $specText -Out $BaseJson
    Invoke-Tests -Features @() -StatusOut $BaseStatus
    Write-Host "    base tests: $((Get-Content -Raw $BaseStatus).Trim())"
    Save-Archive -Archive $BaseArchive
}

# ---------- ordering loop ----------

$OrderingsFile = Join-Path $Cache "$Mode/orderings.txt"
& python (Join-Path $BenchDir 'harness/permute.py') | Set-Content -Path $OrderingsFile -Encoding utf8
if ($LASTEXITCODE -ne 0) {
    throw "permute.py failed"
}

$Orderings = Get-Content -Path $OrderingsFile
$Total = $Orderings.Count
$Idx = 0

foreach ($line in $Orderings) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $Idx++
    $features = $line.Split(',')
    $permTag = $features -join '_'
    $ordDir = Join-Path $Cache ("$Mode/{0:D2}-{1}" -f $Idx, $permTag)
    New-Item -ItemType Directory -Force -Path $ordDir | Out-Null
    Write-Host "==> [$Idx/$Total] $permTag"

    $prevArchive = $BaseArchive
    $stepIdx = 0
    $added = @()

    foreach ($f in $features) {
        $stepIdx++
        $added += $f
        $stepDir = Join-Path $ordDir ("{0:D2}-{1}" -f $stepIdx, $f)
        $stepStatus  = Join-Path $stepDir 'status'
        $stepArchive = Join-Path $stepDir 'src.tar.gz'

        if ((Test-Path $stepStatus) -and (Test-Path $stepArchive)) {
            Write-Host "    [$stepIdx] $f - cached ($((Get-Content -Raw $stepStatus).Trim()))"
            $prevArchive = $stepArchive
            continue
        }

        # Incomplete cache from a prior aborted run - clear it.
        if (Test-Path $stepDir) {
            Remove-Item -Recurse -Force $stepDir
        }
        New-Item -ItemType Directory -Force -Path $stepDir | Out-Null

        Write-Host "    [$stepIdx] $f - running"
        Restore-Archive -Archive $prevArchive
        $featureText = Get-Content -Raw -Path (Join-Path $BenchDir "features/$f.md")
        Invoke-Claude -Prompt $featureText -Out (Join-Path $stepDir 'claude.json')
        Invoke-Tests -Features $added -StatusOut $stepStatus
        Save-Archive -Archive $stepArchive
        Write-Host "      tests: $((Get-Content -Raw $stepStatus).Trim())"
        $prevArchive = $stepArchive
    }
}

Write-Host "done - see $Cache/$Mode"
