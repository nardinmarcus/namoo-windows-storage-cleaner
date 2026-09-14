# namoo-windows-storage-cleaner

Windows 电脑分级清理 Skill：**先测量、后计划、只删白名单、出账单**。

## 解决什么问题

C 盘满时的空间急救与周期性维护，替代"全网抄命令盲删"：
- 24 个扫描模块按 **Tier 0-3** 分级：Tier 0/1 可再生缓存安全清理，Tier 2 系统级操作逐项确认，Tier 3 只报告永不自动删
- **Allowlist 硬约束**：清理计划只传 ModuleId，删除目标只能由脚本内置白名单解析，任何外部路径一律拒绝
- **DryRun 默认**：`-Execute` 是唯一删除入口
- Windows 原生 PowerShell 5.1+，ASCII-safe 输出（GBK 控制台不乱码）

## Install

```bash
# Option A: skills CLI (public standalone repo)
npx skills add nardinmarcus/namoo-windows-storage-cleaner

# Option B: copy into an agent skills directory (project-level)
cp -r namoo-windows-storage-cleaner <agent>/skills/
```

已就位：`~/.agents/.agents/skills/namoo-windows-storage-cleaner`。

## Verify

```powershell
# read-only scan proves installation; nothing is deleted
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Scan-Storage.ps1
```

## Natural Examples

- 「C盘满了帮我清理一下」
- 「帮我看看 WinSxS 为什么这么大」
- 「清理一下 npm/pip 缓存和临时文件」
- 「微信 QQ 占了多少空间」

## 输出

- `storage-scan-report-*.md`：分级扫描报告（可清模块、系统级注记、大文件 Top 20）
- `cleanup-report-*.md`：清理账单（逐模块 before/freed、跳过与锁定文件、净释放空间）

## 前提与风险

- Windows 10/11，PowerShell 5.1+；Tier 2 模块需要管理员
- Tier 2 的不可逆后果（关闭休眠/快速启动、删除全部还原点、DISM ResetBase）在确认时必须明示
- 微信/QQ/钉钉数据默认只报告，聊天记录永不触碰
- 教程类"预期释放 XX GB"数字均未独立验证，仅作预期管理

## 不做什么

重复文件检测、注册表清理、AppData/junction 迁移、macOS/Linux、按文件名模式批量删除。

## Troubleshooting

- 部分 `.ps1` 被执行策略拦截：用 `powershell -NoProfile -ExecutionPolicy Bypass -File ...`
- 模块显示 NOT_FOUND：路径随版本变化，属正常，不猜测替代路径
- PARTIAL 状态：存在被占用（锁定）文件，已跳过并计数，重跑或重启后再清
