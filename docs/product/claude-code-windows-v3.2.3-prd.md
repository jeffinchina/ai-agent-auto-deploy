# Claude Code Windows v3.2.3 PRD

## 1. 文档目的

本文档从已经在 Windows clean-base 虚拟机中跑通的 Claude Code Windows v3.2.3 安装包反向归纳产品需求。它不是重新设计一个更理想化的安装器，而是把已经证明有效的产品价值、安装流程、工程验收和失败处理固化下来，作为后续 macOS 版、其他智能体安装包、统一入口的基准样板。

当前可复用的核心结论是：Claude Code Windows 的可靠路径不是强依赖 CcSwitch GUI，而是通过安装脚本直接写入 Claude Code 可识别的 DeepSeek Anthropic-compatible 配置，同时把 CcSwitch 作为可选的可视化模型管理工具交付给用户。这个折中方案已经在真实 Windows 虚拟机用户视角中证明比强行走 CcSwitch 链路更稳。

## 2. 产品定位

Claude Code Windows v3.2.3 面向已经拿到安装包的普通 Windows 用户，目标是在弱网络或无外网环境下，通过双击/运行一个部署脚本完成 Claude Code、DeepSeek 默认模型、必要运行时和辅助工具安装。用户在过程中只需要输入自己的 DeepSeek API Key，安装完成后打开新终端输入 `claude`，即可开始对话。

产品承诺必须朴素而可验证：

- 用户不需要理解 Node.js、npm、PATH、Git Bash、PowerShell、Claude Code 配置文件。
- 用户不需要翻墙，也不需要 Anthropic 官方账号。
- 安装包优先支持离线/弱网络场景，能从随包资源完成关键安装。
- 安装完成不是打印成功就结束，必须验证 fresh-terminal 启动和 DeepSeek 实际对话链路。
- CcSwitch 是加分项，不是 Claude Code 能否启动和使用 DeepSeek 的单点依赖。

## 3. 用户画像

主要用户：

- Windows 10/11 普通用户，对命令行不熟，但能按提示运行 PowerShell 脚本。
- 有 DeepSeek API Key，希望用低成本国产模型体验 Claude Code 工作流。
- 网络环境不稳定，或者不方便直接从 npm、GitHub、国外站点下载依赖。
- 需要被交付一个文件夹/压缩包，而不是一串复杂教程。

辅助用户：

- 交付者/客服/运营，需要把安装包发给别人，并根据日志定位失败原因。
- 开发者/测试者，需要在 clean-base VM 中重复验证安装链路。

## 4. 用户体验流程

标准流程：

1. 用户解压安装包到本地目录。
2. 用户运行 Windows 一键部署脚本。
3. 脚本做安装前检测：系统、磁盘、架构、网络、PowerShell、Git/Pwsh 依赖、可写目录、离线资源完整性。
4. 脚本安装或配置 Node.js、Claude Code、Git for Windows 或 PowerShell 7 运行依赖。
5. 脚本提示用户输入 DeepSeek API Key，并在内存中完成验证与配置写入。
6. 脚本安装 CcSwitch 离线版并创建可发现的打开方式和说明文档。
7. 脚本做 fresh-terminal 级别验证：`claude --version`、`claude -p` 最小 DeepSeek 对话。
8. 脚本输出成功摘要：模型、端点、配置路径、日志路径、下一步命令。

交互原则：

- 必填输入只有 DeepSeek API Key。
- 进度用稳定步骤呈现，不靠长时间无反馈的黑屏或空终端等待用户猜测。
- 遇到失败时给出用户可执行的下一步，而不是只输出异常堆栈。
- API Key 在屏幕、日志、错误、GitHub artifact 中必须脱敏。

## 5. 安装包输入项

必须输入：

- DeepSeek API Key：由用户在安装时输入。脚本可以校验格式和可用性，但不得把明文写入日志、截图、仓库、CI 输出。

可选输入：

- 安装目录：默认使用用户目录下项目自有目录，普通用户不需要改。
- 是否启动 CcSwitch：默认安装并尝试启动，失败不得阻塞 Claude Code 直连使用。
- 是否运行对话验证：正式包默认运行；调试/离线测试可提供跳过选项，但跳过后不得标记为 release pass。

不得要求普通用户输入：

- npm registry、PATH 片段、Claude Code 配置 JSON、模型 endpoint、Git Bash 路径、PowerShell profile 内容。

## 6. 离线资源要求

安装包应包含并校验：

- Node.js Windows x64 离线压缩包。
- Claude Code npm 包或离线安装资源。
- Git for Windows 或 PowerShell 7 安装资源；至少保证 Claude Code 在无 Git/Pwsh 的原生 Windows 环境中可启动。
- CcSwitch 离线版。
- 资源 manifest：文件名、版本、SHA256、用途、是否必需。
- 安装脚本、使用说明、故障排查说明、重置/卸载脚本。

资源校验要求：

- 缺失必需资源时，安装前直接失败。
- SHA256 不匹配时，明确提示资源损坏或安装包不完整。
- 可选资源失败时，必须说明是否影响 Claude Code 主链路。

## 7. DeepSeek 配置方式

Claude Code Windows v3.2.3 的稳定默认路径是直连 DeepSeek Anthropic-compatible endpoint。脚本负责写入 Claude Code 能识别的配置和认证变量，例如模型、端点、token 来源等。

产品原则：

- 配置判断以 Claude Code 实际读取的配置文件、环境变量和 CLI 行为为准，不以 GUI 是否能填满配置为准。
- CcSwitch 作为可选可视化配置工具交付，但不承担 release gate 的主链路责任。
- 如果 CcSwitch 未来在 VM 中被证明可稳定完成代理/模型切换，再作为可选模式加入，而不是替换已经跑通的直连默认路径。
- 配置写入前应备份用户已有 Claude Code 配置，并记录脱敏 diff 或变更摘要；重复安装必须幂等。
- 少交互不等于无确认覆盖：遇到会覆盖用户既有 provider/model 配置的动作时，应自动备份并用清晰语言说明。

## 8. 安装前检测

安装前检测必须覆盖：

- Windows 版本和架构。
- C 盘或目标安装盘可用空间。
- 当前用户目录、LocalAppData、Desktop 是否可写。
- 当前 PowerShell 是否允许执行脚本；如不允许，给出当前用户级修复命令。
- 是否已有 Node、Claude Code、Git Bash、PowerShell 7，并判断是否可复用或需要项目内安装。
- 网络可用性；网络不可用时切换为离线策略。
- 安装包资源完整性。
- 是否存在旧版本项目目录、旧配置、旧 PATH，必要时提示备份/覆盖策略。
- 中文用户名、空格路径、OneDrive 桌面、非管理员权限、杀软拦截等 Windows 常见用户环境。
- 用户已有 Claude Code provider/model 配置的优先级，避免项目配置、用户配置、环境变量互相覆盖后不可诊断。

检测失败输出必须分级：

- 阻断失败：无法继续安装，必须修复后重试。
- 可降级失败：跳过可选项，但主链路继续。
- 提醒项：不影响安装，但可能影响体验。

## 9. 成功标准

一次安装只有同时满足以下条件，才可以称为成功：

- 安装脚本退出码为 0。
- Node.js 可用且版本符合 manifest。
- Claude Code 可用且版本符合 manifest。
- Git Bash 或 PowerShell 7 依赖满足 Claude Code Windows 启动要求。
- 新开终端后 `claude` 可以被 PATH 找到。
- DeepSeek API Key 验证通过，并完成配置写入。
- `claude -p` 通过 DeepSeek 实际返回最小响应。
- CcSwitch 安装完成；若启动或托盘不可见，必须记录为非阻断警告。
- 桌面或用户可发现位置生成使用说明和快捷方式；如桌面路径异常，必须回退到安装目录并提示。
- 日志存在，且不包含明文 API Key。

## 10. 失败提示要求

错误提示要按用户能理解的方式表达：

- 缺少 Git/Pwsh：说明 Claude Code Windows 需要 Git Bash 或 PowerShell 7，不是用户当前 PowerShell 5.1 打不开，而是 Claude Code 自身启动依赖未满足。
- API Key 无效：提示重新复制 DeepSeek API Key，日志只显示脱敏片段。
- 网络不可用：说明将使用离线资源；如果当前步骤必须联网，提示具体用途。
- 资源损坏：提示重新获取完整安装包，并显示损坏文件名与期望/实际 hash 的脱敏摘要。
- PATH 未刷新：提示新开 PowerShell 或重启终端，不要求用户手动编辑 PATH。
- 桌面快捷方式失败：提示已在安装目录生成替代说明。
- CcSwitch 启动失败：说明不影响 `claude` 直连 DeepSeek，可稍后手动打开。

## 11. 验收标准

发布前必须具备：

- 静态检查：PowerShell parser、secret scan、manifest schema、zip/hash 校验。
- clean-base Windows VM：从未安装过 Claude Code/Git/Pwsh/Node 的快照开始执行。
- 离线/弱网络路径：断网或弱网络时，核心安装依然可完成。
- fresh-terminal 验证：安装后新开终端运行 `claude`。
- DeepSeek 对话验证：最小 prompt 返回预期响应，调用次数尽量少。
- 日志验收：不泄露 API Key，包含失败定位所需路径和步骤。
- 重复安装验收：第二次运行不会破坏配置，能清晰说明复用/覆盖行为。
- 配置冲突验收：已有其他 provider、项目级配置、用户级环境变量时，脚本能说明最终生效来源。
- 卸载/重置验收：能移除项目自有文件、PATH 项和快捷方式，保留或备份用户配置。

## 12. 当前 v3.2.3 状态与缺口

已达到的基准：

- 用户已在 Windows VM 中完成 v3.2.3 安装并确认 Claude Code 可正常对话。
- DeepSeek 直连方案比强依赖 CcSwitch 配置链路更稳。
- Git/Pwsh 依赖问题已被识别为真实 Windows 用户也可能遇到的问题，不是虚拟机特有问题。

仍需补强：

- 将用户口头/聊天反馈固化为结构化验收 artifact。
- 对 VM 测试输出进行自动扫描并写入 acceptance ledger。
- 完善 uninstall/reset 体验。
- 继续强化错误提示的用户语言，而不是开发者语言。
- 将本 PRD 中的验收标准转为可执行测试清单。


