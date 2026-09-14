# Creation Handoff — namoo-windows-storage-cleaner v1.0.0

Date: 2026-02-14 · Mode: Production (personal) · Boundary: Windows-only storage cleanup

## Intent（一句话）

接受 Windows 清理意图（C盘满/空间不足/清缓存），返回分级扫描报告与按批准范围执行的清理账单；不处理重复文件、注册表、迁移流、非 Windows 平台。

## Reference Skills Studied

7 个深查先例（见 `prior-art-research.md`），核心机制来自 clean-my-disk（tier/allowlist/报告契约）、orzcls（DryRun/模块表）、niuhai（scanner 分层/admin-aware）、crrristang（never-touch 清单）、oh-my-disk-cleaner（编码兼容）。

## Candidate-Specific Lessons

1. `.ps1` 以 UTF-8 无 BOM 存盘时，PS 5.1 按 ANSI 读取——**脚本内容必须全 ASCII**，中文只进运行时生成的 UTF-8 报告文件
2. glob（`User Data\*\Cache`）天然覆盖多浏览器 Profile，比枚举 Default 目录更稳
3. `Remove-Item` 锁定文件失败需逐项 try 并计数，输出 PARTIAL 状态而非整体失败
4. 回收站大小用 Shell.Application COM 测量，`Clear-RecycleBin` 清空

## Original Contributions

- ModuleId-only 计划面（agent 无路径注入面）
- COMMAND_WHITELIST + ALLOWLIST 双重校验
- Tier 2 三层门禁（开关 + 提权 + 对话确认）

## Evidence

- `validate_skill.py`：见本次创建输出（通过/失败如实记录）
- `trigger_eval.py`：lexical smoke（非 provider-backed）
- 脚本实测：Scan 在本机 Windows 实跑；Invoke-Cleanup 仅 DryRun 验证（未执行真实删除）

## Missing Evidence

- behavior eval（provider-backed with-skill/baseline）：未做
- 真实清理收益基线：首次实跑后回填
- 隔离-延迟删除流程（Windows Installer 孤儿 MSP）：v1 未纳入，参考 crrristang 模式

## Rejected Alternatives

- Python 跨平台扫描（clean-my-disk/oh-my-disk 方案）：personal 机器已有 PS，避免 Python 依赖
- WSL2 桥（upkeep 方案）：原生 PS 直连，无桥开销

## v1.1.0 (2026-09-14)

- change-001: recycle_bin 扫描行补齐
- change-002: Diagnose-Storage.ps1 固化 + playbook 深度诊断流程
- change-003: 非管理员降级路径 + 提权重扫指引（用户已授权 UAC 流程）

## v1.2.0 (2026-09-14)

- change-004: 新增 Tier 2 模块 live_kernel_reports（catalog + Scan + ALLOWLIST 三处同步），实战来源：本机清理发现 1.2G 内核报告
