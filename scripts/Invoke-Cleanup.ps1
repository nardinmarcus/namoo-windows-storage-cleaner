# namoo-windows-storage-cleaner - Invoke-Cleanup.ps1
# Plan-driven cleanup. DRY-RUN BY DEFAULT: pass -Execute to actually delete.
# Safety contract:
#   - Module IDs only. Deletion targets resolve EXCLUSIVELY from the built-in ALLOWLIST below.
#   - Never accepts arbitrary paths from outside this script.
#   - Tier 2 modules require -IncludeTier2 AND elevation AND prior explicit user confirmation in conversation.
# ASCII-only console output (GBK-safe). PS 5.1+ compatible.
[CmdletBinding()]
param(
    [string]$ModuleIds = '',
    [switch]$IncludeTier2,
    [switch]$Execute,
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
function Get-LiteralDirBytes([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
    if ($null -eq $s) { $s = 0 }
    return [int64]$s
}
function Remove-ChildrenKeepRoot([string]$dir) {
    $errors = 0; $removed = 0
    if (-not (Test-Path -LiteralPath $dir)) { return @{ Err = 0; Removed = 0 } }
    $children = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    foreach ($c in $children) {
        Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $c.FullName) { $errors++ } else { $removed++ }
    }
    return @{ Err = $errors; Removed = $removed }
}
function Remove-GlobChildren([string[]]$globs) {
    $errors = 0; $removed = 0
    foreach ($g in $globs) {
        $dirs = @(Get-Item -Path $g -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer })
        foreach ($d in $dirs) {
            $r = Remove-ChildrenKeepRoot $d.FullName
            $errors += $r.Err; $removed += $r.Removed
        }
    }
    return @{ Err = $errors; Removed = $removed }
}
function Remove-GlobFiles([string[]]$globs) {
    $errors = 0; $removed = 0
    foreach ($g in $globs) {
        $files = @(Get-Item -Path $g -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
        foreach ($f in $files) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $f.FullName) { $errors++ } else { $removed++ }
        }
    }
    return @{ Err = $errors; Removed = $removed }
}

# ---- ALLOWLIST: the ONLY place deletion targets come from ----
# kind: contents | globcontents | globfiles | recyclebin | command | wucache
$ALLOWLIST = @{
    'user_temp'             = @{ Tier = 0; Kind = 'contents';      Paths = @($env:TEMP) }
    'windows_temp'          = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:WINDIR\Temp") }
    'd3dscache'             = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\D3DSCache") }
    'nvidia_shader_cache'   = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\NVIDIA\GLCache","$env:LOCALAPPDATA\NVIDIA\DXCache") }
    'amd_shader_cache'      = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\AMD\DxCache","$env:LOCALAPPDATA\AMD\Dx9Cache") }
    'wer_reports'           = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue","$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive","C:\ProgramData\Microsoft\Windows\WER") }
    'crash_dumps'           = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\CrashDumps") }
    'vscode_cache'          = @{ Tier = 0; Kind = 'contents';      Paths = @("$env:APPDATA\Code\Cache","$env:APPDATA\Code\CachedData","$env:APPDATA\Code\Code Cache","$env:APPDATA\Code\GPUCache") }
    'jetbrains_cache'       = @{ Tier = 0; Kind = 'globcontents';  Paths = @("$env:LOCALAPPDATA\JetBrains\*\caches\*") }
    'pip_cache'             = @{ Tier = 1; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\pip\cache") }
    'npm_cache'             = @{ Tier = 1; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\npm-cache") }
    'yarn_cache'            = @{ Tier = 1; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\Yarn\Cache") }
    'uv_cache'              = @{ Tier = 1; Kind = 'contents';      Paths = @("$env:LOCALAPPDATA\uv\cache") }
    'browser_cache'         = @{ Tier = 1; Kind = 'globcontents';  Paths = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache\*",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache\*",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache\*",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache\*",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache\*",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache\*",
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2\*") }
    'recycle_bin'           = @{ Tier = 1; Kind = 'recyclebin';    Paths = @() }
    'software_distribution' = @{ Tier = 2; Kind = 'wucache';       Paths = @(); Admin = $true }
    'delivery_optimization' = @{ Tier = 2; Kind = 'command';       Paths = @(); Admin = $true; Command = 'Delete-DeliveryOptimizationCache -Force' }
    'memory_dumps'          = @{ Tier = 2; Kind = 'globfiles';     Paths = @("$env:WINDIR\MEMORY.DMP","$env:WINDIR\Minidump\*"); Admin = $true }
    'live_kernel_reports'   = @{ Tier = 2; Kind = 'contents';      Paths = @("$env:WINDIR\LiveKernelReports"); Admin = $true }
    'nuget_global_packages' = @{ Tier = 2; Kind = 'contents';      Paths = @("$env:USERPROFILE\.nuget\packages") }
    'gradle_caches'         = @{ Tier = 2; Kind = 'contents';      Paths = @("$env:USERPROFILE\.gradle\caches","$env:USERPROFILE\.gradle\wrapper\dists") }
    'hibernation_file'      = @{ Tier = 2; Kind = 'command';       Paths = @(); Admin = $true; Command = 'powercfg /h off' }
    'vss_shadow_copies'     = @{ Tier = 2; Kind = 'command';       Paths = @(); Admin = $true; Command = 'vssadmin delete shadows /all /quiet' }
}
$COMMAND_WHITELIST = @('Delete-DeliveryOptimizationCache -Force', 'powercfg /h off', 'vssadmin delete shadows /all /quiet')

$script:isAdmin = Test-IsAdmin

if ($ModuleIds -eq '' -and -not $Execute) {
    Write-Host 'ALLOWLIST modules:'
    foreach ($k in ($ALLOWLIST.Keys | Sort-Object)) {
        Write-Host ('  [T' + $ALLOWLIST[$k].Tier + '] ' + $k.PadRight(24) + $(if ($ALLOWLIST[$k].Admin) { 'admin' } else { '' }))
    }
    Write-Host ''
    Write-Host 'Usage: -ModuleIds id1,id2 [-IncludeTier2] [-Execute]'
    Write-Host 'Default is DRY-RUN. -Execute performs deletion.'
    return
}

$ids = @($ModuleIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$plan = New-Object System.Collections.Generic.List[hashtable]
$rejected = New-Object System.Collections.Generic.List[string]
foreach ($id in $ids) {
    if (-not $ALLOWLIST.ContainsKey($id)) { $rejected.Add($id); continue }
    $m = $ALLOWLIST[$id]
    if ($m.Tier -eq 2 -and -not $IncludeTier2) {
        Write-Host ('SKIP (Tier2 needs -IncludeTier2 + explicit user confirmation): ' + $id)
        continue
    }
    if ($m.Admin -and -not $script:isAdmin) {
        Write-Host ('SKIP (requires admin elevation): ' + $id)
        continue
    }
    if ($m.Kind -eq 'command' -and $COMMAND_WHITELIST -notcontains $m.Command) {
        # defense in depth: command must be in whitelist regardless of allowlist drift
        Write-Host ('REJECT (command not whitelisted): ' + $id)
        continue
    }
    $plan.Add(@{ Id = $id; Spec = $m })
}
if ($rejected.Count -gt 0) {
    Write-Host ('REJECTED unknown module ids (not in ALLOWLIST): ' + ($rejected -join ', '))
}
if ($plan.Count -eq 0) { Write-Host 'Nothing to do.'; return }

$drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$freeBefore = [int64]$drive.Free

$mode = 'DRY-RUN'
if ($Execute) { $mode = 'EXECUTE' }
Write-Host ('== namoo-windows-storage-cleaner : CLEANUP (' + $mode + ') ==')
Write-Host ('Admin    : ' + $script:isAdmin)
Write-Host ('C: free  : ' + (Format-Bytes $freeBefore))
Write-Host ''

$results = New-Object System.Collections.Generic.List[object]
foreach ($entry in $plan) {
    $id = $entry.Id; $m = $entry.Spec
    $before = 0; $found = $false
    foreach ($p in $m.Paths) {
        if ($m.Kind -in @('contents')) {
            $b = Get-LiteralDirBytes $p; if ($null -ne $b) { $found = $true; $before += $b }
        } elseif ($m.Kind -in @('globcontents','globfiles')) {
            $items = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue)
            foreach ($i in $items) {
                $found = $true
                if ($i.PSIsContainer) {
                    $s = (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
                } else { $s = $i.Length }
                if ($s) { $before += [int64]$s }
            }
        }
    }
    if ($m.Kind -eq 'recyclebin') {
        try {
            $shell = New-Object -ComObject Shell.Application
            foreach ($i in $shell.NameSpace(0xA).Items()) { $before += $i.Size }
            $found = $true
        } catch { }
    }

    $status = 'PLANNED'; $freed = 0; $errCount = 0; $detail = ''

    if (-not $Execute) {
        $status = 'DRYRUN'
    } else {
        switch ($m.Kind) {
            'contents' {
                $tot = @{ Err = 0; Removed = 0 }
                foreach ($p in $m.Paths) { $r = Remove-ChildrenKeepRoot $p; $tot.Err += $r.Err; $tot.Removed += $r.Removed }
                $errCount = $tot.Err
                $detail = ('items removed: ' + $tot.Removed)
            }
            'globcontents' {
                $r = Remove-GlobChildren $m.Paths
                $errCount = $r.Err; $detail = ('items removed: ' + $r.Removed)
            }
            'globfiles' {
                $r = Remove-GlobFiles $m.Paths
                $errCount = $r.Err; $detail = ('files removed: ' + $r.Removed)
            }
            'recyclebin' {
                Clear-RecycleBin -Force -ErrorAction SilentlyContinue
                $detail = 'recycle bin cleared'
            }
            'command' {
                Invoke-Expression $m.Command | Out-Null
                $detail = ('ran: ' + $m.Command)
            }
            'wucache' {
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Stop-Service bits -Force -ErrorAction SilentlyContinue
                $r = Remove-ChildrenKeepRoot "$env:WINDIR\SoftwareDistribution\Download"
                Start-Service wuauserv -ErrorAction SilentlyContinue
                Start-Service bits -ErrorAction SilentlyContinue
                $errCount = $r.Err; $detail = ('wucache items removed: ' + $r.Removed + '; services restarted')
            }
        }
        # re-measure
        $after = 0
        if ($m.Kind -eq 'recyclebin') {
            try {
                $shell = New-Object -ComObject Shell.Application
                foreach ($i in $shell.NameSpace(0xA).Items()) { $after += $i.Size }
            } catch { }
        } else {
            foreach ($p in $m.Paths) {
                if ($m.Kind -eq 'contents') {
                    $b = Get-LiteralDirBytes $p; if ($null -ne $b) { $after += $b }
                } elseif ($m.Kind -in @('globcontents','globfiles')) {
                    $items = @(Get-Item -Path $p -Force -ErrorAction SilentlyContinue)
                    foreach ($i in $items) {
                        if ($i.PSIsContainer) {
                            $s = (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
                        } else { $s = $i.Length }
                        if ($s) { $after += [int64]$s }
                    }
                }
            }
        }
        $freed = $before - $after
        if ($freed -lt 0) { $freed = 0 }
        $status = 'DONE'
        if ($errCount -gt 0) { $status = 'PARTIAL (locked files skipped)' }
    }

    $results.Add([pscustomobject]@{ id = $id; tier = $m.Tier; beforeBytes = $before; freedBytes = $freed; status = $status; detail = $detail })
    Write-Host ('[T' + $m.Tier + '] ' + $id.PadRight(24) + ('before ' + (Format-Bytes $before)).PadRight(18) + ('freed ' + (Format-Bytes $freed)).PadRight(18) + $status)
    if ($detail) { Write-Host ('     ' + $detail) }
}

$drive2 = Get-PSDrive -Name C -ErrorAction SilentlyContinue
$freeAfter = [int64]$drive2.Free
$totalFreed = $freeAfter - $freeBefore
if ($totalFreed -lt 0) { $totalFreed = 0 }

Write-Host ''
Write-Host ('Free space : ' + (Format-Bytes $freeBefore) + '  ->  ' + (Format-Bytes $freeAfter))
Write-Host ('Net gained : ' + (Format-Bytes $totalFreed))

if (-not (Test-Path -LiteralPath $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$mdPath = Join-Path $OutputDir "cleanup-report-$stamp.md"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# Windows Cleanup Report (' + $mode + ')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$sb.AppendLine('- Admin: ' + $script:isAdmin)
[void]$sb.AppendLine('- Free space: ' + (Format-Bytes $freeBefore) + ' -> ' + (Format-Bytes $freeAfter) + ' (net ' + (Format-Bytes $totalFreed) + ')')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Tier | Module | Before | Freed | Status | Detail |')
[void]$sb.AppendLine('|---|---|---|---|---|---|')
foreach ($r in $results) {
    [void]$sb.AppendLine('| ' + $r.tier + ' | `' + $r.id + '` | ' + (Format-Bytes $r.beforeBytes) + ' | ' + (Format-Bytes $r.freedBytes) + ' | ' + $r.status + ' | ' + $r.detail + ' |')
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('> Locked files are skipped and counted in PARTIAL status. Nothing outside the built-in allowlist was touched.')
$sb.ToString() | Out-File -LiteralPath $mdPath -Encoding utf8
Write-Host ('Report: ' + $mdPath)
