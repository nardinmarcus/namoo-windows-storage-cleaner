# Red Lines — 红线与误区（不可协商）

来源：Microsoft Learn 官方文档 + 多来源社区共识。任何代码或流程变更不得绕过本清单。

## 永远禁止

1. **注册表清理**。Microsoft 官方支持策略明确不支持注册表清理程序；现代 NVMe 机器上无可测收益。本 skill 不含任何注册表写入/清理逻辑（`safety/backup-registry` 类操作也不做）。
2. **手动删除以下目录的任何内容**：
   - `C:\Windows\WinSxS`（只能走 DISM）
   - `C:\Windows\System32`、`C:\Windows\SysWOW64`
   - `C:\Windows\servicing`
   - `C:\Windows\Installer`（无隔离-校验流程不得删，且该流程不在本 skill 范围内）
3. **进入 `System Volume Information` 手删**。卷影副本只能用 `vssadmin`（list shadowstorage / resize / delete shadows）。
4. **删除 `pagefile.sys`**。它是内存管理核心组件，直接删可致 OOM/蓝屏。调整或迁移走系统属性，不在本 skill 范围。
5. **按文件名/子串模式匹配删除**。名字匹配是假设不是身份——先例事故：`*ace*` 模式曾匹配到 4 个无关产品外加一个仅含该字母序列的目录。
6. **Allowlist 之外的任何路径**。`Invoke-Cleanup.ps1` 只接受 ModuleId；路径解析权只在脚本内置 ALLOWLIST。

## 高风险操作的强制确认话术

| 操作 | 必须告知的不可逆后果 |
|---|---|
| `powercfg /h off` | 关闭休眠**和快速启动**；笔记本合盖休眠失效 |
| `vssadmin delete shadows /all` | 删除**全部**系统还原点，之后无法回滚系统 |
| DISM `/ResetBase` | 之后**无法卸载任何已安装更新**；默认不加，用户显式要求才加 |
| `Clear-RecycleBin` | 回收站清空后不可恢复 |
| 浏览器缓存清理 | 提醒先关浏览器；只清 Cache/Code Cache/GPUCache |

## 已知误区（教程圈流传但不要采纳）

- 「清理注册表能提速」——无官方支持，无视。
- 「pagefile 太大就删掉」——正确做法是迁移到非系统盘或由系统管理。
- 「Prefetch 目录要定期清」——收益趋近于零且属争议优化，本 skill 不做（仅报告大小）。
- 「WinSxS 看着很大所以很肥」——硬链接导致资源管理器显示虚高，以 `DISM /AnalyzeComponentStore` 的"实际大小"为准。
- 任何「预计释放 XX GB」的教程数字都未经验证，向用户转述时必须标注"预期"。

## 证据强度标注约定

- 官方命令（DISM/cleanmgr/vssadmin/powercfg/Delete-DeliveryOptimizationCache）：Microsoft Learn 背书，可信。
- 路径类知识（微信/QQ/缓存目录）：多来源一致，操作细节可信度较高，但版本迭代快，执行前脚本实测存在性。
- 收益数字：一律视为自报，仅用于预期管理。
