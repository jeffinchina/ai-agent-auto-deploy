# AI Agent Auto Deploy

面向普通 Windows 用户的一键 AI Agent 部署脚本。当前稳定主线是 Claude Code + DeepSeek 直连，同时随包安装 CcSwitch，方便用户后续在可视化界面管理更多模型提供商。

## 当前版本

- 版本：`v3.2.3`
- 系统：Windows 10/11 x64
- 主链路：Claude Code -> DeepSeek Anthropic-compatible endpoint
- 附加工具：CcSwitch provider manager
- 运行依赖：Node.js + Claude Code + PortableGit

## 用户流程

1. 将发布包文件夹复制到目标电脑。
2. 双击 `一键部署.cmd`。
3. 根据提示输入 DeepSeek API Key。
4. 脚本会自动完成资源校验、依赖安装、Claude 配置、启动验证和 DeepSeek 对话验证。
5. 安装完成后，重新打开 PowerShell 或 CMD，输入 `claude` 开始对话。

## v3.2.3 关键增强

- 安装前检查 Windows x64、磁盘空间、安装目录和日志目录写入权限。
- 使用 `assets/manifest.json` 对 Node.js、Claude Code、PortableGit、CcSwitch 离线资源做 SHA256 校验。
- 即使系统已有 PowerShell 7，也会配置 Git Bash / PortableGit，降低 Claude Code Windows 启动失败风险。
- DeepSeek API Key 输入改为隐藏输入，日志会脱敏 `sk-...` 形式的密钥。
- 配置写入后会执行 `claude --version` 和 `claude -p "Reply with exactly OK"` 两层验证。
- 写入 `.claude/settings.json` 时保留用户已有非托管环境变量。
- 错误提示增加可执行建议，减少“部署完成但用户第一次启动才失败”的情况。

## 发布包

Git 仓库保存源码、配置、文档和资源清单。完整离线安装包作为 GitHub Release 附件发布，不直接提交到 git 历史中。

当前应生成的发布包名：

- `ai-agent-auto-deploy-v3.2.3-windows.zip`
- `把这个文件夹拷到待安装的电脑_V3.2.3.zip`
- SHA256: `9B7D4CD8B69349359928D3EC7356F1E6D2EA391CB4E042B2284AA7F2AEA6CCDF`

## 项目结构

```text
ai-agent-auto-deploy/
  deploy.ps1                  # Windows 主部署脚本
  一键部署.cmd                 # 用户双击入口
  使用说明.txt                 # 用户说明
  assets/
    manifest.json             # 离线资源清单与校验值
    claude-code-offline/       # Claude Code 离线 npm 包
  config/
    deepseek-preset.json
  docs/
    roadmap.md
    vm-test-notes.md
  tests/
    verify-windows-package.ps1 # 包自检脚本
```

## 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify-windows-package.ps1
```

VM 端到端测试仍以 VirtualBox clean-base 快照为准。真实 DeepSeek 对话验证需要用户输入自己的 API Key，不应在自动化脚本、日志或 GitHub 中硬编码。

## 后续路线

- 先把 Claude Windows 包稳定到可公开分发：卸载/重装幂等、离线资源校验、DeepSeek 对话验证、错误诊断。
- 抽出公共安装框架：资产清单、阶段执行器、日志/错误码、provider 配置、VM 测试清单。
- 再扩展 macOS 安装包。
- 按顺序扩展 Codex、OpenClaw、Cursor 的 Windows/macOS 独立安装包。
- 最后提供统一入口版本，同时保留单独分发包。

## 安全说明

- 不要把 API Key 写入仓库、日志、Issue、截图或聊天记录。
- 发布前必须扫描 `sk-`、`ANTHROPIC_AUTH_TOKEN`、`.claude/settings.json` 等敏感内容。
- 测试使用过的 API Key 建议及时轮换。
