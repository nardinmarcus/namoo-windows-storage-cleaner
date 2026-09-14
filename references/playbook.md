# Playbook — 完整工作流与扩展规则

> SKILL.md 只保留骨架；本文件承载执行细节。两处冲突时以 SKILL.md 的 Safety Invariants 为准。

## Workflow 全步骤

### 1. Preflight

- 确认 OS 是 Windows（`uname` 不可用时用 `$env:OS` / `winver` 线索）；非 Windows 停止。
- 检查 PowerShell 可用性与版本（5.1+）。
- 判断当前会话是否管理员（影响哪些 Tier 2 模块可用；提权动作让用户自己做，不代做 UAC）。
- 记录 C 盘空闲基线：`Get-PSDrive C`。

### 2. Scan（只读）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Scan-Storage.ps1 [-OutputDir <dir>] [-Deep]
```

- `-Deep` 追加 DISM `/AnalyzeComponentStore`（需管理员，1-2 分钟）。
- 读取生成的 `storage-scan-report-*.md`，按 Tier 0/1/2/3 分组向用户呈现：模块、大小、风险、是否需管理员。
- Tier 3 报告里的大文件与 IM 占用要点名给用户看（这往往是真正的大头）。

### 3. Confirm

- Tier 0/1：一次列出全部待清项，获得一个"确认清理"即可。
- Tier 2：**逐项确认**，每项必须先说明不可逆后果（话术见 red-lines.md 高风险表）。用户犹豫即跳过。
- Tier 3：永不进入清理计划；只给手工命令与解释。

### 4. Execute

- 先 DryRun（默认）展示将执行的模块与预期释放，再带 `-Execute` 重跑。
- Tier 2 需要 `-IncludeTier2`；脚本会在未提权时跳过对应模块——这是预期行为，不是错误。
- 浏览器缓存清理前提醒关闭浏览器；`browser_cache` 状态为 PARTIAL 时大概率是浏览器未关。

### 5. Verify & Report

- 向用户汇报：净释放空间（脚本输出 `Net gained`）、逐模块 freed、PARTIAL/SKIPPED 原因。
- 深度清理建议（Tier 3 手工项）作为"后续可选"列出，不代执行。

## 扩展规则（新增/修改模块时）

1. 先在 `references/cleanup-catalog.md` 落行（含 tier、官方命令、证据强度标注）。
2. `Scan-Storage.ps1` 的 `$modules` 与 `Invoke-Cleanup.ps1` 的 `$ALLOWLIST` **必须同步**改，且只允许目录/路径/固定命令，不允许新增可注入参数。
3. 新命令型模块（Kind='command'）必须同时把确切命令串加进 `$COMMAND_WHITELIST`。
4. 涉及聊天记录、用户文档、凭据的路径永远只能进 Tier 3。
5. 修改走 Task-End Skill Improvement Review 流程，不接受直接热改。

## Deep Diagnosis & Report（设置页分类拆解）

当用户拿着 设置→存储 的分类数字（应用和功能/临时文件/其他/其他用户）问"里面具体是什么"时：

1. 运行 `scripts/Diagnose-Storage.ps1`（只读，建议提权；无提权时隐藏区读作 0/null）。
2. 读取输出的 `diag-results-*.json`，按四大分类做对账：可见部分逐项列出，缺口明确标注去向（管理员隐藏区 / UWP 未注册程序 / junction 重复计数）。
3. 生成中文诊断报告（Markdown，UTF-8）存到用户桌面：分类拆解表 + 安全分级（✅立即可清 / ⚠️提权确认 / 👤用户决策 / 🚫红线）+ 预期收益。报告生成由 agent 完成，脚本不写中文（ASCII-only 约束）。
4. 无管理员时的降级路径：明确告知缺口大小，用 `Start-Process powershell -Verb RunAs -Wait` 发起提权重跑（用户点 UAC），脚本落盘 JSON 后回读，把隐藏区数字补进报告 v2。
5. 对账时注意：`All Users`/`Default User` 是 junction（重复计数，忽略）；Default 是新用户模板（🚫 不动）；公司安全软件目录（DLP/杀查/VPN 代理类）一律 🚫。

## 已知限制（v1）

- `large_files` 扫描限用户目录深度 4，C 盘全盘大文件扫描未做（慢）。
- WinSxS 实际大小依赖 `-Deep` + 管理员；资源管理器显示值因硬链接虚高。
- 微信 4.0 缓存子路径随版本变动，执行前以 `Test-Path` 实测为准。
- 不处理 Windows Installer 孤儿 MSP 的隔离-延迟删除（后续版本可参考隔离-哈希校验-观察 1-2 周模式）。
