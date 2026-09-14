# IM App Paths — 微信/QQ/钉钉 路径与风险边界

> 国产 IM 是 C 盘占用大户，也是误删聊天记录的重灾区。本 skill 对 IM 数据的默认策略是 **Tier 3 只报告**。

## 微信 (WeChat / Weixin)

| 路径 | 内容 | 处置 |
|---|---|---|
| `%USERPROFILE%\Documents\WeChat Files` | 旧版聊天记录 + 接收的文件 | **只报告**。含聊天记录，永不动 |
| `%USERPROFILE%\Documents\xwechat_files` | 微信 4.0+ 新数据目录 | **只报告** |
| `%APPDATA%\Tencent\xwechat\radium\...` | 4.0 小程序/WebView 缓存 | 纯缓存子路径，逐路径显式确认后可清 |
| `%APPDATA%\Tencent\WeChat\All Users\...` | 旧版配置残留 | 小体积，报告即可 |

迁移注意（用户问起时告知，不代劳）：设置→文件管理→更改路径**只改新文件位置，不搬旧文件**；需退出微信后整体剪切旧目录。迁移不在本 skill 范围。

## QQ（含 NTQQ 新架构）

| 路径 | 内容 | 处置 |
|---|---|---|
| `%USERPROFILE%\Documents\Tencent Files\<QQ号>` | 旧版聊天记录 + 文件 | **只报告** |
| `%APPDATA%\Tencent\QQ`（NT） | 新版数据 | **只报告**；新版缓存与数据混放，无官方纯缓存路径清单前不自动清 |
| 新旧版本可能并存 | — | 只清一处可能不彻底——报告时提示用户 |

## 钉钉 (DingTalk)

| 路径 | 内容 | 处置 |
|---|---|---|
| `%APPDATA%\DingTalk` | 配置 + 聊天数据 | **只报告** |
| `%APPDATA%\DingTalk\Accounts\<id>\Cache` 类纯缓存子目录 | 缓存 | 逐路径显式确认后可清 |

## 执行规则

1. 扫描阶段：测量以上目录总大小，归入 `im_app_data` Tier 3 报告。
2. 用户明确要清 IM 缓存时：只允许命中本文件列出的**纯缓存子路径**，且必须在对话中逐路径展示并获显式确认（与 Tier 2 同级对待）。
3. 任何含 `msg`、`FileStorage`、`Chat`、用户文件字样的路径一律不进入清理计划。
4. 版本迭代快：脚本执行前必须 `Test-Path` 实测，路径失效就报告"未找到"，不猜测替代路径。
