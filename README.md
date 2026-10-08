# Notes Sidecar

让 AI 贴近你的 Apple Notes：选中一篇笔记，侧栏与它持续对话，可一键复制 / 追加回 Notes。

> 当前阶段：核心对话、Provider 管理、历史与恢复、设置中心、Notes 窗口跟随和 Share Extension 已实现；继续以 Mac App Store 沙盒要求做发布前验证。

---

## 1. 准备工作

- macOS 15.0+（已在 macOS 27.0.1 / Xcode 27.0 / Swift 6.4 构建）
- Xcode 命令行工具：`xcode-select --install`
- 首次跑需要给 Notes 自动化权限（macOS 弹窗 / 系统设置 → 隐私与安全 → 自动化）

## 2. 构建并运行

```bash
# 生成 Xcode 工程（已生成过则跳过）
/Users/youwin/AI/tools/xcodegen/bin/xcodegen generate

# Debug 构建
xcodebuild -project NotesSidecar.xcodeproj \
           -scheme NotesSidecar \
           -configuration Debug \
           -destination 'platform=macOS' \
           build

# 启动
open ~/Library/Developer/Xcode/DerivedData/NotesSidecar-*/Build/Products/Debug/NotesSidecar.app
# 或直接跑二进制看日志
~/Library/Developer/Xcode/DerivedData/NotesSidecar-*/Build/Products/Debug/NotesSidecar.app/Contents/MacOS/NotesSidecar
```

> 启动后是菜单栏图标（`✨`），没有主窗口。点菜单栏图标或按 ⌥⌘N 打开侧栏。

## 3. 第一次对话

1. 点菜单栏 `✨` → "打开边栏"，出现侧栏
2. 侧栏显示 "打开 Notes 以开始"，点 "打开 Notes"，选一篇笔记（这是为了让 Notes 进入前台）
3. 系统会弹窗问 "Notes Sidecar 想控制 Notes"，选 "允许"
4. 切到侧栏 → “设置” → “添加服务商”。MiniMax CN 等内置服务商只需填写 API Key；地址、协议和推荐模型由客户端维护
5. 回到 Notes，选中笔记，回到侧栏 → 现在能看到笔记标题
6. 输入问题（`/summary` `/tasks` `/rewrite` 等 7 个斜杠命令可用），按 ⌘↩ 发送
7. 生成中按 ⌘. 停止；生成完按 ⌘⇧C 复制 / ⌘⇧A 追加到当前笔记

## 4. 快捷键

| 快捷键 | 作用 |
|---|---|
| ⌥⌘N | 显示 / 隐藏侧栏 |
| ⌥⌘R | 刷新当前笔记上下文 |
| ⌘↩ | 发送输入框里的问题 |
| ⌘. | 停止生成 |
| ⌘⇧C | 复制最后回答 |
| ⌘⇧A | 追加最后回答到当前笔记 |
| ⌘⇧W | 按设置中的默认策略执行复制、追加预览或新建笔记 |
| ⌘O | 打开 Notes |

## 5. 隐私不变量（hard constraint，MVP 也保留）

- 密钥只保存在本机 Keychain（`keychainCredentialRef = provider.<UUID>.credential`），从未外发
- 任何出站请求先过 `SensitiveContentFirewall`：
  - 命中常见凭据（sk-/sk-ant-/ghp_/AKIA/.../private key/api_key=.../password=...）→ 整段置 `Protected` → 不发
  - 规则未就绪 → fail-closed（拒绝出站）
- 图片只在本机经 Vision OCR / 分类；原图不上传，隐私命中行在加入问题前排除并提示用户确认
- 笔记原文 = 出站内容，**不**做语义重写；模型回复可一键回写

## 6. 跑测试

```bash
xcodebuild -project NotesSidecar.xcodeproj \
           -scheme NotesSidecar \
           -configuration Debug \
           -destination 'platform=macOS' \
           test
```

当前 37 个测试，全部通过：
- `FirewallTests`：凭据嗅探 / 图片 OCR 隐私逐行排除 / fail-closed / URL 参数清洗
- `PromptBuilderTests`：提示词组装 / 斜杠命令 / Sendable
- `NoteContextTests`：正文哈希 / SlashCommand 匹配
- `RedactorTests`：日志脱敏 / 请求头清洗
- `ConversationStoreTests`：草稿隔离、事件持久化、单条/范围删除和会话清理
- `ResultWriterTests`：写回预览、冲突检测与重建计划

## 7. 项目结构

```
MacOS Notes Sidecar/
├── project.yml                 # XcodeGen 配置（targets / entitlements / 依赖）
├── App/
│   ├── Main/                   # AppModel / AppDelegate / NSPanel / 菜单栏 / 快捷键 / SwiftUI App 入口
│   ├── Views/                  # RootView / HeaderBar / ConversationView / ComposerView / SettingsView
│   ├── Theme/                  # Tokens / GlassStyle / Typography
│   ├── ShareExtension/         # Notes 分享到 Sidecar 的系统扩展
│   └── Resources/              # Info.plist / Debug & Release entitlements / Assets.xcassets
├── Sources/NotesSidecarCore/
│   ├── Models/                 # NoteLocator / ProviderProfile / Conversation / RunEvent / SlashCommand
│   ├── Privacy/                # SafeContext / SensitiveContentFirewall
│   ├── Security/               # KeychainStore / Redactor
│   ├── Bridge/                 # NotesBridge / AppleScriptBridge
│   ├── Providers/              # ModelProvider / OpenAICompatible / Anthropic / ModelRouter
│   ├── Session/                # ConversationState / SessionController / PromptBuilder
│   ├── Storage/                # ConversationStore / ProviderStore
│   ├── Writing/                # ResultWriter
│   └── Logging/                # Logger
├── Tests/NotesSidecarCoreTests/
└── 设计草图/                   # 设计稿与方案
```

## 8. 已知限制

- **正式 App Group 尚未注册**：加入 Apple Developer Program 后，需要为主 App 与 Share Extension 注册并分配 `group.com.youwin.NotesSidecar`
- **Debug 与 Release 权限不同**：Debug 便于本机开发；Release 启用 App Sandbox，并需要持续运行发布验证脚本
- **多模态未实现**：Vision / Speech / Web Fetch 都已留接口
- **自动打标未实现**：每个会话只有基本元数据
- **OCR / EXIF / 位置信息未处理**：MVP 只做文本扫描
- **i18n**：UI 文案以中文为主

## 9. 下一步（MVP 跑通后）

- [x] Release 沙盒 + Notes Apple Events 本机验证
- [x] Share Extension：文本/链接 → Sidecar 本地共享收件箱
- [ ] Apple Developer Team 注册 App Group，并做正式签名的 Share Extension 验收
- [ ] 多模态：图片 OCR / 音频转写 / 链接抓取（本地 Vision/Speech/URLSession）
- [ ] 1 主分组 + 1-4 自动标签 + "私密" 标签
- [ ] Provider Web Fetch 安全接入
- [ ] 自动签名 / 公证 + DMG 分发

发布账号、App ID、App Group、证书与 App Store Connect 的操作清单见 [`Apple开发者权限与开通清单.md`](./Apple开发者权限与开通清单.md)。
