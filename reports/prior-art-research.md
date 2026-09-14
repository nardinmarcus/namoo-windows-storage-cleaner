# Prior-Art Research — namoo-windows-storage-cleaner

Date: 2026-02-14 · Queries: skills.sh ×9 (disk cleanup / clean system cache / free up disk space / developer cache prune / windows cleanup / windows disk cleaner / C盘清理 / windows temp files / windows optimizer) · SkillsMP ×6 · Web ×3

## 检索来源结论

| 来源 | 结论 |
|---|---|
| skills.sh | 高命中，~60 候选 |
| SkillsMP | low-yield（多为 openclaw/基础设施类），记 missing evidence |
| Web（教程面） | 官方工具链 + 社区红线共识已沉淀进 references/ |

## 深查过的候选与借鉴

| 候选 | 借鉴 (adapt) | 来源可信度 |
|---|---|---|
| richer-richard/clean-my-disk | Tier 0-3 风险分级、allowlist-only、never delete on name match、measure→plan→clean→report 契约 | 源码深查 |
| niuhai/skill-c-cleaner | scanner/cleaner 分离、IM/AI 工具缓存模块意识、admin-aware | 源码深查 |
| orzcls/win-disk-cleaner | DryRun 默认、-Skip 选择性跳过、微信/QQ/WinSxS/hiberfil 模块划分 | 源码深查 |
| crrristang726/windows-c-drive-cleanup-skill | never-touch 清单（WinSxS/System32/servicing/Installer）、隔离优于删除 | 源码深查 |
| codealive-ai/...@maintaining-windows-health | scan→JSON→用户勾选→只删勾选项交互契约 | 源码深查（skills.sh 页） |
| open-agent-power/oh-my-disk-cleaner | GBK/编码兼容（ASCII-safe 输出）、进程感知安全思想 | 源码深查 |
| KyleNesium/upkeep | OS 探测路由（本 skill v1 单平台，模式留作 v2 参考） | 源码深查 |

## Reject

- AvdLee/xcode-disk-cleanup-agent-skill（Xcode 专项）
- Tier C 中文 C 盘 skill（yyl-disk-cleaner-cat 360 / geek-skills-c-drive-cleaner 65 / spellbook@disk-cleaner 116 / storage-analyzer 1.5K 等）——未深查（missing evidence），且从可见信息判断工程深度低于 Tier A/B
- SkillsMP 全部结果

## Invent（本 skill 原创组合）

1. **计划传 ModuleId、路径只由脚本内置 ALLOWLIST 解析**——比 clean-my-disk 的 allowlist 更强：agent 永远接触不到可注入的删除路径
2. Tier 2 双保险：`-IncludeTier2` 开关 + 管理员检测 + 对话逐项确认，三层缺一不可
3. COMMAND_WHITELIST 固定命令串，`Invoke-Expression` 输入面为零
4. PS 5.1 原生 + 全 ASCII 脚本输出，直接适配中文 Windows GBK 控制台

## Missing Evidence（如实记录）

- 各候选安全声明均为自我报告，无独立红队验证
- 教程"预期释放 XX GB"数字未验证，报告中已标注
- Tier C 候选与 mole-mac-cleaner（1.4K）未深查
- 触发评测为 lexical smoke，非 provider-backed 路由证据
