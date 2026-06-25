# 跨平台/多智能体统一产品原则 PRD

## 1. 文档目的

本文档定义 ai-agent-auto-deploy 从 Claude Code Windows 单体项目扩展到多系统、多智能体时必须保持一致的产品价值和工程验收原则。它优先解决一个核心问题：不同智能体的安装方式、配置方式、模型协议并不相同，但用户体验承诺必须尽量相同。

统一目标不是做一个庞大的万能脚本，而是先做一组可独立交付、可测试、可支持的单系统单智能体安装包，再在这些包稳定后提供可选统一入口。统一的不是 UI 形态，而是能力识别、配置写入、验证闭环、失败诊断和回滚能力。

## 2. 统一产品承诺

每个正式安装包都应尽力满足：

- 一键：用户下载安装包后运行一个脚本即可完成安装。
- 低门槛：用户不需要理解运行时、包管理器、shell profile、模型协议。
- DeepSeek 默认：默认配置低成本、无需翻墙的 DeepSeek 路径。
- 少交互：除 API Key 外，不要求普通用户做复杂选择。
- 弱网络友好：关键资源可离线随包交付，网络失败有降级策略。
- 可验证对话：安装完成必须证明目标智能体真的通过目标模型返回响应。
- 可诊断：失败日志能帮助交付者定位问题，同时不泄露密钥。

## 3. 配置文件优先原则

判断一个智能体是否适合做 “一键部署 + DeepSeek 默认”，不能看它有没有 GUI，也不能简单看它有没有 interactive onboarding。正确判断标准是：它是否存在稳定、可脚本化、可验证的模型/provider 配置面。

优先级如下：

1. 官方或稳定配置文件：能直接写入 provider、base URL、model、auth env/key 引用。
2. 官方非交互 CLI：能以参数或环境变量完成配置，并落到稳定配置文件。
3. 交互 onboarding：如果最终写入稳定配置文件，可以通过脚本复现或生成该配置。
4. GUI 设置：只有当 GUI 写入的配置文件稳定可控时，才可作为研究入口；GUI 本身不应成为正式安装包的唯一自动化路径。
5. 无稳定配置面：暂不符合正式一键部署要求，只能列为手动/研究状态。

这条原则修正了一个容易走偏的判断：智能体是否存在 GUI 形态，不是 DeepSeek 支持与否的标准。只要智能体有稳定模型配置文件或可脚本化配置入口，就可以评估通过脚本把模型改为 DeepSeek。

## 4. DeepSeek 适配决策树

每个智能体做 PRD 前必须先回答以下问题：

1. 是否原生支持 DeepSeek provider？
   - 是：优先使用原生 provider 配置。
2. 是否支持 OpenAI-compatible Chat Completions，并允许自定义 base URL？
   - 是：评估直接接入 DeepSeek OpenAI-compatible endpoint。
3. 是否支持 Anthropic-compatible endpoint？
   - 是：评估直接接入 DeepSeek Anthropic-compatible endpoint。
4. 是否只支持 OpenAI Responses API 或其他 DeepSeek 不兼容协议？
   - 是：需要桥接层或暂缓正式交付，不能假装直连已完成。
5. 是否只能手动 GUI 配置，且无稳定落盘配置？
   - 是：不进入正式一键部署交付，只能作为手动说明或研究项。

结论分类：

- A 类：可脚本化配置，DeepSeek 可直连，适合正式安装包。
- B 类：可脚本化配置，但协议需要桥接，适合技术预览，桥接稳定后再 release。
- C 类：安装可自动化，但 DeepSeek 配置路径未证明，只能做安装 smoke，不能称为 DeepSeek 一键部署。
- D 类：依赖手动 GUI 或不稳定配置，暂不符合产品承诺。

## 5. 单包优先，统一入口靠后

交付形态分两层：

- 单独安装包：例如 Claude Code Windows、Claude Code macOS、OpenClaw Windows。它们是默认交付形态，便于测试、定位和客服支持。
- 统一入口：在多个单包均达到 release-level 后提供菜单式入口，调用同一套已验证模块，不复制安装逻辑。

统一入口不得成为绕过单包验收的捷径。任何智能体或平台没有单包 release pass，就不能在统一入口中标为可放心交付。

## 6. 每个安装包的共同生命周期

每个 OS + Agent 包都应实现同一生命周期：

1. detect：检测系统、架构、权限、已有安装、网络、磁盘。
2. verify-assets：校验离线资源 manifest、SHA256、压缩包可读性。
3. install-runtime：安装 Node、Git、PowerShell 7、Python、shell 工具或 App 运行时。
4. install-agent：安装目标智能体 CLI 或桌面应用。
5. configure-provider：写入 DeepSeek provider/model/auth 配置。
6. verify-agent：版本检查、fresh-terminal 启动、最小对话验证。
7. finish：PATH/profile、快捷方式、使用说明、日志摘要。
8. reset：卸载项目自有文件、还原/备份配置、恢复可重复测试状态。

## 7. 平台要求

Windows：

- 默认以普通用户权限运行，避免要求管理员权限。
- 必须处理 Windows 自带 PowerShell 5.1 与 Claude Code 运行依赖之间的差异。
- 如果目标智能体需要 Git Bash、PowerShell 7、Python 等，安装包应随包提供或明确联网安装策略。
- 验收应以 clean-base Windows VM 为准，而不是开发者本机。

macOS：

- 验收必须在真实 Mac、云 Mac 或 Apple-hardware macOS 虚拟化环境中完成。
- GitHub macOS runner 可以做 hosted smoke，但不能替代最终用户视角验收。
- 必须处理 Apple Silicon / Intel 差异、shell profile、Gatekeeper/quarantine、Homebrew 是否存在等问题。

## 8. 智能体 PRD 模板要求

每个新智能体/新系统 PRD 至少包括：

- 用户画像和核心使用场景。
- 官方安装路径与离线资源策略。
- 模型/provider 配置文件或可脚本化配置入口。
- DeepSeek 兼容协议判断和证据。
- 需要安装的运行时依赖。
- 安装完成后的 fresh-terminal 验证命令。
- 最小 DeepSeek 对话验证命令。
- 失败提示和用户可执行修复动作。
- 安全策略：密钥输入、脱敏、日志、CI secret、artifact。
- release gate：静态检查、hosted smoke、clean VM/real machine、provider smoke、conversation smoke。
- 不符合产品承诺的已知限制。

## 9. 当前智能体适配判断

Claude Code：

- Windows v3.2.3 已证明可通过配置文件/环境变量直连 DeepSeek Anthropic-compatible endpoint。
- macOS 应沿用同一产品原则，但必须在真实 Mac 或 Apple-hardware 虚拟化环境中验证。
- CcSwitch 是可选增强，不是主链路。

OpenClaw：

- 已有资料显示 OpenClaw 有 DeepSeek provider 文档和非交互 onboard 参数。
- 下一步应确认 onboard 最终落到哪个稳定配置文件，并优先直接生成或通过非交互 CLI 生成该配置。
- 如果 OpenAI-compatible endpoint 可直接使用，应优先直连 DeepSeek，不引入桥接。

Codex：

- 需要重点确认 Codex 当前自定义 provider 所需协议是否与 DeepSeek 直接兼容。
- 如果 Codex 要求 Responses API，而 DeepSeek 只提供 OpenAI-compatible Chat Completions 或 Anthropic-compatible endpoint，则需要桥接层。
- 因此 Codex 可能属于 B 类：配置可脚本化，但是否能无桥接直连，需要以实际 smoke 结果为准。

Cursor：

- 不能因为它是 GUI 应用就排除 DeepSeek 一键部署可能。
- 下一步应研究 Cursor 的模型配置文件、settings 存储、CLI/脚本入口和 custom model 支持。
- 在配置文件路径未证明前，只能称为安装包或手动配置研究包，不能称为 DeepSeek 一键部署包。

## 10. 统一错误分类

所有安装包应使用一致的错误分类，便于用户理解和客服定位：

- E_ENV：系统版本、架构、权限、磁盘、shell、PATH 不满足。
- E_ASSET：离线资源缺失、hash 不匹配、压缩包损坏。
- E_INSTALL：运行时或智能体安装失败。
- E_CONFIG：配置文件路径、格式、权限、优先级冲突导致写入失败。
- E_AUTH：API Key 缺失、格式错误、认证失败。
- E_NETWORK：网络不可达、DNS、TLS、代理、连接超时。
- E_PROVIDER：目标智能体不支持当前 DeepSeek 协议或模型。
- E_VERIFY：版本可见但 fresh-terminal 启动或最小对话失败。
- E_OPTIONAL：快捷方式、托盘、GUI 辅助工具等非主链路失败。

每个错误都必须包含：发生步骤、用户可执行的下一步、日志路径、是否可以重试、是否已回滚或保留备份。

## 11. 验证标准

统一 release-level 标准：

- Static：语法、manifest、hash、secret scan、dry-run 通过。
- Hosted smoke：GitHub runner 或等价临时环境完成安装/基础命令验证。
- Clean VM / real machine：从 clean-base 环境安装，不依赖开发者本机残留。
- Provider smoke：DeepSeek 配置写入并被目标智能体实际读取。
- Conversation smoke：通过目标智能体路径发起最小 prompt 并得到预期响应。

任何只完成 Static 或 Hosted smoke 的包，都不能说成“已经可交付给普通用户放心安装”。它可以是技术预览，但不是 release。

## 12. 安全要求

- 不在仓库、脚本、日志、截图、artifact、PRD 示例中写入真实 API Key。
- 修改配置前保留备份；修改后记录脱敏变更摘要，必要时提供配置前后 diff。
- 交互输入时尽量隐藏或脱敏显示。
- CI 使用仓库 secret 或临时 secret，运行输出必须 mask。
- 本地测试尽量减少真实模型调用次数，优先使用最小 prompt。
- 失败日志保留足够定位信息，但 token 只显示固定脱敏形式。

## 13. 开发顺序

建议顺序：

1. 固化 Claude Code Windows v3.2.3 PRD 和验收清单。
2. 按本原则为 Claude Code macOS、OpenClaw、Codex、Cursor 分别写 PRD。
3. 先验证各智能体的配置文件/协议兼容性，再写安装包。
4. 对每个单包完成 Static -> Hosted smoke -> Clean VM/real machine -> Provider smoke -> Conversation smoke。
5. 多个单包达到 release-level 后，再实现统一入口。

## 14. 明确禁止的产品表达

以下表达必须避免：

- “安装脚本跑完了，所以已经支持 DeepSeek。”
- “GitHub runner 通过了，所以普通用户安装包可交付。”
- “有 GUI，所以不能脚本化配置 DeepSeek。”
- “没有 GUI，所以一定能自动化配置 DeepSeek。”
- “能打开应用，所以对话链路已验证。”
- “用户可以自己去设置模型，所以一键部署已经完成。”

正式口径必须回到可验证事实：安装、配置、启动、DeepSeek 对话四件事是否在目标用户环境中跑通。


