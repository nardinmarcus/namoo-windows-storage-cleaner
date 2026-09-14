# Cleanup Catalog — Windows 清理模块目录

> 所有模块的唯一事实源。`Scan-Storage.ps1` 与 `Invoke-Cleanup.ps1` 的 ALLOWLIST 必须与此表保持一致。
> 修改任何模块的路径/命令前，先过 Task-End Skill Improvement Review 流程。
> 「预期收益」为教程自报数字，未独立验证，仅作预期管理。

## Tier 0 — 自动可再生，零数据丢失

| ModuleId | 路径 | 预期收益 | 说明 |
|---|---|---|---|
| `user_temp` | `%TEMP%` | 1-5 GB | 用户临时文件。锁定文件跳过 |
| `windows_temp` | `C:\Windows\Temp` | 0.5-2 GB | 系统临时文件，部分需管理员 |
| `d3dscache` | `%LOCALAPPDATA%\D3DSCache` | 0.2-2 GB | DirectX 着色器缓存，自动重建 |
| `nvidia_shader_cache` | `%LOCALAPPDATA%\NVIDIA\GLCache`, `%LOCALAPPDATA%\NVIDIA\DXCache` | 0.5-5 GB | 首次游戏加载变慢，可接受 |
| `amd_shader_cache` | `%LOCALAPPDATA%\AMD\DxCache`, `%LOCALAPPDATA%\AMD\Dx9Cache` | 0.2-2 GB | 同上 |
| `wer_reports` | `%LOCALAPPDATA%\Microsoft\Windows\WER\ReportQueue`, `ReportArchive`, `C:\ProgramData\Microsoft\Windows\WER` | 0.1-2 GB | Windows 错误报告队列 |
| `crash_dumps` | `%LOCALAPPDATA%\CrashDumps` | 0-1 GB | 应用崩溃转储 |
| `vscode_cache` | `%APPDATA%\Code\Cache`, `CachedData`, `Code Cache`, `GPUCache` | 0.2-1 GB | 只清缓存子目录，不碰 WorkspaceStorage |
| `jetbrains_cache` | `%LOCALAPPDATA%\JetBrains\<IDE*\caches>`（仅 caches 子目录） | 0.5-5 GB | 索引重建需时间；旧版本残留目录建议在 IDE 内 Delete Leftover 清 |

## Tier 1 — 安全但不可逆

| ModuleId | 路径/命令 | 预期收益 | 说明 |
|---|---|---|---|
| `recycle_bin` | `Clear-RecycleBin`（COM 测量） | 0.5-5 GB | 清空后不可恢复，确认时必须强调 |
| `browser_cache` | Edge/Chrome/Firefox 的 `Cache`, `Code Cache`, `GPUCache` 子目录 | 0.5-3 GB | 执行前提醒关闭浏览器；绝不碰 Profile 其余部分 |
| `pip_cache` | `%LOCALAPPDATA%\pip\cache` | 0.5-3 GB | 重装包时重新下载 |
| `npm_cache` | `%LOCALAPPDATA%\npm-cache` | 0.5-3 GB | 等价 `npm cache clean --force` |
| `yarn_cache` | `%LOCALAPPDATA%\Yarn\Cache` | 0.2-2 GB | |
| `uv_cache` | `%LOCALAPPDATA%\uv\cache` | 1-10 GB | 等价 `uv cache clean`；Python 开发机收益最大 |

## Tier 2 — 系统级 / 需管理员 / 重建代价高（逐项确认）

| ModuleId | 路径/命令 | 预期收益 | 风险与确认话术 |
|---|---|---|---|
| `software_distribution` | `C:\Windows\SoftwareDistribution\Download`（先 stop wuauserv，清后重启服务） | 1-10 GB | 更新缓存，删后下次更新重新下载；需管理员 |
| `delivery_optimization` | `Delete-DeliveryOptimizationCache -Force` | 1-20 GB | 传递优化缓存；旧版本无此 cmdlet 时回退 cleanmgr 指引；需管理员 |
| `dism_component_cleanup` | `Dism.exe /Online /Cleanup-Image /StartComponentCleanup` | 1-5 GB | 耗时 10-30 分钟；**默认不加 `/ResetBase`**（加了将无法卸载已装更新，除非用户显式要求）；系统更新后 30 天内收益有限；需管理员 |
| `hibernation_file` | `powercfg /h off` | ≈物理内存大小 (8-32 GB) | **关闭休眠与快速启动**，笔记本用户需明确同意；重新开启 `/h on` |
| `memory_dumps` | `C:\Windows\MEMORY.DMP`, `C:\Windows\Minidump\*` | 0.2-几 GB | 蓝屏分析材料，删除后无法事后分析；需管理员 |
| `live_kernel_reports` | `C:\Windows\LiveKernelReports` | 0-2 GB | 内核实时报告/崩溃数据，删后无法事后分析；需管理员 |
| `vss_shadow_copies` | `vssadmin delete shadows /all /quiet` | 视配置，可达 10+ GB | **删除全部还原点**，系统出问题无法回滚；先展示 `vssadmin list shadowstorage` 占用再确认；需管理员 |
| `nuget_global_packages` | `%USERPROFILE%\.nuget\packages` | 1-10 GB | .NET 全局包存储，删后 restore 重新下载；.NET 开发机慎选 |
| `gradle_caches` | `%USERPROFILE%\.gradle\caches`, `wrapper\dists` | 1-5 GB | 下次构建全量重新下载；Java/Android 开发机慎选 |

## Tier 3 — 只报告，永不自动删

| ModuleId | 报告内容 | 手工指引 |
|---|---|---|
| `winsxs_analyze` | 组件存储实际大小（需管理员 + `-Deep` 才跑） | `Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore`；切勿手删 WinSxS |
| `system_managed_files` | `hiberfil.sys` / `pagefile.sys` 大小 | pagefile 通过 系统属性→高级→性能设置 迁移，**不删** |
| `windows_installer` | `C:\Windows\Installer` 大小 + 孤儿 MSP 提示 | 孤儿补丁参考隔离-哈希校验-观察 1-2 周流程（见 prior-art 报告），不要直接删 |
| `system_volume_information` | `vssadmin list shadowstorage` 输出（需管理员） | 只用 vssadmin 调整，不进文件夹手删 |
| `windows_old` | `C:\Windows.old` 存在性与大小 | 升级超 10 天后经 磁盘清理→清理系统文件→以前的 Windows 安装 删除 |
| `im_app_data` | 微信/QQ/钉钉数据目录大小 | 见 `im-app-paths.md`；聊天记录与用户文件永不自动删 |
| `wsl_docker_vhdx` | `%LOCALAPPDATA%\Docker\wsl\*\ext4.vhdx`, `%LOCALAPPDATA%\Packages\*Ubuntu*\LocalState\ext4.vhdx` | 容器内 `docker system prune` 后 `wsl --shutdown` + `Optimize-VHD`/diskpart 压缩 |
| `downloads_large` | Downloads 中 >100 MB 文件 Top 20 | 用户自行决定 |
| `large_files` | 用户目录（深度 ≤4）>500 MB 文件 Top 20 | 用户自行决定；只报告路径与大小 |
| `pnpm_store` | `%LOCALAPPDATA%\pnpm\store` | `pnpm store prune` |
| `onedrive_cache` | OneDrive 占用概览 | 通过 OneDrive 设置释放空间（Files On-Demand） |

## 扫描顺序建议

诊断类（找大头）：`system_managed_files` → `winsxs_analyze` → `im_app_data` → `wsl_docker_vhdx` → `large_files`。
常规清理：Tier 0 全部 → Tier 1 按需 → Tier 2 逐项。
