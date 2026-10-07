# Cults3D - Step 2: sort the browser downloads into <creator>\<model>\
#
# 1_cults_collect_and_download.js saved cults_list.json and made the browser download every
# model into your Downloads folder. This script recognises each download by its CONTENTS (the
# file names inside a zip are the model's file names listed on the order page - the zip's own
# name is just the creator's upload name), and for every model:
#   <CULTS_PATH>\<creator>\<model>\files\         the model files (zip extracted; zips inside
#                                                 the zip are extracted into a folder of their own)
#   <CULTS_PATH>\<creator>\<model>\images\        the model's pictures (fetched from Cults3D)
#   <CULTS_PATH>\<creator>\<model>\description.html
# Sorted models are recorded in <CULTS_PATH>\.cults_downloaded.tsv, and cults_done.js is written
# next to this script: paste it into the Console on cults3d.com once, and the browser script
# won't download those models again.
# Nothing is overwritten. Downloads that match no model are left alone and listed.
#
# Run it with $DRY_RUN = $true (the default) first: it only shows what it would do.
# PowerShell 5.1 compatible (PowerShell 7 recommended).

# ==============================
# SETTINGS
# ==============================
$CULTS_PATH = ''          # where the models go; empty = the folder this script is in
$DOWN_PATH  = ''          # where the browser saved the downloads; empty = your Windows Downloads folder
$LIST_FILE  = ''          # cults_list.json; empty = the newest cults_list*.json in $DOWN_PATH or next to this script
$EXTRACT    = $true       # $true = extract zips into files\ ; $false = move the zip into files\
$IMAGES     = $true       # fetch the pictures
$DESCRIPTION = $true      # write description.html
$DELETE_DOWNLOADS = $true # remove a download from $DOWN_PATH once it is sorted
$IMAGE_DELAY_SECONDS = 1
$DRY_RUN    = $true       # $true = only show what would happen
# ==============================

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $CULTS_PATH) { $CULTS_PATH = $PSScriptRoot }
if (-not $DOWN_PATH) {
    $DOWN_PATH = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
    if ($DOWN_PATH) { $DOWN_PATH = [Environment]::ExpandEnvironmentVariables($DOWN_PATH) } else { $DOWN_PATH = Join-Path $env:USERPROFILE 'Downloads' }
}
$LEDGER = Join-Path $CULTS_PATH '.cults_downloaded.tsv'

Write-Host "Cults3D - sort downloads" -ForegroundColor Cyan
Write-Host "Models go to: $CULTS_PATH"
Write-Host "Downloads in: $DOWN_PATH"
if ($DRY_RUN) { Write-Host "DRY RUN - nothing is changed (set `$DRY_RUN = `$false to do it)" -ForegroundColor Yellow }

if (-not $LIST_FILE) {
    $cand = @()
    foreach ($d in @($DOWN_PATH, $PSScriptRoot)) { if (Test-Path -LiteralPath $d) { $cand += Get-ChildItem -LiteralPath $d -File -Filter 'cults_list*.json' } }
    $LIST_FILE = ($cand | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}
if (-not $LIST_FILE -or -not (Test-Path -LiteralPath $LIST_FILE)) { Write-Host "cults_list.json not found - run 1_cults_collect_and_download.js first." -ForegroundColor Red; exit 1 }
Write-Host "List:         $LIST_FILE"
$list = Get-Content -LiteralPath $LIST_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
$models = @($list.models)
Write-Host "$($models.Count) models in the list"
Write-Host ""

# ---------- helpers ----------
function Safe-Name([string]$s, [int]$max = 100) {
    $s = ($s -replace '[\x00-\x1f]', '') -replace '[<>:"/\\|?*]', '_'
    $s = $s.Trim().TrimEnd('.', ' ').TrimStart('.', ' ')
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max).TrimEnd('.', ' ') }
    return $s
}
function Norm([string]$s) { return ($s.ToLowerInvariant() -replace '\s+', ' ').Trim() }
# a download saved twice gets " (1)" etc. from the browser
function Base-Name([string]$n) { return ($n -replace ' \(\d+\)(\.[^.]*)?$', '$1') }

$ledger = @{}
if (Test-Path -LiteralPath $LEDGER) {
    foreach ($l in Get-Content -LiteralPath $LEDGER -Encoding UTF8) { $p = $l -split "`t"; if ($p[0]) { $ledger[$p[0]] = $p[1] } }
}
function Record([string]$key, [string]$rel) {
    if ($DRY_RUN) { return }
    $ledger[$key] = $rel
    Add-Content -LiteralPath $LEDGER -Value ("{0}`t{1}`t{2}" -f $key, $rel, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -Encoding UTF8
}

# ---------- what's in the Downloads folder ----------
$downloads = @()
foreach ($f in Get-ChildItem -LiteralPath $DOWN_PATH -File) {
    if ($f.Name -match '\.(crdownload|tmp|part)$' -or $f.Name -like 'cults_list*.json') { continue }
    $entry = [pscustomobject]@{ File = $f; Leaves = $null; Used = $false }
    if ($f.Extension -eq '.zip') {
        try {
            $z = [IO.Compression.ZipFile]::OpenRead($f.FullName)
            $entry.Leaves = @($z.Entries | Where-Object { $_.Name } | ForEach-Object { Norm $_.Name })
            $z.Dispose()
        } catch { Write-Host "  (cannot read $($f.Name): $($_.Exception.Message))" -ForegroundColor DarkYellow }
    }
    $downloads += $entry
}
Write-Host "$($downloads.Count) files in the Downloads folder"
Write-Host ""

# find the download(s) for a model: a zip containing all of the model's files, or the files themselves
function Find-Downloads($m) {
    $names = @($m.files | ForEach-Object { Norm $_.name })
    $all = @($m.downloads | Where-Object { $_.kind -eq 'all' })
    if ($names.Count -eq 0) { return @() }
    if ($all.Count -gt 0) {
        $hits = @($downloads | Where-Object { -not $_.Used -and $_.Leaves } | Where-Object {
            $leaves = $_.Leaves; @($names | Where-Object { $leaves -notcontains $_ }).Count -eq 0 } |
            Sort-Object { $_.File.LastWriteTime } -Descending)
        if ($hits.Count -gt 0) { return @($hits[0]) }
        # a model with one file: "Download all" can give that file itself
        if ($names.Count -eq 1) {
            $h = @($downloads | Where-Object { -not $_.Used -and (Norm (Base-Name $_.File.Name)) -eq $names[0] } | Sort-Object { $_.File.LastWriteTime } -Descending)
            if ($h.Count -gt 0) { return @($h[0]) }
        }
        return @()
    }
    # no "Download all": every file was downloaded on its own
    $got = @()
    foreach ($n in $names) {
        $h = @($downloads | Where-Object { -not $_.Used -and (Norm (Base-Name $_.File.Name)) -eq $n } | Sort-Object { $_.File.LastWriteTime } -Descending)
        if ($h.Count -eq 0) { return @() }
        $got += $h[0]
    }
    return $got
}

# extract a zip into $dest: single wrapper folders are left out, nothing is overwritten
function Expand-Zip([string]$zipPath, [string]$dest) {
    $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($z.Entries | Where-Object { $_.Name })
        $parts = @($entries | ForEach-Object { ,@($_.FullName -replace '\\', '/' -split '/') })
        $strip = 0
        while ($true) {
            $firsts = @($parts | ForEach-Object { if ($_.Count -gt $strip + 1) { $_[$strip] } else { '<file>' } } | Select-Object -Unique)
            if ($firsts.Count -eq 1 -and $firsts[0] -ne '<file>') { $strip++ } else { break }
        }
        $kept = 0; $written = 0
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $rel = (@($parts[$i] | Select-Object -Skip $strip) | ForEach-Object { Safe-Name $_ 120 }) -join '\'
            $out = Join-Path $dest $rel
            if (Test-Path -LiteralPath $out) { $kept++; continue }
            New-Item -ItemType Directory -Force -Path (Split-Path -LiteralPath $out) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[$i], $out)
            $written++
        }
        return @($written, $kept)
    } finally { $z.Dispose() }
}

$sorted = 0; $missing = @(); $failed = 0; $pics = 0
$sortedBefore = @($models | Where-Object { $ledger.ContainsKey($_.key) }).Count
$owner = @{}
foreach ($k in $ledger.Keys) { $owner[$ledger[$k]] = $k }

foreach ($m in $models) {
    if ($ledger.ContainsKey($m.key)) { continue }
    $rel = (Safe-Name $(if ($m.creator) { $m.creator } else { 'Unknown creator' })) + '\' + (Safe-Name $m.title)
    if ($owner.ContainsKey($rel) -and $owner[$rel] -ne $m.key) { $rel = "$rel ($($m.creation))" }
    $dir = Join-Path $CULTS_PATH $rel
    $hits = @(Find-Downloads $m)
    if ($hits.Count -eq 0) { $missing += $m; continue }
    foreach ($h in $hits) { $h.Used = $true }
    Write-Host ("  -> {0}  =>  {1}\  ({2})" -f $m.title, $rel, (($hits | ForEach-Object { $_.File.Name }) -join ', ')) -ForegroundColor Cyan
    if ($DRY_RUN) { $sorted++; continue }
    try {
        $files = Join-Path $dir 'files'
        New-Item -ItemType Directory -Force -Path $files | Out-Null
        foreach ($h in $hits) {
            if ($h.File.Extension -eq '.zip' -and $EXTRACT) {
                $r = Expand-Zip $h.File.FullName $files
                Write-Host ("     files\: {0} extracted{1}" -f $r[0], $(if ($r[1]) { ", $($r[1]) already there (kept)" } else { '' }))
            } else {
                $to = Join-Path $files (Safe-Name (Base-Name $h.File.Name) 120)
                if (-not (Test-Path -LiteralPath $to)) { Copy-Item -LiteralPath $h.File.FullName -Destination $to }
            }
        }
        # zips inside the model's files: into a folder of their own
        if ($EXTRACT) {
            foreach ($inner in @(Get-ChildItem -LiteralPath $files -Recurse -File -Filter '*.zip')) {
                $to = Join-Path $inner.DirectoryName ([IO.Path]::GetFileNameWithoutExtension($inner.Name))
                try { [void](Expand-Zip $inner.FullName $to); Remove-Item -LiteralPath $inner.FullName } catch { Write-Host "     (kept $($inner.Name): $($_.Exception.Message))" -ForegroundColor DarkYellow }
            }
        }
        if ($DESCRIPTION -and -not (Test-Path -LiteralPath (Join-Path $dir 'description.html'))) {
            $enc = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
            $html = "<!doctype html><meta charset=""utf-8""><title>$(& $enc $m.title)</title>`n<h1>$(& $enc $m.title)</h1>`n" +
                "<p>by $(& $enc $m.creator) - <a href=""$(& $enc $m.url)"">$(& $enc $m.url)</a><br>Licence: $(& $enc $m.license)</p>`n" + [string]$m.description
            [IO.File]::WriteAllText((Join-Path $dir 'description.html'), $html, (New-Object Text.UTF8Encoding $false))
        }
        if ($IMAGES -and $m.pictures) {
            $img = Join-Path $dir 'images'
            New-Item -ItemType Directory -Force -Path $img | Out-Null
            foreach ($u in @($m.pictures)) {
                $name = Safe-Name ([Uri]::UnescapeDataString(($u -split '\?')[0].Split('/')[-1])) 120
                $to = Join-Path $img $name
                if (Test-Path -LiteralPath $to) { continue }
                Start-Sleep -Seconds $IMAGE_DELAY_SECONDS
                try {
                    Invoke-WebRequest -Uri $u -OutFile "$to.part" -UseBasicParsing -TimeoutSec 60
                    $b = [IO.File]::ReadAllBytes("$to.part") | Select-Object -First 4
                    $hex = ($b | ForEach-Object { $_.ToString('x2') }) -join ''
                    if ($hex -match '^(89504e47|ffd8ff|52494646|47494638)') { Move-Item -LiteralPath "$to.part" -Destination $to; $pics++ }
                    else { Remove-Item -LiteralPath "$to.part"; Write-Host "     (not a picture: $name)" -ForegroundColor DarkYellow }
                } catch { Remove-Item -LiteralPath "$to.part" -ErrorAction SilentlyContinue; Write-Host "     (picture failed: $name - $($_.Exception.Message))" -ForegroundColor DarkYellow }
            }
        }
        Record $m.key $rel
        $owner[$rel] = $m.key
        if ($DELETE_DOWNLOADS) { foreach ($h in $hits) { Remove-Item -LiteralPath $h.File.FullName } }
        $sorted++
    } catch {
        $failed++
        Write-Host "     FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ---------- cults_done.js: tells the browser script which models are done ----------
if (-not $DRY_RUN) {
    $keys = @($ledger.Keys | Sort-Object)
    $js = "// Cults3D - models already sorted by 2_cults_sort_downloads.ps1 ($(Get-Date -Format 'yyyy-MM-dd HH:mm')).`n" +
        "// Paste into the Console on cults3d.com: 1_cults_collect_and_download.js then skips these models.`n" +
        "// Hide unrelated Console `"noise`" (red errors/warnings from the site's own scripts): click the`n" +
        "// gear icon at the top right of the Console, tick `"Hide network`" and `"Selected context only`".`n" +
        "localStorage.setItem('cultsDone', JSON.stringify(" + (ConvertTo-Json -InputObject $keys -Compress) + "));`n" +
        "'$($keys.Count) models marked as done.'`n"
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'cults_done.js'), $js, (New-Object Text.UTF8Encoding $false))
}

$unused = @($downloads | Where-Object { -not $_.Used -and $_.File.Extension -in '.zip', '.stl', '.3mf', '.obj', '.7z', '.rar' })
Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host (" {0}{1}" -f $(if ($DRY_RUN) { 'Would be sorted:        ' } else { 'Sorted now:             ' }), $sorted) -ForegroundColor Green
Write-Host (" Already sorted before:  {0}" -f $sortedBefore)
Write-Host (" Not downloaded yet:     {0}" -f $missing.Count)
if ($failed) { Write-Host (" Failed:                 {0}" -f $failed) -ForegroundColor Red }
if ($pics) { Write-Host (" Pictures:               {0}" -f $pics) }
Write-Host "================================================" -ForegroundColor Yellow
if ($missing.Count) {
    Write-Host "Not in the Downloads folder (yet):" -ForegroundColor Yellow
    $missing | Select-Object -First 25 | ForEach-Object { Write-Host "  $($_.title)" }
    if ($missing.Count -gt 25) { Write-Host "  ... and $($missing.Count - 25) more" }
}
if ($unused.Count) {
    Write-Host "Downloads that match no model in the list (left alone):" -ForegroundColor Yellow
    $unused | Select-Object -First 15 | ForEach-Object { Write-Host "  $($_.File.Name)" }
}
if ($DRY_RUN) { Write-Host "Dry run - nothing was changed. If this looks right, set `$DRY_RUN = `$false and run it again." -ForegroundColor Yellow }
elseif ($sorted) { Write-Host "cults_done.js updated next to this script - paste it into the Console on cults3d.com once." }
