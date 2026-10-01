# MyMiniFactory - Step 5: Correct downloaded filenames
# Renames downloaded files (saved with numeric names and no extension) to the
# real filename from the model's JSON metadata, using the archive_id in the path.
#
# Works with any folder layout, as long as "archive_id=<number>" appears
# somewhere in the file's path. Files are renamed in place (not moved).
#
# Run with $DRY_RUN = $true first to see what would happen.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Root folder for all downloads. Set the PRINTS_DIR environment variable
# (e.g. setx PRINTS_DIR "D:\3DPrints") or change the default here.
$PRINTS_DIR = if ($env:PRINTS_DIR) { $env:PRINTS_DIR } else { Join-Path $HOME '3DPrints' }
# Where your browser's download manager saves MyMiniFactory files
# (set MMF_DOWNLOAD_PATH or change the default here).
$DOWN_PATH = if ($env:MMF_DOWNLOAD_PATH) { $env:MMF_DOWNLOAD_PATH } else { Join-Path $HOME 'Downloads\www.myminifactory.com\download' }
$JSON_PATH = Join-Path $PRINTS_DIR '.mmf_downloads\downloads'

# $true  = only show what would be renamed, change nothing
# $false = actually rename files
$DRY_RUN = $true
# ============================================================================

$JUNK_FILES   = @('Thumbs.db', 'desktop.ini', '.DS_Store')
$PARTIAL_EXTS = @('.crdownload', '.part', '.partial', '.tmp', '.download')

# Replace characters Windows does not allow in filenames
function Get-SafeFileName([string]$name) {
    $safe = $name -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    return $safe.TrimEnd(' ', '.')
}

# Build lookup: archive ID -> model ID + real filename, from all JSON files
function Get-ArchiveIndex([string]$jsonDir) {
    $index = @{}
    $bad = 0
    foreach ($jf in Get-ChildItem -LiteralPath $jsonDir -Filter 'model_*.json' -File) {
        $modelId = $jf.BaseName -replace '^model_', ''
        try {
            $json = Get-Content -LiteralPath $jf.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $bad++
            continue
        }
        foreach ($item in @($json.files.items)) {
            if ($null -eq $item -or $null -eq $item.id -or [string]::IsNullOrWhiteSpace($item.filename)) { continue }
            $index[[string]$item.id] = [pscustomobject]@{ ModelId = $modelId; Filename = [string]$item.filename }
        }
    }
    if ($bad -gt 0) { Write-Host "Warning: $bad JSON file(s) could not be read and were ignored." -ForegroundColor Yellow }
    return $index
}

Clear-Host
Write-Host "MyMiniFactory - Correct Filenames" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
if ($DRY_RUN) { Write-Host "DRY RUN - nothing will be changed" -ForegroundColor Yellow }
Write-Host ""

if (-not (Test-Path -LiteralPath $DOWN_PATH)) { Write-Host "ERROR: Download path not found: $DOWN_PATH" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $JSON_PATH)) { Write-Host "ERROR: JSON path not found: $JSON_PATH" -ForegroundColor Red; exit 1 }

$root  = (Resolve-Path -LiteralPath $DOWN_PATH).ProviderPath.TrimEnd('\', '/')
$index = Get-ArchiveIndex $JSON_PATH
Write-Host "Loaded $($index.Count) file entries from JSON metadata." -ForegroundColor Gray
Write-Host ""

$renamed = 0; $already = 0; $conflicts = 0; $noMeta = 0; $partial = 0; $failed = 0; $ignored = 0

$files = Get-ChildItem -LiteralPath $root -File -Recurse -Force |
         Where-Object { $JUNK_FILES -notcontains $_.Name }

foreach ($file in $files) {
    $rel = $file.FullName.Substring($root.Length).TrimStart('\', '/')

    if ($PARTIAL_EXTS -contains $file.Extension.ToLower()) {
        Write-Host "Incomplete download, skipping: $rel" -ForegroundColor Yellow
        $partial++
        continue
    }

    $targetName = $null

    if ($rel -match 'archive_id=(\d+)') {
        $archiveId = $Matches[1]
        $entry = $index[$archiveId]
        if ($null -eq $entry) {
            Write-Host "archive_id=$archiveId not found in any JSON (download its model's metadata first): $rel" -ForegroundColor Red
            $noMeta++
            continue
        }
        $targetName = Get-SafeFileName $entry.Filename
        if ($targetName -ne $entry.Filename) {
            Write-Host "Note: '$($entry.Filename)' contains characters Windows does not allow; using '$targetName'" -ForegroundColor Yellow
        }
    }
    elseif ($file.Extension -eq '' -and $file.BaseName -match '^\d+$' -and $file.Directory.Name -match '^[^=]+=(.+)$' -and $Matches[1] -notmatch '^\d+$') {
        # Fallback from the original script: parent folder is "key=<filename>"
        $targetName = Get-SafeFileName $Matches[1]
    }
    else {
        $ignored++
        continue
    }

    if ([string]::IsNullOrWhiteSpace($targetName)) {
        Write-Host "Could not work out a valid filename, skipping: $rel" -ForegroundColor Red
        $failed++
        continue
    }

    if ($file.Name -ieq $targetName) {
        $already++
        continue
    }

    $targetPath = Join-Path $file.DirectoryName $targetName
    if (Test-Path -LiteralPath $targetPath) {
        Write-Host "Target already exists, not renaming:" -ForegroundColor Red
        Write-Host "  $rel -> $targetName" -ForegroundColor Gray
        $conflicts++
        continue
    }

    if ($DRY_RUN) {
        Write-Host "Would rename: $rel -> $targetName" -ForegroundColor Cyan
        $renamed++
        continue
    }

    try {
        Rename-Item -LiteralPath $file.FullName -NewName $targetName -ErrorAction Stop
        Write-Host "Renamed: $rel -> $targetName" -ForegroundColor Green
        $renamed++
    } catch {
        Write-Host "Failed to rename $rel : $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-28}{1}" -f $(if ($DRY_RUN) { "Would rename:" } else { "Renamed:" }), $renamed) -ForegroundColor Green
Write-Host ("{0,-28}{1}" -f "Already correctly named:", $already)
Write-Host ("{0,-28}{1}" -f "Name conflicts:", $conflicts) -ForegroundColor $(if ($conflicts) { 'Red' } else { 'Gray' })
Write-Host ("{0,-28}{1}" -f "No matching metadata:", $noMeta) -ForegroundColor $(if ($noMeta) { 'Red' } else { 'Gray' })
Write-Host ("{0,-28}{1}" -f "Incomplete downloads:", $partial) -ForegroundColor $(if ($partial) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-28}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
Write-Host ("{0,-28}{1}" -f "Other files (left alone):", $ignored) -ForegroundColor Gray
if ($DRY_RUN) { Write-Host ""; Write-Host "Set `$DRY_RUN = `$false to apply these changes." -ForegroundColor Yellow }
