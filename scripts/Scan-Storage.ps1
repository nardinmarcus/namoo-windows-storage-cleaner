# namoo-windows-storage-cleaner - Scan-Storage.ps1
# Read-only scan. No deletion. ASCII-only console output (GBK-safe).
# PS 5.1+ compatible.
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path $env:TEMP "namoo-windows-storage-cleaner"),
    [switch]$Deep
)
$ErrorActionPreference = 'SilentlyContinue'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Format-Bytes([double]$b) {
    if ($null -eq $b -or $b -lt 0) { return 'N/A' }
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    return ('{0:N0} KB' -f ($b / 1KB))
}
function Get-LiteralDirBytes([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
    if ($null -eq $s) { $s = 0 }
    return [int64]$s
}
function Get-GlobBytes([string[]]$globs) {
    $total = 0; $found = $false
    foreach ($g in $globs) {
        $items = Get-Item -Path $g -Force -ErrorAction SilentlyContinue
        foreach ($i in $items) {
            if ($null -eq $i) { continue }
            $found = $true
            if ($i.PSIsContainer) {
                $s = (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
            } else { $s = $i.Length }
            if ($s) { $total += [int64]$s }
        }
    }
    if (-not $found) { return $null }
    return [int64]$total
}
function Get-RecycleBinBytes {
    try {
        $shell = New-Object -ComObject Shell.Application
        $items = $shell.NameSpace(0xA).Items()
        $total = 0
        foreach ($i in $items) { $total += $i.Size }
        return [int64]$total
    } catch { return $null }
}

$script:isAdmin = Test-IsAdmin
$script:outLines = New-Object System.Collections.Generic.List[string]

# ---- module table: Id / Tier / AdminRequired / Kind / Paths(globs or literals) ----
$modules = @(
    @{ Id='user_temp';            Tier=0; Admin=$false; Kind='dirs';  Paths=@($env:TEMP) },
    @{ Id='windows_temp';         Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:WINDIR\Temp") },
    @{ Id='d3dscache';            Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\D3DSCache") },
    @{ Id='nvidia_shader_cache';  Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\NVIDIA\GLCache","$env:LOCALAPPDATA\NVIDIA\DXCache") },
    @{ Id='amd_shader_cache';     Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\AMD\DxCache","$env:LOCALAPPDATA\AMD\Dx9Cache") },
    @{ Id='wer_reports';          Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue","$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive","C:\ProgramData\Microsoft\Windows\WER") },
    @{ Id='crash_dumps';          Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\CrashDumps") },
    @{ Id='recycle_bin';          Tier=1; Admin=$false; Kind='recyclebin'; Paths=@() },
    @{ Id='vscode_cache';         Tier=0; Admin=$false; Kind='dirs';  Paths=@("$env:APPDATA\Code\Cache","$env:APPDATA\Code\CachedData","$env:APPDATA\Code\Code Cache","$env:APPDATA\Code\GPUCache") },
    @{ Id='jetbrains_cache';      Tier=0; Admin=$false; Kind='globs'; Paths=@("$env:LOCALAPPDATA\JetBrains\*\caches") },
    @{ Id='pip_cache';            Tier=1; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\pip\cache") },
    @{ Id='npm_cache';            Tier=1; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\npm-cache") },
    @{ Id='yarn_cache';           Tier=1; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\Yarn\Cache") },
    @{ Id='uv_cache';             Tier=1; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\uv\cache") },
    @{ Id='browser_cache';        Tier=1; Admin=$false; Kind='globs'; Paths=@(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2") },
    @{ Id='software_distribution';Tier=2; Admin=$true;  Kind='dirs';  Paths=@("$env:WINDIR\SoftwareDistribution\Download") },
    @{ Id='delivery_optimization';Tier=2; Admin=$true;  Kind='dirs';  Paths=@("$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache") },
    @{ Id='memory_dumps';         Tier=2; Admin=$true;  Kind='globs'; Paths=@("$env:WINDIR\MEMORY.DMP","$env:WINDIR\Minidump\*") },
    @{ Id='live_kernel_reports';  Tier=2; Admin=$true;  Kind='dirs';  Paths=@("$env:WINDIR\LiveKernelReports") },
    @{ Id='nuget_global_packages';Tier=2; Admin=$false; Kind='dirs';  Paths=@("$env:USERPROFILE\.nuget\packages") },
    @{ Id='gradle_caches';        Tier=2; Admin=$false; Kind='dirs';  Paths=@("$env:USERPROFILE\.gradle\caches","$env:USERPROFILE\.gradle\wrapper\dists") },
    @{ Id='im_app_data';          Tier=3; Admin=$false; Kind='dirs';  Paths=@(
        "$env:USERPROFILE\Documents\WeChat Files",
        "$env:USERPROFILE\Documents\xwechat_files",
        "$env:USERPROFILE\Documents\Tencent Files",
        "$env:APPDATA\Tencent",
        "$env:APPDATA\DingTalk") },
    @{ Id='wsl_docker_vhdx';      Tier=3; Admin=$false; Kind='globs'; Paths=@(
        "$env:LOCALAPPDATA\Docker\wsl\*\ext4.vhdx",
        "$env:LOCALAPPDATA\Packages\*\LocalState\ext4.vhdx") },
    @{ Id='pnpm_store';           Tier=3; Admin=$false; Kind='dirs';  Paths=@("$env:LOCALAPPDATA\pnpm\store") },
    @{ Id='onedrive_cache';       Tier=3; Admin=$false; Kind='dirs';  Paths=@("$env:USERPROFILE\OneDrive") },
    @{ Id='windows_installer';    Tier=3; Admin=$false; Kind='dirs';  Paths=@("C:\Windows\Installer") },
    @{ Id='downloads_large';      Tier=3; Admin=$false; Kind='special'; Paths=@() },
    @{ Id='large_files';          Tier=3; Admin=$false; Kind='special'; Paths=@() }
)

function Scan-Module([hashtable]$m) {
    $res = [ordered]@{ id=$m.Id; tier=$m.Tier; adminRequired=[bool]$m.Admin; bytes=$null; status='FOUND'; detail='' }
    $r = $null
    switch ($m.Kind) {
        'dirs' {
            $total = 0; $foundAny = $false
            foreach ($p in $m.Paths) {
                $b = Get-LiteralDirBytes $p
                if ($null -ne $b) { $foundAny = $true; $total += $b }
            }
            if ($foundAny) { $r = [int64]$total }
        }
        'globs' { $r = Get-GlobBytes $m.Paths }
        'recyclebin' { $r = Get-RecycleBinBytes }
        'recyclebin' { $r = Get-RecycleBinBytes }
        'special' {
            if ($m.Id -eq 'downloads_large') {
                $res.status = 'REPORT'
                $res.detail = 'see report file: top >100MB files in Downloads'
            } elseif ($m.Id -eq 'large_files') {
                $res.status = 'REPORT'
                $res.detail = 'see report file: top >500MB files under user profile (depth 4)'
            }
        }
    }
    if ($m.Kind -ne 'special' -and $null -eq $r) { $res.status = 'NOT_FOUND' }
    $res.bytes = $r
    return $res
}

Write-Host '== namoo-windows-storage-cleaner : SCAN (read-only) ==' 
Write-Host ('Admin      : ' + $script:isAdmin)
$drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$freeBefore = 0
if ($drive) { $freeBefore = [int64]$drive.Free; Write-Host ('C: free    : ' + (Format-Bytes $freeBefore)) }

$results = New-Object System.Collections.Generic.List[object]
foreach ($m in $modules) {
    $r = Scan-Module $m
    $results.Add([pscustomobject]$r)
    $sizeTxt = Format-Bytes $r.bytes
    Write-Host ('[T' + $r.tier + '] ' + $r.id.PadRight(24) + $sizeTxt.PadRight(12) + $r.status)
}

# ---- Tier 3 special reports ----
$specialNotes = New-Object System.Collections.Generic.List[string]

$hib = Get-Item -LiteralPath 'C:\hiberfil.sys' -Force -ErrorAction SilentlyContinue
if ($hib) { $specialNotes.Add(('hiberfil.sys: ' + (Format-Bytes $hib.Length) + ' (Tier2: powercfg /h off)')) }
$pg = Get-Item -LiteralPath 'C:\pagefile.sys' -Force -ErrorAction SilentlyContinue
if ($pg) { $specialNotes.Add(('pagefile.sys: ' + (Format-Bytes $pg.Length) + ' (NEVER delete; migrate via System Properties)')) }

if (Test-Path -LiteralPath 'C:\Windows.old') {
    $b = Get-LiteralDirBytes 'C:\Windows.old'
    $specialNotes.Add(('Windows.old: ' + (Format-Bytes $b) + ' (remove via Disk Cleanup > Previous Windows installations)'))
}

if ($script:isAdmin) {
    $vss = & vssadmin list shadowstorage 2>$null
    if ($vss) { $specialNotes.Add('vssadmin list shadowstorage:'); $specialNotes += ($vss | Select-Object -First 12) }
} else {
    $specialNotes.Add('vssadmin/system dump inventory: skipped (requires admin)')
}

if ($Deep -and $script:isAdmin) {
    Write-Host 'Running DISM AnalyzeComponentStore (1-2 min)...'
    $dism = & "$env:WINDIR\System32\Dism.exe" /Online /Cleanup-Image /AnalyzeComponentStore 2>$null
    if ($dism) { $specialNotes.Add('DISM AnalyzeComponentStore:'); $specialNotes += ($dism | Where-Object { $_ -match '\S' } | Select-Object -First 15) }
} elseif ($Deep) {
    $specialNotes.Add('DISM analyze skipped: requires admin')
}

if (-not $script:isAdmin) {
    $specialNotes.Add('NOTE: run elevated for windows_temp/memory_dumps/software_distribution full accounting.')
}

# ---- large file reports ----
$dlPath = Join-Path $env:USERPROFILE 'Downloads'
$dlFiles = @(Get-ChildItem -LiteralPath $dlPath -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB } | Sort-Object Length -Descending | Select-Object -First 20)
$bigFiles = @(Get-ChildItem -LiteralPath $env:USERPROFILE -Recurse -Depth 4 -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 500MB } | Sort-Object Length -Descending | Select-Object -First 20)

# ---- outputs ----
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $OutputDir "scan-results-$stamp.json"
$mdPath   = Join-Path $OutputDir "storage-scan-report-$stamp.md"

$results | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $jsonPath -Encoding utf8

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Windows Storage Scan Report')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('- Admin: ' + $script:isAdmin)
[void]$sb.AppendLine('- C: free: ' + (Format-Bytes $freeBefore))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Cleanable modules (Tier 0-2)')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Tier | Module | Size | Status |')
[void]$sb.AppendLine('|---|---|---|---|')
foreach ($r in $results | Where-Object { $_.tier -le 2 }) {
    [void]$sb.AppendLine('| ' + $r.tier + ' | `' + $r.id + '` | ' + (Format-Bytes $r.bytes) + ' | ' + $r.status + ' |')
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Report-only (Tier 3, never auto-deleted)')
[void]$sb.AppendLine('')
foreach ($r in $results | Where-Object { $_.tier -eq 3 }) {
    [void]$sb.AppendLine('- `' + $r.id + '`: ' + (Format-Bytes $r.bytes) + ' (' + $r.status + (($(if ($r.detail) { '; ' + $r.detail } else { '' }))) + ')')
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## System-level notes')
[void]$sb.AppendLine('')
foreach ($n in $specialNotes) { [void]$sb.AppendLine('- ' + $n) }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Large files in Downloads (>100MB, top 20)')
[void]$sb.AppendLine('')
foreach ($f in $dlFiles) { [void]$sb.AppendLine('- ' + (Format-Bytes $f.Length) + '  ' + $f.FullName) }
if ($dlFiles.Count -eq 0) { [void]$sb.AppendLine('- (none)') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Large files under user profile (>500MB, top 20, depth 4)')
[void]$sb.AppendLine('')
foreach ($f in $bigFiles) { [void]$sb.AppendLine('- ' + (Format-Bytes $f.Length) + '  ' + $f.FullName) }
if ($bigFiles.Count -eq 0) { [void]$sb.AppendLine('- (none)') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> All size estimates are approximate. Numbers are self-reported baselines, not guarantees.')
$sb.ToString() | Out-File -LiteralPath $mdPath -Encoding utf8

Write-Host ''
Write-Host ('JSON : ' + $jsonPath)
Write-Host ('MD   : ' + $mdPath)
Write-Host 'DONE (read-only, nothing was deleted)'
