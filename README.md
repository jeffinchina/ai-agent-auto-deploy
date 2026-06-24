# AI Agent Auto Deploy

面向普通 Windows 用户的一键 AI Agent 部署脚本。当前稳定版本聚焦 Claude Code + DeepSeek 直连，同时安装 CcSwitch，便于用户后续在可视化界面管理更多模型供应商。

## 当前版本

- 版本：`v3.2.2`
- 系统：Windows 10/11 x64
- 主链路：Claude Code -> DeepSeek Anthropic-compatible endpoint
- 附加工具：CcSwitch provider manager
- 运行依赖：Node.js + Claude Code + PortableGit

## 用户流程

1. 将发布包文件夹复制到目标电脑。
2. 双击 `一键部署.cmd`。
3. 根据提示输入 DeepSeek API Key。
4. 安装完成后，重新打开 PowerShell 或 CMD。
5. 输入 `claude` 开始对话。

## v3.2.2 关键修复

Claude Code on Windows requires Git Bash or PowerShell 7. 普通 Windows 通常只有 Windows PowerShell 5.1，不满足 Claude Code 运行要求。`v3.2.2` 已内置 PortableGit 自动安装和 `CLAUDE_CODE_GIT_BASH_PATH` 配置。

## 仓库与发布包

Git 仓库只保存源码、配置、文档和资源清单。完整离线安装包作为 GitHub Release 附件发布，不直接提交到 git 历史中。

当前发布包：

- `把这个文件夹拷到待安装的电脑_V3.2.2.zip`
- SHA256: `77B863C6431E7DBDB8AD9DA95D9E2D083F642DC3EC4199914F41190034D81277`

## 项目结构

```text
ai-agent-auto-deploy/
  deploy.ps1                 # Windows 主部署脚本
  一键部署.cmd                # 用户双击入口
  使用说明.txt                # 用户说明
  config/
    deepseek-preset.json
  assets/
    manifest.json            # 离线资源清单与校验值
  CHANGELOG.md
  README.md
```

## 当前部署阶段

1. 环境检测
2. 安装 Node.js
3. 安装 Claude Code
4. 安装 Claude Code 运行环境（PortableGit / Git Bash）
5. 配置 DeepSeek API Key
6. PATH 持久化、CcSwitch 安装、最终验证

## 路线图

- Windows 稳定化：卸载/重装、重复安装幂等、错误诊断、资源校验。
- 多供应商：DeepSeek、Qwen、GLM、Kimi、OpenRouter 等。
- 多智能体：Claude Code、Codex CLI、Gemini CLI、Aider 等 adapter。
- 多系统：macOS/Linux 独立安装器。
- 自动化测试：Windows VM smoke test、离线包校验、端到端模型调用验证。

## 安全说明

- 不要将 API Key 写入仓库、日志、Issue 或聊天记录。
- 发布公开仓库前必须扫描 `sk-`、`ANTHROPIC_AUTH_TOKEN`、`.claude/settings.json` 等敏感内容。
- 测试使用过的 API Key 建议及时轮换。
