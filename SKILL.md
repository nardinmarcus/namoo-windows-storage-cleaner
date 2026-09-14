---
name: namoo-windows-storage-cleaner
description: "Windows 电脑存储清理：当用户提到 C盘满、磁盘空间不足、清理电脑/垃圾/缓存/临时文件、WinSxS、休眠文件、浏览器缓存、微信/QQ 占用、开发缓存(npm/pip)时触发。Tier 0-3 分级：0/1 确认后清，2 逐项确认，3 只报告。不做重复文件/注册表/迁移，不含 macOS/Linux。"
when_to_use: "清理电脑, C盘清理, 磁盘空间不足, 清理缓存, 清理临时文件, 清理垃圾, 释放空间, free up space, clean my pc, disk cleanup, storage cleaner, WinSxS, 清理微信缓存"
dispatch_intent: "Tiered Windows storage cleanup: scan first, allowlist-only deletion, explicit confirmation for system-level ops."
argument-hint: scan | clean --tier=0,1 [--execute] | clean --module=MODULE_ID [--execute] | report
metadata:
  author: Namoo
  version: "1.2.0"
---

# Namoo Windows Storage Cleaner

## Outcome Contract

- Outcome: 分级扫描报告 + 按批准范围执行的清理 + 前后对比账单（逐模块释放量、跳过项）。
- Exclusions: 重复文件检测、注册表清理、迁移流、macOS/Linux。
- Platform: Windows 10/11，PowerShell 5.1+；非 Windows 直接停止。

## Workflow（详见 references/playbook.md）

1. Preflight：确认 Windows、管理员状态、C 盘空闲基线。
2. 运行 `scripts/Scan-Storage.ps1`（只读）→ 按 Tier 分组呈现计划；无管理员时部分系统区读作 0，提示提权重扫（见 playbook）。
3. Confirm：Tier 0/1 一次确认；Tier 2 逐项确认并明示不可逆后果；Tier 3 永不执行。
4. 先 DryRun，批准后运行 `scripts/Invoke-Cleanup.ps1 -Execute`，输出账单。

## Tier 契约

| Tier | 含义 | 策略 |
|---|---|---|
| 0 | 自动可再生 | 确认一次即清 |
| 1 | 安全但不可逆 | 同上，单独列出 |
| 2 | 系统级/需管理员/重建贵 | 逐项确认，默认跳过 |
| 3 | 只报告 | 永不自动删 |

模块目录：`references/cleanup-catalog.md`（含官方命令与预期收益）。

## Safety Invariants

- **Allowlist-only**：计划只传 ModuleId，删除路径仅由 `Invoke-Cleanup.ps1` 内置 ALLOWLIST 解析；外部路径一律拒绝；永不按文件名匹配删除。
- **红线**（注册表清理/手删 WinSxS、System32、servicing、Installer/手删 System Volume Information/删 pagefile.sys）：全部禁止，见 `references/red-lines.md`。
- **IM 数据（微信/QQ/钉钉）默认只报告**，聊天记录永不触碰；纯缓存子路径逐路径确认，见 `references/im-app-paths.md`。
- **浏览器只清 Cache/Code Cache/GPUCache**，执行前提醒关浏览器。
- 只删内容保留目录根；锁定文件跳过并计数；需管理员的模块未提权时可见跳过。
- **DryRun 默认**，`-Execute` 是唯一删除入口；Tier 2 另需 `-IncludeTier2` + 提权 + 对话确认三层门禁。脚本输出 ASCII-safe，报告 UTF-8。

## Task-End Skill Improvement Review

- During a task, track only explicit corrections the user makes to this Skill's behavior. Do not infer corrections from ordinary tool errors and do not scan earlier transcripts.
- Keep pending items task-local by default. Finish the requested task first unless a safety or permission issue requires an immediate stop.
- Before the final task response, if reusable corrections remain, show a `Skill 改进待审` section with the problem, proposed adjustment, scope, risk, and explicit item IDs. If there are no actionable items, do not add a reminder.
- Silence, deferral, or approval without explicit item IDs grants no change authority.
- After the user approves item IDs, invoke `namoo-skill-creator` as the single writer. It may update this Skill in an isolated candidate, add RED/GREEN regression evidence, and verify only the approved write targets.
- Show the verified diff and evidence before asking for canonical approval. Candidate approval does not authorize merge, publication, catalog adoption, or runtime projection.
