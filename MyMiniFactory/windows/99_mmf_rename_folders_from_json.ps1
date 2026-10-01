# MyMiniFactory - Optional, ALWAYS LAST: Rename model folders using names from the JSON metadata
# Renames  model_851789  ->  851789_Yhal_The_Skygazer  (or just the name)
#
# RUN THIS LAST. After renaming, the checker (3_mmf_check_and_download.sh), move (6_mmf_move_downloads.ps1) and
# extract steps no longer recognise the folders, because they expect model_<id>.
# Every rename is logged to rename_log.csv so it can be undone.
#
# Run with $DRY_RUN = $true first to preview the new names.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Folders. Empty = the "downloads" / "models" folder next to this script,
# or put a full path here, e.g. 'D:\MyMiniFactory\models'.
$JSON_PATH    = ''    # JSON metadata from step 2
$FOLDERS_PATH = ''    # model_<id> folders

# "ID_NAME"   -> 851789_Yhal_The_Skygazer  (recommended, always unique)
# "NAME_ONLY" -> Yhal_The_Skygazer
$NAMING_FORMAT = "ID_NAME"

# Maximum length of the name part (keeps paths under Windows limits)
$MAX_NAME_LENGTH = 80

# $true  = only show the new names, change nothing
# $false = actually rename folders
$DRY_RUN = $true
# ============================================================================

if (-not $JSON_PATH)    { $JSON_PATH    = Join-Path $PSScriptRoot 'downloads' }
if (-not $FOLDERS_PATH) { $FOLDERS_PATH = Join-Path $PSScriptRoot 'models' }

$RESERVED = '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$'

function Get-CleanName([string]$name, [int]$maxLen) {
    $clean = $name -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $clean = $clean -replace '\s+', '_'
    $clean = $clean -replace '_+', '_'
    $clean = $clean.Trim('_', ' ', '.')
    if ($clean.Length -gt $maxLen) {
        $clean = $clean.Substring(0, $maxLen).Trim('_', ' ', '.')
    }
    return $clean
}

Write-Host "MyMiniFactory - Rename Folders" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
if ($DRY_RUN) { Write-Host "DRY RUN - nothing will be changed" -ForegroundColor Yellow }
Write-Host ""

if (-not (Test-Path -LiteralPath $JSON_PATH))    { Write-Host "ERROR: JSON path not found: $JSON_PATH" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $FOLDERS_PATH)) { Write-Host "ERROR: Folders path not found: $FOLDERS_PATH" -ForegroundColor Red; exit 1 }

$jsonFiles = @(Get-ChildItem -LiteralPath $JSON_PATH -Filter "model_*.json" -File)
$total = $jsonFiles.Count
if ($total -eq 0) { Write-Host "ERROR: No model_*.json files found in $JSON_PATH" -ForegroundColor Red; exit 1 }

Write-Host "Found $total JSON files" -ForegroundColor Green
Write-Host ""

$renamed = 0; $already = 0; $notFound = 0; $conflicts = 0; $noName = 0; $failed = 0; $current = 0
$log = New-Object System.Collections.Generic.List[object]

foreach ($jsonFile in $jsonFiles) {
    $current++
    $modelId = $jsonFile.BaseName -replace '^model_', ''
    $prefix  = "[$current/$total] Model $modelId"
    $oldFolder = Join-Path $FOLDERS_PATH "model_$modelId"

    if (-not (Test-Path -LiteralPath $oldFolder)) {
        # Distinguish "already renamed" from "never downloaded"
        $existing = @(Get-ChildItem -LiteralPath $FOLDERS_PATH -Directory | Where-Object { $_.Name -like "${modelId}_*" })
        if ($existing.Count -gt 0) { $already++ }
        else {
            Write-Host "$prefix - no model_$modelId folder, skipping" -ForegroundColor DarkGray
            $notFound++
        }
        continue
    }

    try {
        $json = Get-Content -LiteralPath $jsonFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "$prefix - JSON could not be read, skipping" -ForegroundColor Red
        $failed++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($json.name)) {
        Write-Host "$prefix - no name in JSON, skipping" -ForegroundColor Yellow
        $noName++
        continue
    }

    $cleanName = Get-CleanName ([string]$json.name) $MAX_NAME_LENGTH
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        Write-Host "$prefix - name '$($json.name)' has no usable characters, skipping" -ForegroundColor Yellow
        $noName++
        continue
    }

    if ($NAMING_FORMAT -eq "ID_NAME") {
        $newName = "${modelId}_${cleanName}"
    } else {
        # Names like CON or NUL are reserved on Windows
        $newName = if ($cleanName -match $RESERVED) { $cleanName + '_' } else { $cleanName }
    }
    $newFolder = Join-Path $FOLDERS_PATH $newName

    if (Test-Path -LiteralPath $newFolder) {
        Write-Host "$prefix - target already exists: $newName" -ForegroundColor Yellow
        $conflicts++
        continue
    }

    if ($DRY_RUN) {
        Write-Host "$prefix - would rename: model_$modelId -> $newName" -ForegroundColor Cyan
        $renamed++
        continue
    }

    try {
        Rename-Item -LiteralPath $oldFolder -NewName $newName -ErrorAction Stop
        Write-Host "$prefix - renamed: model_$modelId -> $newName" -ForegroundColor Green
        $log.Add([pscustomobject]@{ OldName = "model_$modelId"; NewName = $newName; Time = (Get-Date -Format s) })
        $renamed++
    } catch {
        Write-Host "$prefix - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -like "*being used by another process*" -or $_.Exception.Message -like "*denied*") {
            Write-Host "  Tip: close any Explorer windows or programs using this folder and try again" -ForegroundColor Yellow
        }
        $failed++
    }
}

if ($log.Count -gt 0) {
    $logFile = Join-Path $PSScriptRoot "rename_log.csv"
    $log | Export-Csv -LiteralPath $logFile -NoTypeInformation -Append -Encoding UTF8
}

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-26}{1}" -f $(if ($DRY_RUN) { "Would rename:" } else { "Renamed:" }), $renamed) -ForegroundColor Green
Write-Host ("{0,-26}{1}" -f "Already renamed:", $already) -ForegroundColor Gray
Write-Host ("{0,-26}{1}" -f "No folder:", $notFound) -ForegroundColor Gray
Write-Host ("{0,-26}{1}" -f "Name conflicts:", $conflicts) -ForegroundColor $(if ($conflicts) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-26}{1}" -f "No usable name:", $noName) -ForegroundColor $(if ($noName) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-26}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
if (-not $DRY_RUN -and $log.Count -gt 0) { Write-Host "Renames logged to: $(Join-Path $PSScriptRoot 'rename_log.csv')" -ForegroundColor Gray }
if ($DRY_RUN) { Write-Host ""; Write-Host "Set `$DRY_RUN = `$false to apply these changes." -ForegroundColor Yellow }
