<#
.SYNOPSIS
    Extract CelToon changes from the private UE5.6 fork and stage them into ToonEngine
    for manual review before publishing as a new public release.

.DESCRIPTION
    Given a baseline tag in the UE5.6 fork, this script:
      1. For each target file in scripts/target-files.json, runs
             git diff <Baseline>..HEAD -- <file>
         in the UE5.6 fork.
      2. Saves the raw diff (for human review) to build/release-<Version>/per-file/*.diff.txt.
      3. Extracts ONLY the '+' lines (your original code, safe to publish) and writes
         them to build/release-<Version>/per-file/*.new-lines-only.txt. Context lines
         and '-' lines (Epic code) are discarded, preventing accidental republication
         of UE source under this public MIT-licensed repo.
      4. Generates CHANGELOG-proposed.md as a skeleton for the new version entry.
      5. Generates manual-action-required.txt listing what the human must decide.

    The script DOES NOT modify snippets/, integration_notes.md, or CHANGELOG.md;
    it does NOT commit anything in either repo. Review the staging output, then
    manually update ToonEngine.

.PARAMETER UE5Path
    Absolute path to your UE5.6 source fork (must be a git repo).
    Default: from scripts/target-files.json ue5_fork_default.

.PARAMETER Baseline
    Baseline tag in UE5.6 fork (e.g. celtoon-v0.1.0).
    Default: from scripts/target-files.json baseline_default.

.PARAMETER NewVersion
    Target ToonEngine version label, e.g. v0.2.0.
    This is used for the staging directory name and the CHANGELOG entry.

.PARAMETER ToonEnginePath
    Absolute path to the ToonEngine repo. Default: parent of this script's directory.

.PARAMETER ConfigPath
    Path to target-files.json. Default: adjacent to this script.

.EXAMPLE
    .\scripts\release-public.ps1 -NewVersion v0.2.0

.EXAMPLE
    .\scripts\release-public.ps1 -NewVersion v0.2.0 -Baseline celtoon-v0.1.0 -UE5Path E:\UECode\UnrealEngine-5.6

.NOTES
    Safe to run multiple times — overwrites the staging directory each time.
    Never writes outside of build/release-<Version>/.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+([.-].+)?$')]
    [string]$NewVersion,

    [string]$UE5Path = $null,
    [string]$Baseline = $null,
    [string]$ToonEnginePath = $null,
    [string]$ConfigPath = $null
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ---------- Force UTF-8 I/O ----------
# Windows PowerShell 5.1 decodes external command stdout (e.g. `git diff`) using
# [Console]::OutputEncoding, which defaults to the OEM code page (cp936 on
# Chinese Windows). This corrupts UTF-8 source files. Lock everything to UTF-8
# so our UE5.6 source diffs (which contain Chinese comments) round-trip cleanly.
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# ---------- Resolve paths ----------
if (-not $ToonEnginePath) { $ToonEnginePath = Split-Path -Parent $PSScriptRoot }
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'target-files.json' }

if (-not (Test-Path $ConfigPath)) { throw "Config file not found: $ConfigPath" }
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (-not $UE5Path) { $UE5Path = $config.ue5_fork_default }
if (-not $Baseline) { $Baseline = $config.baseline_default }

# ---------- Validate inputs ----------
if (-not (Test-Path $UE5Path)) { throw "UE5 fork path not found: $UE5Path" }
if (-not (Test-Path (Join-Path $UE5Path '.git'))) {
    throw "UE5 fork path is not a git repo (no .git dir): $UE5Path"
}
$tagCheck = git -C $UE5Path tag --list $Baseline
if (-not $tagCheck) {
    throw "Baseline tag '$Baseline' not found in $UE5Path. Create it with:`n    git -C `"$UE5Path`" tag -a $Baseline -m '...'"
}

# ---------- Header ----------
Write-Host ""
Write-Host "================================================================"
Write-Host "  ToonEngine release staging: $NewVersion"
Write-Host "================================================================"
Write-Host "  UE5 fork        : $UE5Path"
Write-Host "  Baseline tag    : $Baseline"
Write-Host "  ToonEngine path : $ToonEnginePath"
Write-Host "  Target files    : $($config.target_files.Count)"
Write-Host ""

# ---------- Prepare staging dir ----------
$stagingDir = Join-Path $ToonEnginePath "build/release-$NewVersion"
if (Test-Path $stagingDir) {
    Write-Host "[warn] Staging dir exists. Overwriting: $stagingDir" -ForegroundColor Yellow
    Remove-Item $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
$perFileDir = Join-Path $stagingDir 'per-file'
New-Item -ItemType Directory -Path $perFileDir -Force | Out-Null

# ---------- Iterate target files ----------
$refactorCandidates = New-Object System.Collections.ArrayList
$pureAdditions = New-Object System.Collections.ArrayList
$totalPlus = 0
$totalMinus = 0

foreach ($entry in $config.target_files) {
    $file = $entry.path
    $mappedSnippet = $entry.maps_to_snippet
    $section = $entry.integration_section

    # Normalise to forward slashes for git
    $gitFile = $file -replace '\\', '/'
    $rawDiff = git -C $UE5Path diff "$Baseline..HEAD" -- $gitFile

    if ([string]::IsNullOrWhiteSpace($rawDiff)) {
        continue
    }

    # File-name-safe key for output files
    $safeName = ($file -replace '[/\\]', '__')

    $diffPath = Join-Path $perFileDir "$safeName.diff.txt"
    $newLinesPath = Join-Path $perFileDir "$safeName.new-lines-only.txt"

    # Save raw diff for human review (WITH Epic context; never commit this)
    $rawDiff | Out-File -FilePath $diffPath -Encoding UTF8

    # Extract '+' lines only; skip '+++' header; count '-' lines for refactor detection
    $lines = $rawDiff -split "`n"
    $plusLines = New-Object System.Collections.ArrayList
    $minusCount = 0
    foreach ($l in $lines) {
        if ($l -match '^\+\+\+') { continue }
        if ($l -match '^---') { continue }
        if ($l -match '^\+') { [void]$plusLines.Add($l.Substring(1)) }
        elseif ($l -match '^-') { $minusCount++ }
    }
    $plusCount = $plusLines.Count
    $totalPlus += $plusCount
    $totalMinus += $minusCount

    # Write a header + your additions, stripped of all Epic material
    $header = @(
        '// ================================================================================',
        "// Staging extract — new / changed lines ONLY (Epic context stripped).",
        "//",
        "//   UE5 file          : $file",
        "//   Diff range        : $Baseline..HEAD",
        "//   Integration §     : $section",
        "//   Mapped snippet(s) : $(if ($mappedSnippet) { $mappedSnippet } else { '(none — list-extension only; update integration_notes.md)' })",
        "//   Insertions        : $plusCount",
        "//   Deletions         : $minusCount (NOT INCLUDED — Epic code, cannot be republished)",
        "//",
        "// This file contains ONLY lines you added to the UE5.6 source. It has been",
        "// stripped of all Epic context lines and deletion markers, so it is safe to",
        "// copy into the public ToonEngine repo. Review carefully and paste into the",
        "// appropriate Block of the mapped snippet file.",
        '// ================================================================================',
        ''
    )

    ($header + $plusLines.ToArray()) -join "`n" | Out-File -FilePath $newLinesPath -Encoding UTF8

    # Bucket the result
    $row = [PSCustomObject]@{
        File          = $file
        Plus          = $plusCount
        Minus         = $minusCount
        MappedSnippet = $mappedSnippet
        Section       = $section
    }
    if ($minusCount -gt 0) { [void]$refactorCandidates.Add($row) }
    else { [void]$pureAdditions.Add($row) }

    $tag = if ($minusCount -gt 0) { '[refactor]' } else { '[additive]' }
    Write-Host ("  {0,-10}  {1}  (+{2} / -{3})" -f $tag, $file, $plusCount, $minusCount) `
        -ForegroundColor $(if ($minusCount -gt 0) { 'Yellow' } else { 'Green' })
}

if (($refactorCandidates.Count + $pureAdditions.Count) -eq 0) {
    Write-Host ""
    Write-Host "No changes in any of the $($config.target_files.Count) target files between $Baseline and HEAD." -ForegroundColor Yellow
    Write-Host "Nothing to release."
    Remove-Item $stagingDir -Recurse -Force
    exit 0
}

Write-Host ""
Write-Host ("Total: {0} files changed, +{1} / -{2} lines" -f ($refactorCandidates.Count + $pureAdditions.Count), $totalPlus, $totalMinus)

# ---------- CHANGELOG-proposed.md ----------
$shortVer = $NewVersion.TrimStart('v')
$date = Get-Date -Format 'yyyy-MM-dd'
$cl = New-Object System.Collections.ArrayList
[void]$cl.Add("## [$shortVer] - $date")
[void]$cl.Add('')
[void]$cl.Add('### Changed')
[void]$cl.Add('')
foreach ($c in ($pureAdditions + $refactorCandidates)) {
    $line = "- ``$($c.File)``: +$($c.Plus)"
    if ($c.Minus -gt 0) { $line += " / -$($c.Minus)" }
    if ($c.MappedSnippet) {
        $line += "  _(affects `snippets/shaders/$($c.MappedSnippet)`)_"
    }
    elseif ($c.Section) {
        $line += "  _(integration_notes.md §$($c.Section))_"
    }
    [void]$cl.Add($line)
}
[void]$cl.Add('')
[void]$cl.Add("[$shortVer]: https://github.com/floridaman4080/ToonEngine/releases/tag/$NewVersion")
$cl -join "`n" | Out-File -FilePath (Join-Path $stagingDir 'CHANGELOG-proposed.md') -Encoding UTF8

# ---------- manual-action-required.txt ----------
$ma = New-Object System.Collections.ArrayList
[void]$ma.Add("MANUAL ACTION REQUIRED - ToonEngine $NewVersion")
[void]$ma.Add('=' * 60)
[void]$ma.Add('')
[void]$ma.Add('The script staged the diff for your review. It did NOT modify any file')
[void]$ma.Add('under snippets/ or integration_notes.md, and it did NOT commit anything.')
[void]$ma.Add('Everything below needs your decision.')
[void]$ma.Add('')

if ($refactorCandidates.Count -gt 0) {
    [void]$ma.Add('[!] REFACTOR CANDIDATES - these files have BOTH insertions and deletions.')
    [void]$ma.Add('    Please inspect per-file/*.diff.txt to decide whether this is a')
    [void]$ma.Add('    refactor that also requires REMOVING old content from the snippet,')
    [void]$ma.Add('    or just an in-place edit.')
    [void]$ma.Add('')
    foreach ($c in $refactorCandidates) {
        [void]$ma.Add(("    - {0}  (+{1} / -{2})" -f $c.File, $c.Plus, $c.Minus))
        if ($c.MappedSnippet) {
            [void]$ma.Add("        -> affects: snippets/shaders/$($c.MappedSnippet)")
        }
        else {
            [void]$ma.Add("        -> integration_notes.md section(s): $($c.Section)")
        }
    }
    [void]$ma.Add('')
}

if ($pureAdditions.Count -gt 0) {
    [void]$ma.Add('[i] PURE ADDITIONS - these files only have new lines. Typically a clean')
    [void]$ma.Add('    append/replace into the mapped snippet Block, or a brand-new section.')
    [void]$ma.Add('')
    foreach ($c in $pureAdditions) {
        [void]$ma.Add(("    - {0}  (+{1})" -f $c.File, $c.Plus))
        if ($c.MappedSnippet) {
            [void]$ma.Add("        -> target: snippets/shaders/$($c.MappedSnippet)")
        }
        else {
            [void]$ma.Add("        -> integration_notes.md only (section(s): $($c.Section))")
        }
    }
    [void]$ma.Add('')
}

[void]$ma.Add('STEPS TO COMPLETE THE RELEASE:')
[void]$ma.Add('  1. For each per-file/*.new-lines-only.txt, open the mapped snippet file')
[void]$ma.Add('     under snippets/shaders/ and replace / append the relevant Block.')
[void]$ma.Add('     If there is no mapped snippet, decide whether:')
[void]$ma.Add('       (a) pure list-extension -> update integration_notes.md only, OR')
[void]$ma.Add('       (b) new significant code -> create a new snippet file + new section.')
[void]$ma.Add('')
[void]$ma.Add('  2. Merge CHANGELOG-proposed.md into CHANGELOG.md as the new version entry.')
[void]$ma.Add('')
[void]$ma.Add('  3. Review your working tree in the ToonEngine repo:')
[void]$ma.Add('       git status')
[void]$ma.Add('       git diff')
[void]$ma.Add('')
[void]$ma.Add('  4. Commit and tag:')
[void]$ma.Add("       git add snippets/ integration_notes.md CHANGELOG.md")
[void]$ma.Add("       git commit -m 'Release $NewVersion'")
[void]$ma.Add("       git tag -a $NewVersion -m '$NewVersion release'")
[void]$ma.Add('')
[void]$ma.Add('  5. Push ToonEngine + tag the UE5 fork to mark the new baseline:')
[void]$ma.Add('       git push origin main')
[void]$ma.Add("       git push origin $NewVersion")
[void]$ma.Add("       git -C `"$UE5Path`" tag -a celtoon-$NewVersion -m 'UE5.6 state for ToonEngine $NewVersion'")
[void]$ma.Add("       git -C `"$UE5Path`" push origin celtoon-$NewVersion")
[void]$ma.Add('')
[void]$ma.Add('  6. Once everything is committed, you can delete this staging dir:')
[void]$ma.Add("       Remove-Item -Recurse -Force '$stagingDir'")
$ma -join "`n" | Out-File -FilePath (Join-Path $stagingDir 'manual-action-required.txt') -Encoding UTF8

# ---------- Done ----------
Write-Host ""
Write-Host "================================================================"
Write-Host "  STAGED to: $stagingDir"
Write-Host "================================================================"
Write-Host "  Next:  cat '$stagingDir\manual-action-required.txt'"
Write-Host ""
