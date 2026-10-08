# Notes Sidecar：Apple 开发者权限与开通清单

更新日期：2026-10-05

本文只记录需要产品所有者亲自注册、签约、提交资料或授权的事项。Notes Sidecar 是本地运行的 macOS App，不依赖开发者后台；用户的模型 API Key 保存在本机 Keychain，笔记内容只在用户主动提问时直接发往其选择的模型服务商。

## 结论

现在不必立刻付费加入 Apple Developer Program。工程可以继续完成开发、单元测试、本机 ad-hoc 签名、App Sandbox 验证和本地 StoreKit 测试。

等产品达到“只差正式签名、TestFlight 和审核”的状态后，再加入 Apple Developer Program，并集中完成本文中的账号、标识符、证书和 App Store Connect 配置。

其中最关键的一项是注册并同时分配给主 App 与 Share Extension 的 App Group：

```text
group.com.youwin.NotesSidecar
```

## 一、加入 Developer Program 前需要准备

- [ ] 决定以个人还是组织身份注册。个人账号展示个人法定姓名；组织账号通常需要可验证的法人实体、D‑U‑N‑S 信息以及代表组织签约的权限。
- [ ] 准备专门用于开发者账号的 Apple Account，并开启双重认证。
- [ ] 确认拟使用的开发者显示名称、联系邮箱、支持邮箱和法定收款主体。
- [ ] 确认以下标识符不会再更改。它们会进入签名、Keychain、App Group 和 App Store 记录：

| 用途 | 当前标识符 |
| --- | --- |
| 主 App Bundle ID | `com.youwin.NotesSidecar` |
| Share Extension Bundle ID | `com.youwin.NotesSidecar.ShareExtension` |
| App Group | `group.com.youwin.NotesSidecar` |

> 如果以后要更换 `com.youwin` 前缀，应在正式注册 App ID、创建 App Store Connect 记录和发布第一个版本之前统一修改工程。发布后再改会影响更新路径、Keychain 数据和共享容器。

## 二、加入 Developer Program 后必须注册

在 Apple Developer 网站的 **Certificates, Identifiers & Profiles** 中完成。

### 1. 注册两个 Explicit App ID

- [ ] 注册主 App ID：`com.youwin.NotesSidecar`
- [ ] 注册 Share Extension App ID：`com.youwin.NotesSidecar.ShareExtension`
- [ ] 两者都使用 Explicit App ID，不使用通配符。

主 App 与扩展是两个独立的可执行组件，因此各自需要与工程 Bundle ID 完全一致的标识符和签名配置。

### 2. 注册 App Group

- [ ] 新建 App Group：`group.com.youwin.NotesSidecar`
- [ ] 在主 App ID 上启用 **App Groups**，并勾选该组。
- [ ] 在 Share Extension App ID 上启用 **App Groups**，并勾选同一组。
- [ ] 修改能力后，让 Xcode 重新生成或刷新 provisioning profiles。

这个共享容器只用于 Share Extension 把用户从 Notes 分享的文字交给主 App。工程当前已经写入同名 entitlement，但在开发者 Team 中注册之前，正式签名无法授权该容器。

### 3. 主 App 需要的本地能力

以下能力已经写入 Release entitlements，正式签名前需要确认生成的 provisioning profile 与签名产物保留它们：

| 能力 | entitlement | 用途 | 是否需要单独向 Apple 申请 |
| --- | --- | --- | --- |
| App Sandbox | `com.apple.security.app-sandbox` | Mac App Store 必需 | 否 |
| 出站网络 | `com.apple.security.network.client` | 直接连接用户选择的模型 API | 否 |
| Apple Events | `com.apple.security.automation.apple-events` | 由用户授权控制 Notes | 否，但需用途说明 |
| Notes 临时例外 | `com.apple.security.temporary-exception.apple-events` → `com.apple.Notes` | 在沙盒中读取当前 Notes 笔记 | 不在 Portal 注册；提交时需解释，存在审核风险 |
| App Groups | `com.apple.security.application-groups` | 主 App 与 Share Extension 交换本地内容 | 需要注册并分配 |

当前版本不需要申请 iCloud、CloudKit、推送通知、Sign in with Apple、Apple Pay、HealthKit、相机、麦克风或通讯录权限。除非产品需求改变，否则不要开启无关能力。

## 三、证书与签名

建议优先使用 Xcode 的 **Automatically manage signing**，选择你的 Team，让 Xcode 创建或维护 profiles。需要保留以下签名能力：

- [ ] `Apple Development`：正式 Team 下的开发与本机验证。
- [ ] `Apple Distribution`（或 Apple 当前为该工作流提供的 Mac App Store 发行证书）：Archive 并上传 App Store Connect。
- [ ] 主 App 与 Share Extension 均使用同一个 Team 签名，并各自匹配自己的 App ID。
- [ ] 检查 Archive 中嵌入的 Share Extension 也被正确签名，且 App Group entitlement 一致。

只有启用官网直装备用路线时才需要：

- [ ] `Developer ID Application`：签名 App Store 之外分发的 `.app`。
- [ ] `Developer ID Installer`：仅在使用签名 `.pkg` 安装包时需要。
- [ ] App Store Connect API Key 或 app-specific password：仅在实际自动化上传/公证流程需要时创建，遵循最小权限。

证书私钥应留在你的 macOS 钥匙串或受控 CI 密钥库中。不要通过聊天发送 `.p12`、私钥、API Key 或证书密码；只需把证书正确安装到用于构建的 Mac，并在 Xcode 中选择 Team。

## 四、App Store Connect 需要开通

### 1. 创建 App 记录

- [ ] 平台选择 macOS。
- [ ] Bundle ID 选择 `com.youwin.NotesSidecar`。
- [ ] 填写 App 名称、主语言和内部 SKU。SKU 创建后不能修改。
- [ ] 填写分类、年龄分级、版权、支持 URL、隐私政策 URL、描述、关键词和截图。
- [ ] 完成 App Privacy 问卷。必须如实说明：本 App 不提供开发者后台；模型请求直接发往用户配置的第三方服务商。

Share Extension 不单独创建 App Store Connect App 记录，它随主 App 一起上传和审核。

### 2. 开通收费

如果采用付费下载或 App 内购买：

- [ ] 由 Account Holder 在 App Store Connect 的 Business 中签署 **Paid Apps Agreement**。
- [ ] 填写银行账户和收款币种信息。
- [ ] 填写 Apple 要求的美国税表；非美国主体通常还会根据账号所在地填写相应税务资料。
- [ ] 等协议、银行和税务状态变为有效。
- [ ] 设置 App 价格、销售地区和正确的税务分类。

如果 V1 采用“免费下载 + 一次性 Pro 解锁”，还需要：

- [ ] 在 App Store Connect 创建非消耗型 In‑App Purchase 产品。
- [ ] 确定永久不变的产品 ID。
- [ ] 填写产品显示名称、描述、价格、审核截图和审核备注。
- [ ] 在 Xcode target 中启用 In‑App Purchase capability。
- [ ] 用真实 StoreKit Sandbox 与 TestFlight 验证购买、取消、恢复购买、退款/撤销与离线权益。

如果 V1 采用“付费下载”，不需要创建 IAP 产品，工程量最低。

### 3. TestFlight 与审核

- [ ] 用正式 Team 签名生成 Archive 并上传 App Store Connect。
- [ ] 在 TestFlight 安装到干净 macOS 用户或另一台 Mac，验证首次运行。
- [ ] 验证首次控制 Notes 的系统授权弹窗、拒绝路径、重新开启路径和切换笔记自动同步。
- [ ] 验证 Keychain 在相同正式签名身份下不会反复要求“始终允许”。
- [ ] 验证 Notes Share Extension 出现在系统分享菜单，并能把文本交给主 App。
- [ ] 准备 Notes 自动化操作视频和逐步审核说明。
- [ ] 在 App Sandbox entitlement 用途说明中解释 Notes 临时 Apple Events 例外：只访问 `com.apple.Notes`，只在用户触发读取/自动同步时运行，不扫描其他 App。
- [ ] 最好先向 Feedback Assistant 提交 Notes 沙盒自动化反馈并保存编号，审核说明中附上该编号。
- [ ] 提供一个不依赖开发者后台的审核路径：审核员只需在 Notes 建立测试笔记，并配置其可用的模型 API Key；也可说明哪些界面无需 Key 即可检查。

## 五、macOS 系统权限不是 Developer Portal 能力

以下权限由每位用户在自己的 Mac 上授予，不能由开发者账号预先代替用户开通：

- **自动化 → Notes：**首次通过 Apple Events 读取 Notes 时由 macOS 提示。App 内需要提供“重新检查/打开系统设置”的恢复入口。
- **辅助功能：**仅在启用“跟随 Notes 窗口”时需要，用于读取 Notes 窗口位置；核心读取与对话不应依赖它。
- **钥匙串访问：**API Key 只保存在本机 Keychain。正式发布必须保持 Bundle ID、Team 和 designated requirement 稳定，避免每次更新重新弹窗。

这些权限应在用户触发相应功能时再请求，不应在首次启动时一次性全部索取。

## 六、当前不需要你开通的项目

- 不需要租用服务器、数据库、域名 API 或云函数来完成基本对话。
- 不需要把用户的模型 API Key 上传给开发者。
- 不需要 APNs 推送证书。
- 不需要 iCloud/CloudKit 容器。
- 不需要 Apple Pay Merchant ID。App Store 收费使用 StoreKit/商店结算，不是 Apple Pay capability。
- 不需要为 Notes.app 单独注册一个标识符；它的系统 Bundle ID 是 `com.apple.Notes`。

## 七、交给开发环境时只需提供什么

加入 Developer Program 后，安全的协作方式是：

1. 在这台 Mac 的 Xcode 中登录你的 Apple Account。
2. 在工程 Signing & Capabilities 中选择你的 Team，或把 Team ID 告诉我用于更新非秘密配置。
3. 在 Developer Portal 注册本文列出的两个 App ID 和一个 App Group；也可以授权 Xcode 自动创建。
4. 证书和私钥留在本机钥匙串，不要导出给聊天。
5. 完成后让我运行签名、entitlement、Archive、TestFlight 前检查和干净安装验收。

## 八、最终核对表

```text
Apple Developer Program 已生效
├─ App ID: com.youwin.NotesSidecar
│  └─ App Groups → group.com.youwin.NotesSidecar
├─ App ID: com.youwin.NotesSidecar.ShareExtension
│  └─ App Groups → group.com.youwin.NotesSidecar
├─ 发行证书与两个 target 的 provisioning profiles
└─ App Store Connect
   ├─ macOS App 记录
   ├─ Paid Apps Agreement
   ├─ 银行与税务信息
   ├─ 定价或一次性 IAP
   ├─ App Privacy、隐私政策和支持页面
   └─ TestFlight、Notes 权限说明与 App Review
```

## 官方参考

- Apple：[注册 Explicit App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- Apple：[注册 App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group/)
- Apple：[为 App ID 启用 App Groups 等能力](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
- Apple：[证书类型说明](https://developer.apple.com/help/account/create-certificates/certificates-overview)
- Apple：[创建 App Store Connect App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
- Apple：[签署 Paid Apps Agreement](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/)
- Apple：[填写税务信息](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information)
- Apple：[配置 In-App Purchase](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/)

> 本文是工程和发布操作清单，不替代法律或税务意见。账号注册、收款主体、税表与销售地区应以申请时 Apple 显示的最新要求为准。
