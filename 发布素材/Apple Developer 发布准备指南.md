# Notes Sidecar：Apple Developer 发布资料准备指南

> 适用目标：先把 **Notes Sidecar** 提交至 Mac App Store；同时保留未来从官网发布、经 Apple 公证的 Developer ID 方案。
>
> 最后更新：2026-10-07。Apple 会调整网页文案与入口名称；遇到不一致时，以链接中的官方页面为准。

## 0. 先选清楚：不是只需要“一张证书”

| 发布路径 | 用户如何获取 | 必需签名 | 是否需要 App Store Connect 新建 App | Notes Sidecar 建议 |
|---|---|---|---|---|
| **Mac App Store** | Mac App Store 下载 | Apple Distribution / Mac App Store Connect provisioning profile | **需要** | 首发优先走此路径 |
| **官网 DMG / PKG** | 官网下载 | Developer ID Application；PKG 另需 Developer ID Installer；随后公证 | 不需要（除非同时上架） | 在 Notes 自动化 / 沙盒能力需要更宽松边界时采用 |

这两条路径可同时存在，但证书、签名和交付方式不同：

- `Apple Distribution` / `Mac App Store Connect`：用于上传 App Store Connect。
- `Developer ID Application`：用于签名官网直接下载的 `.app` 或 DMG 内 App，**不能**替代 App Store 上传签名。
- `Developer ID Installer`：仅在做签名 `.pkg` 安装包时才需要。

本项目目前含 Apple Events、Accessibility 可选增强和 Share Extension。上架前必须按 Mac App Store 沙盒规则逐项审计；若某项能力不适合商店沙盒，保持官网 Developer ID 版本是更稳妥的预案。

官方入口：

- [Apple Developer Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list)
- [App Store Connect](https://appstoreconnect.apple.com/)
- [证书类型总览](https://developer.apple.com/help/account/create-certificates/certificates-overview)
- [Developer ID 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)

---

## 1. 发布前的资料总清单

先准备下表中的内容；所有带 `□` 的项目完成后再提交审核。

### 1.1 账户与身份

- [ ] Apple Developer Program 已显示为 Active，且当前 Apple Account 属于正确 Team。
- [ ] 确认 Team ID：Developer 网站右上角团队信息处可见；不要把它当成 Bundle ID。
- [ ] App Store Connect 的 Agreements, Tax, and Banking 状态已完成；没有签署最新协议时，可能无法新建 App。
- [ ] EU 分发决定：若计划在欧盟店面出售，补全交易商（Trader）状态、联系地址和电话；否则不应承诺欧盟可用。
- [ ] 确认你是 Account Holder；若是团队账号，至少要有 Admin / App Manager 权限。创建某些分发证书和 profile 需要 Account Holder 或 Admin。

### 1.2 产品标识（一次确定，尽量不改）

建议值：

| 字段 | 建议值 | 规则 |
|---|---|---|
| App 名称 | `Notes Sidecar` | 在目标店面内必须可用；创建记录后可改显示名，但不要频繁更改 |
| Bundle ID | `com.youwin.NotesSidecar` | 显式 App ID；必须与 Xcode target、Extension 的配置一致 |
| SKU | `notes-sidecar-macos-001` | 仅开发者内部识别；上架后不可修改；不要用个人身份证、邮箱或秘密 |
| 首个版本 | `1.0.0` | `CFBundleShortVersionString`，人类可读 |
| Build | `1` | `CFBundleVersion`，每次上传必须递增 |
| 主语言 | 简体中文或英语 | 选择首发产品页主要语言；后续增加本地化 |

### 1.3 商店文案和素材

- [ ] App 图标：1024 × 1024 PNG，无透明边缘、无圆角遮罩、无促销文字。
- [ ] 截图：至少 1 张、最多 10 张 PNG/JPG；建议中英文各 5 张。
- [ ] 宣传文案：副标题、简介、关键词、支持网址、营销网址（可选）。
- [ ] 隐私政策网址：App Store 的 macOS App 需要可公开访问的 Privacy Policy URL。
- [ ] App Review Notes：清楚解释 Notes 自动化、可选 Accessibility、模型服务商 API Key 的用途和测试方式。
- [ ] 审核账号：本产品没有自建账号则填“无需登录”；若审核必须使用外部模型，提供审核可用的无敏感测试路径，绝不提交个人 API Key。
- [ ] 联系信息：审核联系人姓名、邮箱、电话。

### 1.4 工程与合规材料

- [ ] Release 构建在干净机器 / 新用户账户上可启动。
- [ ] 所有 `Info.plist` 权限用途文字准确、可理解，且与实际功能一致。
- [ ] 沙盒 entitlement 已审核，不保留未使用权限。
- [ ] Apple Events、App Sandbox、Share Extension、Keychain Access Group 分别有真实测试证据。
- [ ] 隐私问卷的数据收集答案与实际网络行为一致。
- [ ] 开源许可证、第三方 SDK 清单、隐私政策和支持页面已准备。

---

## 2. 第一步：在 Apple Developer 注册 App ID

### 2.1 是否需要新建 App？

**需要。**截图中 App Store Connect 显示“无 App”，因此要新建一个 App Store Connect App 记录；同时建议先在 Developer 网站创建对应的显式 App ID。两者不同：

- **App ID / Identifier**：签名与能力的技术身份。
- **App Store Connect App record**：商店页面、构建、TestFlight、价格、隐私和审核资料的业务记录。

### 2.2 创建显式 App ID

1. 打开 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)。
2. 左侧选择 **Identifiers**，右上角点 `+`。
3. 选择 **App IDs** → **App** → `Continue`。
4. Description 填 `Notes Sidecar`。
5. Bundle ID 选择 **Explicit**，填：`com.youwin.NotesSidecar`。
6. 只勾选当前真实需要的 Capabilities。例如：
   - App Groups：仅当主 App 与 Share Extension 已实际使用并已确定 group ID 时启用。
   - iCloud / Push Notifications：当前未使用就不要勾选。
   - Associated Domains：没有 Universal Links 就不要勾选。
7. 点 `Continue`，仔细确认 Bundle ID 后点 `Register`。

### 2.3 Share Extension 的 Bundle ID

项目有 `NotesSidecarShare`。它通常使用单独的 Bundle ID，例如：

```text
com.youwin.NotesSidecar.Share
```

在 Xcode 中确认 Extension target 的 `PRODUCT_BUNDLE_IDENTIFIER`；如果采用显式 ID 手工签名，则为该 Extension 也注册对应 Identifier。不要把主 App 和 Extension 配成同一个 Bundle ID。

### 2.4 创建后立即回填 Xcode

1. 打开 `.xcodeproj`，选中主 App target → **Signing & Capabilities**。
2. Team 选你的新开发者团队。
3. Bundle Identifier 改为上一步创建的值。
4. 勾选 **Automatically manage signing**，先让 Xcode 做一次开发签名。
5. 对 Share Extension target 重复检查 Team、Bundle ID 与签名。
6. Build 一次；若 Xcode 报 capability / entitlement 不一致，先修正工程，不要靠下载 profile 绕过。

---

## 3. 第二步：证书与签名

## 3.1 建议的最省错方式：先用 Xcode 自动管理

用于开发与 App Store 上传时，优先让 Xcode 自动管理签名：

1. Xcode → Settings → Accounts，登录同一 Apple Account。
2. 选择新 Team，点 `Manage Certificates…`。
3. 如没有开发证书，点左下角 `+` 创建 **Apple Development**。
4. App target → Signing & Capabilities → Team 选择正确团队 → 勾选 **Automatically manage signing**。
5. Product → Archive；在 Organizer 中选择 Distribute App → App Store Connect → Upload。

Xcode 会按需建立或使用适合 App Store 的分发签名配置。不要在没有必要时手工创建多个重复证书。

## 3.2 何时手动创建 Apple Distribution 证书

以下情况才使用手工流程：CI 固定签名、团队明确要求证书托管、自动签名无法处理、或你需要离线归档。

1. 打开 Developer 网站 → **Certificates** → `+`。
2. 选择 **Apple Distribution**（用于 App Store 提交）。
3. 在本机打开 **Keychain Access** → Certificate Assistant → Request a Certificate From a Certificate Authority。
4. 输入你的邮箱、选择 *Saved to disk*，生成 `.certSigningRequest`（CSR）。
5. 上传 CSR，下载生成的 `.cer`。
6. 双击 `.cer` 导入 Keychain Access；在 **My Certificates** 中确认它展开后含有私钥。
7. 妥善备份私钥；私钥遗失后无法签署历史证书，只能新建证书并重签新构建。

## 3.3 手工创建 Mac App Store provisioning profile（仅手工签名时）

1. Developer 网站 → **Profiles** → `+`。
2. 在 Distribution 下选择 **Mac App Store Connect**。
3. 选择与主 App 完全匹配的显式 App ID。
4. 选择 Apple Distribution 证书。
5. 命名，例如 `NotesSidecar Mac App Store 2026` → Generate → Download。
6. 双击 `.provisionprofile` 导入 Xcode，或在 Xcode 中下载。
7. 每次启用/停用能力或更换证书后，重新生成 profile。

官方步骤：[创建 Mac App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)。

## 3.4 官网直装预案：Developer ID + 公证

不要在首次 App Store 上传前创建它，除非你确定会同时发布官网版本。

1. Developer 网站 → Certificates → `+`。
2. 选择 **Developer ID Application**，提交 CSR，下载并导入 `.cer`。
3. 若发布 `.pkg`，再创建 **Developer ID Installer**。
4. 用 Developer ID Application 签 `.app`，开启 Hardened Runtime，执行 Apple notarization，最后 staple 票据。
5. 官网包不能用 Developer ID 证书上传到 Mac App Store；两条构建管线应分开命名、分开验收。

官方说明：[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)。

---

## 4. 第三步：把工程改成可上架状态

## 4.1 Release 基础设置

在 Xcode 逐项检查主 App 与 Share Extension：

| 项目 | 主 App | Share Extension |
|---|---|---|
| Team | 你的 Team | 相同 Team |
| Bundle ID | `com.youwin.NotesSidecar` | 独立后缀 ID |
| Version | `1.0.0` | 与主 App 一致或按项目策略 |
| Build | `1` | 与主 App 归档一致 |
| Signing | Automatic（首发推荐） | Automatic |
| Deployment Target | 与产品承诺一致（当前工程为 macOS 15+） | 一致 |

## 4.2 沙盒与 Notes 自动化：先做真实可行性验证

Mac App Store 与官网直装最大的差异是沙盒。对 Notes Sidecar，必须在 **Release + App Sandbox** 下验证：

1. 从 Xcode Archive 导出一个 Development / App Store 构建，而不是只运行 Debug。
2. 首次“读当前笔记”时，确认系统出现正确的 Automation 提示。
3. 用户拒绝 Automation 后，确认粘贴模式仍可建立安全对话。
4. 请求 Accessibility 前，确认窗口跟随功能保持关闭；用户拒绝后核心聊天仍可使用。
5. 验证 Share Extension 将内容交给主 App 的真实链路。
6. 验证 Keychain 保存和读取 Provider API Key；日志、导出文件、运行事件中不得出现密钥。

如果上述任一项在 App Sandbox / App Review 规则下无法成立，不要隐瞒或加私有 API。将该能力关闭、降级为用户显式 Share / Paste，或改走官网 Developer ID 发行并在产品页面清晰说明。

## 4.3 Entitlements 审计清单

- [ ] `com.apple.security.app-sandbox`：Mac App Store 版本必须启用。
- [ ] Apple Events entitlement：仅在有真实、被允许的自动化用途时保留；被控制应用标识必须准确。
- [ ] `com.apple.security.application-groups`：只有主 App 与 Extension 实际共享数据时启用，并使用注册后的 group ID。
- [ ] Keychain access groups：不写死其他 Team 的前缀。
- [ ] 网络 client entitlement：仅当实际连接模型服务商时保留。
- [ ] 不申请 microphone；产品只导入已有音频，不做录音。
- [ ] Speech Recognition 用途说明与实际“本机转写、无云回退”一致。

## 4.4 归档前的代码与隐私核对

- [ ] App 不含测试 API Key、示例 Token、个人邮箱、绝对本机路径、调试开关或崩溃日志中的笔记原文。
- [ ] “原图 / 原始音频不上传”和“只发送通过防火墙的安全文本”能由真实网络抓包或 mock-free 集成验证支撑。
- [ ] 所有 Provider 都是用户直接连服务商；若未来加中转，必须重新评估隐私标签与隐私政策。
- [ ] 自动标签仍未实现，不在商店文案承诺该功能。

---

## 5. 第四步：在 App Store Connect 新建 App

截图中的页面正是正确入口。

1. 打开 [App Store Connect → Apps](https://appstoreconnect.apple.com/apps)。
2. 点蓝色 `+`，选择 **New App**。
3. 填写：
   - Platforms：只选 **macOS**。
   - Name：`Notes Sidecar`（若被占用，先选择一个临时可用名；不要声称拥有他人商标）。
   - Primary Language：选择首发主语言。
   - Bundle ID：选择第 2 步注册的 `com.youwin.NotesSidecar`。
   - SKU：填内部值，如 `notes-sidecar-macos-001`。
   - User Access：只有你一人时选 Full Access；团队协作且要控制范围时选 Limited Access。
4. 点 Create。状态应为 **Prepare for Submission**。
5. 不要在没有确定 Bundle ID 前创建记录：Bundle ID 和 SKU 的改动空间有限。

官方步骤：[Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)。

---

## 6. 第五步：产品页文案与截图

## 6.1 建议的中英文素材结构

本项目已有 `发布素材/截图/zh-Hans/` 与 `发布素材/截图/en-US/` 目录。每种语言建议准备相同叙事顺序：

1. **每篇备忘录有独立对话**：主会话与当前 Notes 笔记并列。
2. **本地优先隐私门**：安全文字预览、隐私片段不发送的提示。
3. **自选模型服务商**：Provider 设置，不露出真实 Key。
4. **快捷动作与写回预览**：明确“用户确认后才写回”。
5. **本机图片 / 音频上下文**：强调原始附件不上传、仅安全文本进入 AI。

每张截图应使用演示笔记、演示账号和虚构数据。不能出现真实姓名、邮箱、电话、Token、客户资料、浏览历史、桌面通知或第三方版权内容。

## 6.2 App Store 文案字段建议

| 字段 | 需要准备什么 |
|---|---|
| Subtitle | 一句说明：Apple Notes 的本地优先 AI 边栏 |
| Promotional Text | 可随时更新的活动文字；首发可留空 |
| Description | 功能、隐私边界、支持的连接模式、用户确认写回 |
| Keywords | 不含竞品商标、不堆砌、不含误导词 |
| Support URL | 用户可访问的帮助页 / 邮箱页 |
| Marketing URL | 可选；官网产品页 |
| Copyright | 年份 + 权利主体 |
| Review Notes | 审核复现路径与权限解释 |

截图格式以 App Store Connect 上传页实际显示的 macOS 尺寸要求为准。官方允许每个支持的设备尺寸和语言上传 **1–10 张** PNG/JPG 截图；若 UI 相同，最高分辨率截图可缩放到较小尺寸。详见：[Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)。

---

## 7. 第六步：隐私、年龄分级和审核说明

## 7.1 App Privacy

1. App Store Connect → 选择 App → 左侧 **App Privacy** → Get Started。
2. 根据真实行为回答数据收集问题；不要按“我们不保存”直接选择 No。
3. Notes Sidecar 当前需要逐项核实：
   - 笔记正文、聊天内容、图片 OCR、音频转写是否仅在设备上处理、是否离开设备。
   - 用户输入的 API Key 是否只进 Keychain、是否不发送给开发者服务器。
   - 用户主动选择模型服务商时，哪些内容会直接发往该第三方 Provider。
   - 是否存在分析、崩溃报告、广告 SDK、远程日志或账户系统。
4. 填入公开的 Privacy Policy URL。Apple 要求准确且及时更新；该网址必须可在审核时访问。

官方说明：[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)。

## 7.2 Age Rating

按真实内容能力填写，不因“可能有 AI”就任意提高或降低。Notes Sidecar 不提供 UGC 社区、社交分享或面向儿童功能；但其可连接外部 AI 服务，应如实回答相关内容生成与用户可访问内容的问题。

## 7.3 给审核人员的 Review Notes 模板

可按实际功能改写，**不填入任何密钥**：

```text
Notes Sidecar is a macOS companion app for Apple Notes.

1. Select a note in Apple Notes, open Notes Sidecar, then choose “Read Current Note”.
2. macOS may ask for Automation permission so the app can read only the selected note.
3. Accessibility is optional and is used only for window following / future precise write-back. Core chat works without it.
4. The app does not require a Notes account, an in-app account, or a developer-hosted login.
5. Model-provider keys are supplied by the user and stored in the macOS Keychain. The developer does not operate a relay server.
6. Images and audio are explicitly imported. Original attachments are processed locally; only privacy-filtered text can be sent to the user-selected provider.
```

如果审核构建需要外部 Provider 才能演示 AI 回复，提供一个专门用于审核、可随时撤销、额度受限的测试配置；不要提供个人主力账号或真实客户数据。

---

## 8. 第七步：Archive、上传、TestFlight 与提交

### 8.1 Archive

1. Xcode Scheme 选择 `Any Mac` / Release 对应配置。
2. Product → Archive。
3. Organizer 中检查 Archive：版本、Build、Bundle ID、签名 Team 都正确。
4. 选择 **Validate App**；先修复所有 error，再处理有意义的 warning。
5. 选择 **Distribute App** → **App Store Connect** → Upload。
6. 上传后等待 Processing；不要因为暂时未出现而重复上传同一个 Build。

### 8.2 TestFlight（推荐）

- 先进行 Internal Testing：仅团队成员，优先验证签名、安装、权限提示、Provider 配置、Notes 读取和崩溃。
- 再决定是否 External Testing；外部测试可能需要 Beta App Review。
- 每次上传新 Build 必须提高 `CFBundleVersion`。

### 8.3 提交审核

1. App Store Connect → App 版本页，选择已经处理完成的 Build。
2. 完成截图、描述、关键词、分类、年龄分级、隐私、审核联系信息与 Review Notes。
3. 逐项检查右侧缺失项；确认价格与可售地区。
4. 点击 **Add for Review**，形成 Ready for Review 草稿。
5. 最后检查无误后点击 **Submit for Review**。

官方步骤：[Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)。

---

## 9. Notes Sidecar 首发前的最终验收表

### 功能

- [ ] 打开边栏、最小化、关闭、Pin、启动项开关都符合预期。
- [ ] 切换 Apple Notes 选中笔记会切换到正确的本地会话。
- [ ] Automation 被拒绝时，粘贴模式可正常使用。
- [ ] 图片和音频只能显式导入；隐私命中片段不会进入出站请求。
- [ ] 没有 Provider Key 时，UI 给出明确、可恢复的说明。
- [ ] 写回 Notes 前总有用户确认；冲突时不覆盖原笔记。

### 安全与合规

- [ ] Release 日志、导出文件、截图、测试记录均无凭据、真实笔记、真实附件或个人资料。
- [ ] 网络连接只去用户选择的 Provider；无开发者中转。
- [ ] Privacy Policy、Support URL 和隐私问卷表达一致。
- [ ] 权限用途文字与 App 实际行为一致。
- [ ] 仅保留实际用到的 entitlement。

### 商店资料

- [ ] 简体中文与英文产品页已分别校对。
- [ ] 中英文截图已替换为无敏感演示数据版本。
- [ ] App 名称、Bundle ID、SKU、版本号和版权主体无误。
- [ ] Review Notes 说明了可选权限、无账号依赖和测试路径。

---

## 10. 你现在最推荐的执行顺序

1. 在 Developer 网站注册主 App ID 与 Share Extension ID。
2. 在 Xcode 用 Automatic Signing 绑定 Team，先完成一次 Release Archive。
3. 在 App Store Connect 新建 macOS App record（截图中的蓝色 `+` 或“添加 App”）。
4. 完成 App Sandbox / Apple Events / Extension 的真实 Release 验证；若存在商店沙盒阻塞，先决定降级能力还是官网 Developer ID 路线。
5. 完成中英文截图、产品页文案、隐私政策页面和 Support URL。
6. 上传首个 Build，先 Internal TestFlight。
7. 修复测试发现的问题后，填写隐私问卷和审核说明，再提交审核。

不要现在就创建一堆手工 profile 或 Developer ID 证书。首发 App Store 的最小可行路径是：**显式 App ID → Xcode 自动签名 → App Store Connect App record → Archive / Upload → TestFlight → Review**。只有自动签名、CI 或官网直装确有需要时，再按本指南对应章节手工创建证书。
