# MyMiniFactory - Step 6: Move downloads to the models folder
# Moves each downloaded file to  <MODELS_PATH>\model_<id>\<filename>
# (flat, no subfolders), which is the layout the checker script expects.
#
# The model ID is taken from, in order:
#   1. "archive_id=<number>" anywhere in the path, looked up in the JSON metadata
#   2. a folder in the path named "<id>" or "<id>_something"
# Files are moved one at a time, so moving between drives (e.g. C: to a network drive) works.
# Top-level folders whose names start with "moved" are left alone.
#
# Run 5_mmf_correct_filenames.ps1 first, and run with $DRY_RUN = $true first to check.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Folders. Leave empty for the defaults, or put a full path here, e.g. 'D:\MyMiniFactory\models'.
# Where your browser's download manager saves MyMiniFactory files
# (empty = Downloads\www.myminifactory.com\download in your user folder).
$DOWN_PATH = ''
# model_<id> folders (empty = the "models" folder next to this script).
$MODELS_PATH = ''
# JSON metadata from step 2 (empty = the "downloads" folder next to this script).
$JSON_PATH = ''

# $true  = only show what would be moved, change nothing
# $false = actually move files and remove emptied folders
$DRY_RUN = $true
# ============================================================================

if (-not $DOWN_PATH)   { $DOWN_PATH   = Join-Path $HOME 'Downloads\www.myminifactory.com\download' }
if (-not $MODELS_PATH) { $MODELS_PATH = Join-Path $PSScriptRoot 'models' }
if (-not $JSON_PATH)   { $JSON_PATH   = Join-Path $PSScriptRoot 'downloads' }

$JUNK_FILES   = @('Thumbs.db', 'desktop.ini', '.DS_Store')
$PARTIAL_EXTS = @('.crdownload', '.part', '.partial', '.tmp', '.download')

function Get-ArchiveIndex([string]$jsonDir) {
    $index = @{}
    foreach ($jf in Get-ChildItem -LiteralPath $jsonDir -Filter 'model_*.json' -File) {
        $modelId = $jf.BaseName -replace '^model_', ''
        try {
            $json = Get-Content -LiteralPath $jf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch { continue }
        foreach ($item in @($json.files.items)) {
            if ($null -eq $item -or $null -eq $item.id) { continue }
            $index[[string]$item.id] = $modelId
        }
    }
    return $index
}

Clear-Host
Write-Host "MyMiniFactory - Move Downloads" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
if ($DRY_RUN) { Write-Host "DRY RUN - nothing will be changed" -ForegroundColor Yellow }
Write-Host ""

foreach ($p in @($DOWN_PATH, $MODELS_PATH, $JSON_PATH)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "ERROR: Path not found: $p" -ForegroundColor Red; exit 1 }
}

$root  = (Resolve-Path -LiteralPath $DOWN_PATH).ProviderPath.TrimEnd('\', '/')
$index = Get-ArchiveIndex $JSON_PATH

$moved = 0; $exists = 0; $noId = 0; $notRenamed = 0; $partial = 0; $failed = 0
$problems = New-Object System.Collections.Generic.List[string]

$files = Get-ChildItem -LiteralPath $root -File -Recurse -Force |
         Where-Object { $JUNK_FILES -notcontains $_.Name }

foreach ($file in $files) {
    $rel   = $file.FullName.Substring($root.Length).TrimStart('\', '/')
    $parts = $rel -split '[\\/]'

    # Leave anything inside a top-level "moved..." folder alone
    if ($parts.Count -gt 1 -and $parts[0] -like 'moved*') { continue }

    if ($PARTIAL_EXTS -contains $file.Extension.ToLower()) {
        Write-Host "Incomplete download, skipping: $rel" -ForegroundColor Yellow
        $partial++; $problems.Add("INCOMPLETE  $rel"); continue
    }

    # Work out the model ID
    $modelId = $null
    if ($rel -match 'archive_id=(\d+)' -and $index.ContainsKey($Matches[1])) {
        $modelId = $index[$Matches[1]]
    } elseif ($parts.Count -ge 2) {
        foreach ($dir in $parts[0..($parts.Count - 2)]) {
            if ($dir -match '^(\d+)(_|$)') { $modelId = $Matches[1]; break }
        }
    }

    if (-not $modelId -or $modelId -notmatch '^\d+$') {
        Write-Host "Cannot determine model ID, skipping: $rel" -ForegroundColor Red
        $noId++; $problems.Add("NO MODEL ID $rel"); continue
    }

    # A numeric name with no extension means 5_mmf_correct_filenames.ps1 has not renamed it yet
    if ($file.Extension -eq '' -and $file.BaseName -match '^\d+$') {
        Write-Host "Not renamed yet (run 5_mmf_correct_filenames.ps1 first), skipping: $rel" -ForegroundColor Yellow
        $notRenamed++; $problems.Add("NOT RENAMED $rel"); continue
    }

    $destDir  = Join-Path $MODELS_PATH "model_$modelId"
    $destFile = Join-Path $destDir $file.Name

    if (Test-Path -LiteralPath $destFile) {
        $destLen = (Get-Item -LiteralPath $destFile -Force).Length
        $note = if ($destLen -eq $file.Length) { "same size" } else { "DIFFERENT size: stored $destLen vs local $($file.Length)" }
        Write-Host "Already in models folder ($note), left in Downloads: $rel" -ForegroundColor Yellow
        $exists++; $problems.Add("EXISTS ($note)  $rel -> $destFile"); continue
    }

    if ($DRY_RUN) {
        Write-Host "Would move: $rel -> model_$modelId\$($file.Name)" -ForegroundColor Cyan
        $moved++; continue
    }

    try {
        if (-not (Test-Path -LiteralPath $destDir)) {
            [void][System.IO.Directory]::CreateDirectory($destDir)
        }
        # .NET move: literal paths, works across drives
        [System.IO.File]::Move($file.FullName, $destFile)
        Write-Host "Moved: $rel -> model_$modelId\$($file.Name)" -ForegroundColor Green
        $moved++
    } catch {
        Write-Host "Failed to move $rel : $($_.Exception.Message)" -ForegroundColor Red
        $failed++; $problems.Add("FAILED      $rel : $($_.Exception.Message)")
    }
}

# Remove folders that are now empty (or contain only junk files), deepest first
$removedDirs = 0
if (-not $DRY_RUN) {
    $dirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -Force |
            Sort-Object { $_.FullName.Length } -Descending
    foreach ($d in $dirs) {
        $rel = $d.FullName.Substring($root.Length).TrimStart('\', '/')
        if (($rel -split '[\\/]')[0] -like 'moved*') { continue }
        if (-not (Test-Path -LiteralPath $d.FullName)) { continue }
        $left = @(Get-ChildItem -LiteralPath $d.FullName -Force | Where-Object { $_.PSIsContainer -or $JUNK_FILES -notcontains $_.Name })
        if ($left.Count -eq 0) {
            try {
                Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
                $removedDirs++
            } catch {
                Write-Host "Could not remove empty folder $rel : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

# Save a list of everything that needs attention (replacing any old list)
$logFile = Join-Path $PSScriptRoot "move_problems.txt"
Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
if ($problems.Count -gt 0) { $problems | Set-Content -LiteralPath $logFile -Encoding UTF8 }

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-30}{1}" -f $(if ($DRY_RUN) { "Would move:" } else { "Moved:" }), $moved) -ForegroundColor Green
Write-Host ("{0,-30}{1}" -f "Already stored (not moved):", $exists) -ForegroundColor $(if ($exists) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Not renamed yet:", $notRenamed) -ForegroundColor $(if ($notRenamed) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Model ID unknown:", $noId) -ForegroundColor $(if ($noId) { 'Red' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Incomplete downloads:", $partial) -ForegroundColor $(if ($partial) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
if (-not $DRY_RUN) { Write-Host ("{0,-30}{1}" -f "Empty folders removed:", $removedDirs) -ForegroundColor Gray }
if ($problems.Count -gt 0) { Write-Host ""; Write-Host "Files needing attention are listed in: $logFile" -ForegroundColor Yellow }
if ($DRY_RUN) { Write-Host ""; Write-Host "Set `$DRY_RUN = `$false to apply these changes." -ForegroundColor Yellow }
