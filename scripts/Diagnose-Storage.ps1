# namoo-windows-storage-cleaner - Diagnose-Storage.ps1
# Deep per-category diagnosis (read-only): reconstructs Windows Settings > Storage buckets
# (Apps / Temporary files / Other / Other users) and outputs JSON for agent-side report building.
# Elevated run recommended: hidden zones (SoftwareDistribution, Windows\Temp, Delivery
# Optimization, Prefetch) are ACL-blocked without admin and will read as 0/null.
# ASCII-only console output (GBK-safe). PS 5.1+ compatible.
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path $env:TEMP "namoo-windows-storage-cleaner")
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
function DirBytes([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
    if ($null -eq $s) { $s = 0 }
    return [int64]$s
}
function TopChildren([string]$dir, [int]$n) {
    $out = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    $kids = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    foreach ($k in $kids) {
        if ($k.PSIsContainer) {
            $s = (Get-ChildItem -LiteralPath $k.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
        } else { $s = $k.Length }
        if ($null -eq $s) { $s = 0 }
        $out += [pscustomobject]@{ name = $k.Name; bytes = [int64]$s }
    }
    return ($out | Sort-Object bytes -Descending | Select-Object -First $n)
}
function FileBytes([string]$p) {
    $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($i) { return [int64]$i.Length }
    return $null
}

$isAdmin = Test-IsAdmin
Write-Host ('Admin: ' + $isAdmin)

# --- drive ---
$ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$drive = @{ free = [int64]$ld.FreeSpace; total = [int64]$ld.Size; used = ([int64]$ld.Size - [int64]$ld.FreeSpace) }
Write-Host ('C: used ' + (Format-Bytes $drive.used) + ' / ' + (Format-Bytes $drive.total) + ', free ' + (Format-Bytes $drive.free))

# --- system managed files ---
$sysfiles = [ordered]@{}
$sysfiles['hiberfil.sys']  = FileBytes 'C:\hiberfil.sys'
$sysfiles['pagefile.sys']  = FileBytes 'C:\pagefile.sys'
$sysfiles['swapfile.sys']  = FileBytes 'C:\swapfile.sys'
foreach ($k in @($sysfiles.Keys)) { Write-Host ($k + ' = ' + (Format-Bytes $sysfiles[$k])) }

$windowsOld = $null
if (Test-Path -LiteralPath 'C:\Windows.old') { $windowsOld = DirBytes 'C:\Windows.old' }
Write-Host ('Windows.old = ' + (Format-Bytes $windowsOld))

# --- temporary-files bucket pieces ---
$tempUserTotal = DirBytes $env:TEMP
$tempUserTop = TopChildren $env:TEMP 12
Write-Host ('user temp total ' + (Format-Bytes $tempUserTotal))

$tempWinTotal = DirBytes "$env:WINDIR\Temp"
$tempWinTop = TopChildren "$env:WINDIR\Temp" 10
Write-Host ('windows temp total ' + (Format-Bytes $tempWinTotal))

$wuPath = "$env:WINDIR\SoftwareDistribution\Download"
$wuBytes = DirBytes $wuPath
Write-Host ('wu download cache (visible) ' + (Format-Bytes $wuBytes))

$doPath = "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
$doBytes = DirBytes $doPath
Write-Host ('delivery optimization (visible) ' + (Format-Bytes $doBytes))

$rb = 0
try {
    $shell = New-Object -ComObject Shell.Application
    foreach ($i in $shell.NameSpace(0xA).Items()) { $rb += $i.Size }
} catch { }
Write-Host ('recycle bin ' + (Format-Bytes $rb))

$thumb = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
$inet  = DirBytes "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
$prefetch = DirBytes "$env:WINDIR\Prefetch"
$d3d = DirBytes "$env:LOCALAPPDATA\D3DSCache"
$wer = 0
foreach ($p in @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue","$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",'C:\ProgramData\Microsoft\Windows\WER')) { $b = DirBytes $p; if ($b) { $wer += $b } }
$crash = DirBytes "$env:LOCALAPPDATA\CrashDumps"
$memdump = (Get-ChildItem "$env:WINDIR\MEMORY.DMP","$env:WINDIR\Minidump\*" -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
Write-Host ('thumb ' + (Format-Bytes $thumb) + ' | inet ' + (Format-Bytes $inet) + ' | prefetch ' + (Format-Bytes $prefetch) + ' | d3d ' + (Format-Bytes $d3d) + ' | wer ' + (Format-Bytes $wer) + ' | crash ' + (Format-Bytes $crash) + ' | memdump ' + (Format-Bytes $memdump))

# --- installed apps (registry EstimatedSize; UWP/system components not covered) ---
$appProps = @()
$regPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
foreach ($rp in $regPaths) {
    $appProps += Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent }
}
$apps = @($appProps | Where-Object { $_.EstimatedSize } | ForEach-Object {
    [pscustomobject]@{ name = $_.DisplayName; bytes = [int64]$_.EstimatedSize * 1KB }
} | Sort-Object bytes -Descending)
$appsSum = ($apps | Measure-Object -Sum bytes).Sum
Write-Host ('registry apps counted: ' + $apps.Count + ', sum ' + (Format-Bytes $appsSum))

# --- other user profiles (junctions All Users / Default User report near-zero) ---
$otherUsers = @()
Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $env:USERNAME } | ForEach-Object {
    $total = DirBytes $_.FullName
    $top = TopChildren $_.FullName 6
    $script:otherUsers += [pscustomobject]@{ profile = $_.Name; bytes = $total; top = $top }
    Write-Host ('USER ' + $_.Name.PadRight(16) + (Format-Bytes $total))
}

# --- program data ---
$pdTotal = DirBytes 'C:\ProgramData'
$pdTop = TopChildren 'C:\ProgramData' 12
Write-Host ('ProgramData total ' + (Format-Bytes $pdTotal))

# --- C root strays (standard system dirs excluded) ---
$cRoot = @()
Get-ChildItem 'C:\' -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('Windows','Program Files','Program Files (x86)','Users','ProgramData','$Recycle.Bin','System Volume Information','Documents and Settings','PerfLogs') } | ForEach-Object {
    if ($_.PSIsContainer) {
        $s = DirBytes $_.FullName
        $cRoot += [pscustomobject]@{ name = $_.Name; bytes = $s; isDir = $true }
    } else {
        $cRoot += [pscustomobject]@{ name = $_.Name; bytes = [int64]$_.Length; isDir = $false }
    }
}
$cRoot = @($cRoot | Sort-Object { if ($null -eq $_.bytes) { -1 } else { $_.bytes } } -Descending)
foreach ($c in $cRoot | Select-Object -First 15) { Write-Host ('ROOT ' + (Format-Bytes $c.bytes).PadRight(12) + $c.name) }

# --- json out (report composition is the agent's job; see references/playbook.md) ---
$out = [pscustomobject]@{
    admin = $isAdmin
    drive = $drive
    sysfiles = $sysfiles
    windowsOld = $windowsOld
    tempUser = @{ total = $tempUserTotal; top = $tempUserTop }
    tempWindows = @{ total = $tempWinTotal; top = $tempWinTop }
    wuCache = @{ path = $wuPath; bytes = $wuBytes }
    doCache = @{ path = $doPath; bytes = $doBytes }
    recycleBin = $rb
    thumbnails = $thumb
    inetCache = $inet
    prefetch = $prefetch
    d3dscache = $d3d
    wer = $wer
    crashDumps = $crash
    memDumps = $memdump
    appsTop = ($apps | Select-Object -First 25)
    appsSum = $appsSum
    appsCount = $apps.Count
    otherUsers = $otherUsers
    programData = @{ total = $pdTotal; top = $pdTop }
    cRoot = ($cRoot | Select-Object -First 20)
}
if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $OutputDir "diag-results-$stamp.json"
$out | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $jsonPath -Encoding utf8
Write-Host ('JSON: ' + $jsonPath)
Write-Host 'DONE (read-only, nothing was deleted)'
