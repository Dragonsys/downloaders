# MyMiniFactory - Optional, ALWAYS LAST: Rename model folders using names from the JSON metadata
# Renames  model_851789  ->  Ghamak\851789_Yhal_The_Skygazer   (or another $FOLDER_STRUCTURE, see below)
#
# Folders renamed before ("<id>_<name>", side by side or in a designer folder) are moved to the
# chosen structure too - so it can be run again at any time, also after changing $FOLDER_STRUCTURE.
# The folders inside a model folder (Images, extracted files ...) are not changed.
#
# RUN THIS LAST: 6_mmf_move_downloads.ps1 puts files for a model that has no folder yet into a new
# model_<id> folder; running this script again moves it to its place.
# Every rename is logged to rename_log.csv so it can be undone.
#
# Run with $DRY_RUN = $true first to preview the new names.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Folders. Empty = the "downloads" / "models" folder next to this script,
# or put a full path here, e.g. 'D:\MyMiniFactory\models'.
$JSON_PATH    = ''    # JSON metadata from step 2
$FOLDERS_PATH = ''    # model folders

# Folder structure - available options:
#   "DESIGNER\ID_NAME"  -> MatMire_Makes\849932_Caterpillar   (default, recommended)
#   "DESIGNER\NAME"     -> MatMire_Makes\Caterpillar
#   "ID_NAME"           -> 849932_Caterpillar                 (all models side by side)
#   "NAME"              -> Caterpillar
# Change it and run again to re-sort: folders already sorted are moved to the new structure.
# Without the ID (the NAME options) the other scripts can't find the folders again, and nor can
# this one - so a NAME layout can't be changed back by this script. Use the ID options if unsure.
$FOLDER_STRUCTURE = "DESIGNER\ID_NAME"
# Designer folder name: "name" = the designer's display name (e.g. MatMire_Makes),
# "username" = their MyMiniFactory user name (e.g. MatMireMakes)
$AUTHOR_NAME = "name"
# Folder for models whose metadata names no designer (e.g. private models from 99_mmf_private_models.js)
$UNKNOWN_AUTHOR = "_Unknown_designer"

# Maximum length of the name part (keeps paths under Windows limits)
$MAX_NAME_LENGTH = 80

# $true  = only show the new names, change nothing
# $false = actually rename folders
$DRY_RUN = $true
# ============================================================================

if (-not $JSON_PATH)    { $JSON_PATH    = Join-Path $PSScriptRoot 'downloads' }
if (-not $FOLDERS_PATH) { $FOLDERS_PATH = Join-Path $PSScriptRoot 'models' }

$STRUCTURES = @('DESIGNER\ID_NAME', 'DESIGNER\NAME', 'ID_NAME', 'NAME')
$structure = ([string]$FOLDER_STRUCTURE).Trim().Replace('/', '\').ToUpperInvariant()
if ($STRUCTURES -notcontains $structure) {
    Write-Host "ERROR: unknown `$FOLDER_STRUCTURE '$FOLDER_STRUCTURE' - use one of: $($STRUCTURES -join ', ')" -ForegroundColor Red
    exit 1
}
$byDesigner = $structure.StartsWith('DESIGNER\')
$withId     = $structure.EndsWith('ID_NAME')

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

# Model folders in $root: "model_<id>" or "<id>_<name>", directly in it or one level down in a
# designer folder. Returns id -> list of folder paths (only ids in $ids).
function Get-ModelFolderIndex([string]$root, [hashtable]$ids) {
    $index = @{}
    $add = { param($id, $path) if (-not $index.ContainsKey($id)) { $index[$id] = New-Object System.Collections.Generic.List[string] }; $index[$id].Add($path) }
    foreach ($d in Get-ChildItem -LiteralPath $root -Directory -Force) {
        if ($d.Name -match '^model_(\d+)$' -or $d.Name -match '^(\d+)_') {
            if ($ids.ContainsKey($Matches[1])) { & $add $Matches[1] $d.FullName; continue }
        }
        # Not a model folder: a designer folder
        foreach ($s in Get-ChildItem -LiteralPath $d.FullName -Directory -Force -ErrorAction SilentlyContinue) {
            if ($s.Name -match '^model_(\d+)$' -or $s.Name -match '^(\d+)_') {
                if ($ids.ContainsKey($Matches[1])) { & $add $Matches[1] $s.FullName }
            }
        }
    }
    return $index
}

Write-Host "MyMiniFactory - Rename Folders" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
if ($DRY_RUN) { Write-Host "DRY RUN - nothing will be changed" -ForegroundColor Yellow }
Write-Host ""

if (-not (Test-Path -LiteralPath $JSON_PATH))    { Write-Host "ERROR: JSON path not found: $JSON_PATH" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $FOLDERS_PATH)) { Write-Host "ERROR: Folders path not found: $FOLDERS_PATH" -ForegroundColor Red; exit 1 }
$FOLDERS_PATH = (Resolve-Path -LiteralPath $FOLDERS_PATH).ProviderPath.TrimEnd('\', '/')

$jsonFiles = @(Get-ChildItem -LiteralPath $JSON_PATH -Filter "model_*.json" -File)
$total = $jsonFiles.Count
if ($total -eq 0) { Write-Host "ERROR: No model_*.json files found in $JSON_PATH" -ForegroundColor Red; exit 1 }

Write-Host "Found $total JSON files" -ForegroundColor Green
$ids = @{}
foreach ($jf in $jsonFiles) { $ids[($jf.BaseName -replace '^model_', '')] = $true }
$folderIndex = Get-ModelFolderIndex $FOLDERS_PATH $ids
$topDirs = @{}
foreach ($d in Get-ChildItem -LiteralPath $FOLDERS_PATH -Directory -Force) { $topDirs[$d.Name.ToLowerInvariant()] = $d.Name }
Write-Host "Found model folders for $($folderIndex.Count) of them" -ForegroundColor Green
Write-Host ""

$renamed = 0; $already = 0; $notFound = 0; $conflicts = 0; $several = 0; $noName = 0; $failed = 0; $current = 0
$log = New-Object System.Collections.Generic.List[object]
$designers = @{}
$leftDirs = @{}

foreach ($jsonFile in $jsonFiles) {
    $current++
    $modelId = $jsonFile.BaseName -replace '^model_', ''
    $prefix  = "[$current/$total] Model $modelId"

    if (-not $folderIndex.ContainsKey($modelId)) {
        Write-Host "$prefix - no model_$modelId or ${modelId}_* folder, skipping" -ForegroundColor DarkGray
        $notFound++
        continue
    }
    $found = @($folderIndex[$modelId])
    if ($found.Count -gt 1) {
        # e.g. an images-only "<id>_<name>" folder next to model_<id>: leave it to the user
        Write-Host "$prefix - several folders, left alone: $(($found | ForEach-Object { $_.Substring($FOLDERS_PATH.Length + 1) }) -join ' | ')" -ForegroundColor Yellow
        $several++
        continue
    }
    $oldFolder = $found[0]
    $oldRel    = $oldFolder.Substring($FOLDERS_PATH.Length + 1)

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

    if ($withId) {
        $newName = "${modelId}_${cleanName}"
    } else {
        # Names like CON or NUL are reserved on Windows
        $newName = if ($cleanName -match $RESERVED) { $cleanName + '_' } else { $cleanName }
    }

    $newRel = $newName
    if ($byDesigner) {
        $d = $json.designer
        $author = ''
        if ($d) {
            $author = if ($AUTHOR_NAME -eq 'username') { [string]$d.username } else { [string]$d.name }
            if ([string]::IsNullOrWhiteSpace($author)) { $author = if ($AUTHOR_NAME -eq 'username') { [string]$d.name } else { [string]$d.username } }
        }
        $author = Get-CleanName $author $MAX_NAME_LENGTH
        if ([string]::IsNullOrWhiteSpace($author)) { $author = $UNKNOWN_AUTHOR }
        if ($author -match $RESERVED) { $author += '_' }
        # A designer folder that's already there with other upper/lower case is used as it is
        # (Windows treats them as the same folder)
        $key = $author.ToLowerInvariant()
        if ($designers.ContainsKey($key)) { $author = $designers[$key] }
        else {
            if ($topDirs.ContainsKey($key)) { $author = $topDirs[$key] }
            $designers[$key] = $author
        }
        $newRel = Join-Path $author $newName
    }
    $newFolder = Join-Path $FOLDERS_PATH $newRel

    if ($oldFolder -ceq $newFolder) { $already++; continue }

    # Same path apart from upper/lower case (e.g. the designer changed the case of their name):
    # Windows sees it as the same folder, so it's moved via a temporary name below
    $caseOnly = ($oldFolder -ieq $newFolder)
    if (-not $caseOnly -and (Test-Path -LiteralPath $newFolder)) {
        Write-Host "$prefix - target already exists: $newRel" -ForegroundColor Yellow
        $conflicts++
        continue
    }

    if ($DRY_RUN) {
        Write-Host "$prefix - would move: $oldRel -> $newRel" -ForegroundColor Cyan
        $renamed++
        continue
    }

    try {
        $parent = Split-Path -Parent $newFolder
        if (-not (Test-Path -LiteralPath $parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }
        if ($caseOnly) {
            $tmp = Join-Path $parent (".rename_tmp_$modelId")
            [System.IO.Directory]::Move($oldFolder, $tmp)
            [System.IO.Directory]::Move($tmp, $newFolder)
        } else {
            [System.IO.Directory]::Move($oldFolder, $newFolder)
        }
        Write-Host "$prefix - moved: $oldRel -> $newRel" -ForegroundColor Green
        $log.Add([pscustomobject]@{ OldName = $oldRel; NewName = $newRel; Time = (Get-Date -Format s) })
        $leftDirs[(Split-Path -Parent $oldFolder)] = $true
        $renamed++
    } catch {
        Write-Host "$prefix - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Message -like "*being used by another process*" -or $_.Exception.Message -like "*denied*") {
            Write-Host "  Tip: close any Explorer windows or programs using this folder and try again" -ForegroundColor Yellow
        }
        $failed++
    }
}

# Designer folders emptied by the moves (e.g. a designer who renamed themselves) are removed
$removedDirs = 0
foreach ($dir in $leftDirs.Keys) {
    if ($dir -ieq $FOLDERS_PATH -or -not (Test-Path -LiteralPath $dir)) { continue }
    if (@(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
        try { Remove-Item -LiteralPath $dir -Force -ErrorAction Stop; $removedDirs++ } catch {}
    }
}

if ($log.Count -gt 0) {
    $logFile = Join-Path $PSScriptRoot "rename_log.csv"
    $log | Export-Csv -LiteralPath $logFile -NoTypeInformation -Append -Encoding UTF8
}

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-26}{1}" -f $(if ($DRY_RUN) { "Would move/rename:" } else { "Moved/renamed:" }), $renamed) -ForegroundColor Green
Write-Host ("{0,-26}{1}" -f "Already in place:", $already) -ForegroundColor Gray
if ($byDesigner) { Write-Host ("{0,-26}{1}" -f "Designers:", $designers.Count) -ForegroundColor Gray }
Write-Host ("{0,-26}{1}" -f "No folder:", $notFound) -ForegroundColor Gray
Write-Host ("{0,-26}{1}" -f "Several folders:", $several) -ForegroundColor $(if ($several) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-26}{1}" -f "Name conflicts:", $conflicts) -ForegroundColor $(if ($conflicts) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-26}{1}" -f "No usable name:", $noName) -ForegroundColor $(if ($noName) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-26}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
if ($removedDirs) { Write-Host ("{0,-26}{1}" -f "Empty folders removed:", $removedDirs) -ForegroundColor Gray }
if (-not $DRY_RUN -and $log.Count -gt 0) { Write-Host "Renames logged to: $(Join-Path $PSScriptRoot 'rename_log.csv')" -ForegroundColor Gray }
if ($DRY_RUN) { Write-Host ""; Write-Host "Set `$DRY_RUN = `$false to apply these changes." -ForegroundColor Yellow }
