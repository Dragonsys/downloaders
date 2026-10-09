# MyMiniFactory - Optional: move the images you downloaded in the browser into the model folders
#
# 3_mmf_check_and_download.sh downloads the models' images itself, except those whose name ends
# in upper-case ".JPG" (MyMiniFactory's bot check refuses those to scripts). It lists them in
# missing_images.txt for your browser's download manager, and in missing_images_map.tsv says
# which model folder each one belongs in. After downloading them with the browser, this script
# moves each one to  <MODELS_PATH>\[<designer>\]<model folder>\Images\<name>  - the same place and name the
# Linux script uses for the other images (name without the "1000X1000-" size prefix).
#
# The downloaded images are recognised by their file name; for common names (e.g. "1.JPG") also by
# the image's upload folder in the path (assets.myminifactory.com/object-images/<upload>/...).
# Each file is checked to be a real JPEG first (not a saved error page). Nothing is overwritten.
#
# Run with $DRY_RUN = $true first to check.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Leave empty for the defaults, or put a full path here.
# Where your browser's download manager saved the images
# (empty = Downloads\assets.myminifactory.com in your user folder).
$DOWN_PATH = ''
# The folder holding the model folders (empty = the "models" folder next to this script).
$MODELS_PATH = ''
# The list written by 3_mmf_check_and_download.sh (empty = missing_images_map.tsv next to this script).
$MAP_FILE = ''

# $true  = only show what would be moved, change nothing
# $false = actually move the images and remove emptied download folders
$DRY_RUN = $true
# ============================================================================

if (-not $DOWN_PATH)   { $DOWN_PATH   = Join-Path $HOME 'Downloads\assets.myminifactory.com' }
# The script's folder; when the script is pasted into the console instead of run as a file there
# is none, so the current folder (the one shown in the prompt) is used.
$SCRIPT_DIR = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $MODELS_PATH) { $MODELS_PATH = Join-Path $SCRIPT_DIR 'models' }
if (-not $MAP_FILE)    { $MAP_FILE    = Join-Path $SCRIPT_DIR 'missing_images_map.tsv' }

$PARTIAL_EXTS = @('.crdownload', '.part', '.partial', '.tmp', '.download')

# Replace characters Windows does not allow in file names
function Get-SafeFileName([string]$name) {
    $safe = $name -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    return $safe.TrimEnd(' ', '.')
}

# JPEG files start with FF D8 FF
function Test-Jpeg([string]$path) {
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try { $b = New-Object byte[] 3; $n = $fs.Read($b, 0, 3) } finally { $fs.Close() }
        return ($n -eq 3 -and $b[0] -eq 0xFF -and $b[1] -eq 0xD8 -and $b[2] -eq 0xFF)
    } catch { return $false }
}

# Model folders in $root: "model_<id>" or "<id>_<name>" (renamed by 99_mmf_rename_folders_from_json.ps1),
# directly in it or one level down in a designer folder. Returns id -> list of folder paths (only ids in $ids).
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


# The model's folder in $MODELS_PATH, found by its id (model_<id>, or the one "<id>_<name>" folder -
# if there are several, the only one that isn't empty); else the folder named as in the map
function Get-ModelDir([string]$modelId, [string]$mapName) {
    $named = Join-Path $MODELS_PATH $mapName
    if (-not $folderIndex.ContainsKey($modelId)) { return $named }
    $found = @($folderIndex[$modelId])
    $plain = @($found | Where-Object { (Split-Path -Leaf $_) -eq "model_$modelId" })
    if ($plain.Count -ge 1) { return $plain[0] }
    if ($found.Count -eq 1) { return $found[0] }
    $same = @($found | Where-Object { (Split-Path -Leaf $_) -eq $mapName })
    if ($same.Count -eq 1) { return $same[0] }
    $nonEmpty = @($found | Where-Object { @(Get-ChildItem -LiteralPath $_ -Force).Count -gt 0 })
    if ($nonEmpty.Count -eq 1) { return $nonEmpty[0] }
    return $named
}

Clear-Host
Write-Host "MyMiniFactory - Move Browser-Downloaded Images" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
if ($DRY_RUN) { Write-Host "DRY RUN - nothing will be changed" -ForegroundColor Yellow }
Write-Host ""

foreach ($p in @($DOWN_PATH, $MODELS_PATH, $MAP_FILE)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "ERROR: Path not found: $p" -ForegroundColor Red; exit 1 }
}
$root = (Resolve-Path -LiteralPath $DOWN_PATH).ProviderPath.TrimEnd('\', '/')

# ---- Read the map: url, model_id, folder (path on the Linux side), file (Images\<name>) ----
$entries = New-Object System.Collections.Generic.List[object]
$lineNo = 0
foreach ($line in Get-Content -LiteralPath $MAP_FILE -Encoding UTF8) {
    $lineNo++
    $line = $line.TrimEnd("`r")
    if ($lineNo -eq 1 -and $line -like 'url*') { continue }      # header
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $c = $line -split "`t"
    if ($c.Count -lt 4) { Write-Host "Skipping unreadable line $lineNo of the map" -ForegroundColor Yellow; continue }
    $url = $c[0]
    $urlName = [System.Uri]::UnescapeDataString(($url -split '\?')[0].Split('/')[-1])
    $upload = if ($url -match '/object-images/([^/]+)/') { $Matches[1] } else { '' }
    # The model folder's name: the last part of the folder path the Linux script wrote
    $folderName = ($c[2] -split '[\\/]' | Where-Object { $_ })[-1]
    $target = Get-SafeFileName (($c[3] -split '[\\/]')[-1])
    $entries.Add([pscustomobject]@{ Url = $url; UrlName = $urlName; Upload = $upload; ModelId = $c[1];
                                    Folder = $folderName; Target = $target })
}
Write-Host "Images in the map: $($entries.Count)" -ForegroundColor Gray
$MODELS_PATH = (Resolve-Path -LiteralPath $MODELS_PATH).ProviderPath.TrimEnd('\', '/')
$ids = @{}
foreach ($e in $entries) { $ids[$e.ModelId] = $true }
$folderIndex = Get-ModelFolderIndex $MODELS_PATH $ids

# ---- Index the downloaded files by name (only names that occur in the map) ----
$wanted = @{}
foreach ($e in $entries) { $wanted[$e.UrlName.ToLowerInvariant()] = $true; $wanted[$e.Target.ToLowerInvariant()] = $true }
$byName = @{}
foreach ($f in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
    $k = $f.Name.ToLowerInvariant()
    if (-not $wanted.ContainsKey($k)) { continue }
    if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object System.Collections.Generic.List[object] }
    $byName[$k].Add($f)
}

$moved = 0; $already = 0; $notFound = 0; $ambiguous = 0; $notJpeg = 0; $partial = 0; $failed = 0
$problems = New-Object System.Collections.Generic.List[string]
$used = @{}

foreach ($e in $entries) {
    $modelDir = Get-ModelDir $e.ModelId $e.Folder
    $destDir  = Join-Path $modelDir 'Images'
    $destFile = Join-Path $destDir $e.Target
    $show     = "$($modelDir.Substring($MODELS_PATH.Length + 1))\Images\$($e.Target)"

    if (Test-Path -LiteralPath $destFile) { $already++; continue }

    # Candidates: files named like the image (with or without the size prefix), not used yet
    $cands = @()
    foreach ($k in @($e.UrlName.ToLowerInvariant(), $e.Target.ToLowerInvariant()) | Select-Object -Unique) {
        if ($byName.ContainsKey($k)) { $cands += @($byName[$k] | Where-Object { -not $used.ContainsKey($_.FullName) }) }
    }
    # Several with the same name (e.g. "1.JPG"): prefer the one in this image's upload folder
    if ($cands.Count -gt 1 -and $e.Upload) {
        $inUpload = @($cands | Where-Object { $_.FullName -like "*\$($e.Upload)\*" })
        if ($inUpload.Count -ge 1) { $cands = $inUpload }
    }

    if ($cands.Count -eq 0) {
        $notFound++; $problems.Add("NOT FOUND   $($e.UrlName)  (model $($e.ModelId), $($e.Url))"); continue
    }
    if ($cands.Count -gt 1) {
        Write-Host "Several downloads match $($e.UrlName), left alone" -ForegroundColor Yellow
        $ambiguous++; $problems.Add("AMBIGUOUS   $($e.UrlName)  (model $($e.ModelId)): " + (($cands | ForEach-Object { $_.FullName }) -join ' | ')); continue
    }

    $src = $cands[0]
    $rel = $src.FullName.Substring($root.Length).TrimStart('\', '/')
    if ($PARTIAL_EXTS -contains $src.Extension.ToLower()) {
        $partial++; $problems.Add("INCOMPLETE  $rel"); continue
    }
    if (-not (Test-Jpeg $src.FullName)) {
        Write-Host "Not a JPEG image (maybe an error page was saved), left alone: $rel" -ForegroundColor Red
        $notJpeg++; $problems.Add("NOT A JPEG  $rel"); continue
    }
    $used[$src.FullName] = $true

    if ($DRY_RUN) {
        Write-Host "Would move: $rel -> $show" -ForegroundColor Cyan
        $moved++; continue
    }
    try {
        [void][System.IO.Directory]::CreateDirectory($destDir)
        # .NET move: literal paths, works across drives (e.g. C: to a network drive)
        [System.IO.File]::Move($src.FullName, $destFile)
        Write-Host "Moved: $rel -> $show" -ForegroundColor Green
        $moved++
    } catch {
        Write-Host "Failed to move $rel : $($_.Exception.Message)" -ForegroundColor Red
        $failed++; $problems.Add("FAILED      $rel : $($_.Exception.Message)")
    }
}

# Remove download folders that are now empty, deepest first (never the download folder itself)
$removedDirs = 0
if (-not $DRY_RUN) {
    $dirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -Force | Sort-Object { $_.FullName.Length } -Descending
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d.FullName)) { continue }
        if (@(Get-ChildItem -LiteralPath $d.FullName -Force).Count -eq 0) {
            try { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop; $removedDirs++ } catch { }
        }
    }
}

# Save a list of everything that needs attention (replacing any old list)
$logFile = Join-Path $SCRIPT_DIR "move_images_problems.txt"
Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
if ($problems.Count -gt 0) { $problems | Set-Content -LiteralPath $logFile -Encoding UTF8 }

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-30}{1}" -f $(if ($DRY_RUN) { "Would move:" } else { "Moved:" }), $moved) -ForegroundColor Green
Write-Host ("{0,-30}{1}" -f "Already in the model folder:", $already) -ForegroundColor Gray
Write-Host ("{0,-30}{1}" -f "Not downloaded yet:", $notFound) -ForegroundColor $(if ($notFound) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Several matches:", $ambiguous) -ForegroundColor $(if ($ambiguous) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Not a JPEG:", $notJpeg) -ForegroundColor $(if ($notJpeg) { 'Red' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Incomplete downloads:", $partial) -ForegroundColor $(if ($partial) { 'Yellow' } else { 'Gray' })
Write-Host ("{0,-30}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
if (-not $DRY_RUN) { Write-Host ("{0,-30}{1}" -f "Empty folders removed:", $removedDirs) -ForegroundColor Gray }
if ($problems.Count -gt 0) { Write-Host ""; Write-Host "Images needing attention are listed in: $logFile" -ForegroundColor Yellow }
if ($DRY_RUN) { Write-Host ""; Write-Host "Set `$DRY_RUN = `$false to apply these changes." -ForegroundColor Yellow }
