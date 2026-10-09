# MyMiniFactory - Optional: Extract all archives
# Extracts every .zip (and .7z/.rar if 7-Zip is installed) in the model folders.
#
# Default: each archive goes into its own "<archive name>_extracted" folder next
# to it, so files from different archives can never overwrite each other, and
# already-extracted archives are skipped on later runs.
#
# Keep the archives after extracting: the checker (3_mmf_check_and_download.sh) looks for them,
# and will report them as missing if they are deleted.
#
# PowerShell 7 (pwsh) is recommended: Windows PowerShell 5.1 fails on paths
# longer than 260 characters. If 7-Zip is installed it is used instead, which
# avoids that limit and is much faster.

# ============================================================================
# CONFIGURATION
# ============================================================================
# Folder to search for archives. Empty = the "models" folder next to this script,
# or put a full path here, e.g. 'D:\MyMiniFactory\models' or 'D:\LootStudios'.
$BASE_PATH = ''

# $false = extract into "<archive>_extracted" folders (recommended)
# $true  = extract straight into the model folder; files with the same name
#          are OVERWRITTEN and every archive is re-extracted on each run
$EXTRACT_IN_PLACE = $false

# Path to 7-Zip (optional). Needed for .7z and .rar files.
$SEVEN_ZIP = "C:\Program Files\7-Zip\7z.exe"
# ============================================================================

# The script's folder; when the script is pasted into the console instead of run as a file there
# is none, so the current folder (the one shown in the prompt) is used.
$SCRIPT_DIR = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not $BASE_PATH) { $BASE_PATH = Join-Path $SCRIPT_DIR 'models' }

Add-Type -AssemblyName System.IO.Compression.FileSystem

# Extract a .zip using literal paths (Expand-Archive mishandles [ ] in folder names).
# Refuses entries that would write outside the destination folder.
function Expand-ZipLiteral([string]$zipPath, [string]$dest) {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $sep = [System.IO.Path]::DirectorySeparatorChar
        $destFull = [System.IO.Path]::GetFullPath($dest).TrimEnd('\', '/') + $sep
        foreach ($entry in $zip.Entries) {
            $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destFull, $entry.FullName))
            if (-not $target.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Unsafe path inside archive: $($entry.FullName)"
            }
            if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                [void][System.IO.Directory]::CreateDirectory($target)
                continue
            }
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
        }
    } finally {
        $zip.Dispose()
    }
}

Write-Host "MyMiniFactory - Extract Archives" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -LiteralPath $BASE_PATH)) {
    Write-Host "ERROR: Base path does not exist: $BASE_PATH" -ForegroundColor Red
    exit 1
}

$use7z = Test-Path -LiteralPath $SEVEN_ZIP
$extensions = if ($use7z) { @('.zip', '.7z', '.rar') } else { @('.zip') }
Write-Host "Extractor: $(if ($use7z) { '7-Zip' } else { 'built-in (.zip only - install 7-Zip for .7z/.rar)' })" -ForegroundColor Gray
Write-Host "Mode: $(if ($EXTRACT_IN_PLACE) { 'in place (overwrites)' } else { 'separate _extracted folders' })" -ForegroundColor Gray
Write-Host ""

$archives = @(Get-ChildItem -LiteralPath $BASE_PATH -File -Recurse -Force |
              Where-Object { $extensions -contains $_.Extension.ToLower() })

if (-not $use7z) {
    $unsupported = @(Get-ChildItem -LiteralPath $BASE_PATH -File -Recurse -Force |
                     Where-Object { @('.7z', '.rar') -contains $_.Extension.ToLower() })
    if ($unsupported.Count -gt 0) {
        Write-Host "Note: $($unsupported.Count) .7z/.rar file(s) will be skipped because 7-Zip was not found at $SEVEN_ZIP" -ForegroundColor Yellow
        Write-Host ""
    }
}

$total = $archives.Count
if ($total -eq 0) { Write-Host "No archives found in $BASE_PATH" -ForegroundColor Yellow; exit 0 }
Write-Host "Found $total archive(s)" -ForegroundColor Green
Write-Host ""

$current = 0; $ok = 0; $skipped = 0; $failed = 0
$failedList = New-Object System.Collections.Generic.List[string]

foreach ($archive in $archives) {
    $current++
    $pct = [math]::Round(($current / $total) * 100, 1)
    $label = "[$current/$total - $pct%] $($archive.Name)"

    if ($EXTRACT_IN_PLACE) {
        $destination = $archive.DirectoryName
    } else {
        $destination = Join-Path $archive.DirectoryName ($archive.BaseName + "_extracted")
        if ((Test-Path -LiteralPath $destination) -and @(Get-ChildItem -LiteralPath $destination -Force).Count -gt 0) {
            Write-Host "$label - already extracted, skipping" -ForegroundColor DarkGray
            $skipped++
            continue
        }
    }

    Write-Host "$label - extracting..." -ForegroundColor Cyan
    $createdDest = $false
    try {
        if (-not (Test-Path -LiteralPath $destination)) {
            [void][System.IO.Directory]::CreateDirectory($destination)
            $createdDest = $true
        }

        if ($use7z) {
            $output = & $SEVEN_ZIP x -y "-o$destination" -- $archive.FullName 2>&1
            if ($LASTEXITCODE -ne 0) {
                $msg = ($output | Where-Object { $_ -match 'ERROR' } | Select-Object -First 3) -join ' '
                throw "7-Zip exit code $LASTEXITCODE. $msg"
            }
        } else {
            Expand-ZipLiteral $archive.FullName $destination
        }

        Write-Host "  OK" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        $failedList.Add($archive.FullName)
        # Remove a partial extraction folder so the next run retries it
        if (-not $EXTRACT_IN_PLACE -and $createdDest -and (Test-Path -LiteralPath $destination)) {
            Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$failedFile = Join-Path $SCRIPT_DIR "failed_archives.txt"
Remove-Item -LiteralPath $failedFile -Force -ErrorAction SilentlyContinue
if ($failedList.Count -gt 0) { $failedList | Set-Content -LiteralPath $failedFile -Encoding UTF8 }

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host ("{0,-26}{1}" -f "Extracted:", $ok) -ForegroundColor Green
Write-Host ("{0,-26}{1}" -f "Already extracted:", $skipped) -ForegroundColor Gray
Write-Host ("{0,-26}{1}" -f "Failed:", $failed) -ForegroundColor $(if ($failed) { 'Red' } else { 'Gray' })
if ($failed -gt 0) { Write-Host "Failed archives are listed in: $failedFile" -ForegroundColor Yellow }
