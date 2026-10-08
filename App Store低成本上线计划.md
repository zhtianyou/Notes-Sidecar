# Notes Sidecar：App Store 低成本上线计划

更新日期：2026-10-05

## 核心决定

在 Notes Sidecar 达到“可以提交审核”的状态之前，暂不申请 Apple Developer Program。

原因：Apple Developer Program 按年收费，目前公开价格为每年 99 美元或当地等值价格。提前申请会消耗会员有效期，却不能提前保证 App Review 一定接受 Notes 自动化权限。

项目继续完全按照 Mac App Store 标准开发。等免费条件下能够验证的事项全部通过，只剩正式签名、TestFlight 和 App Review 时，再付费申请开发者账号。

## 当前已确认的情况

- 已制作 App Store Sandbox Release 构建。
- 已启用 App Sandbox、模型服务所需的出站网络权限和 Notes Apple Events 权限。
- 已修复沙盒版读取 Notes 时的 `-10004 权限违例`。
- 沙盒版已在本机成功读取当前选中的 Notes 笔记并进入对话界面。
- 当前自动化测试共 34 项通过。
- 已加入文本/链接 Share Extension；正式共享容器仍需未来的 Apple Developer Team 注册 `group.com.youwin.NotesSidecar`。
- 已生成本机 ad-hoc 签名的 `.app` 和 `.xcarchive`，但它们不能上传 App Store Connect。
- 最大剩余审核风险是：读取 Notes 需要 `com.apple.security.temporary-exception.apple-events` 临时例外。

## 免费阶段可以完成的工作

仅使用免费 Apple Account、Xcode 和本机环境，先完成以下工作：

### 1. 完成核心产品

- [ ] Notes 当前笔记读取稳定。
- [ ] 切换笔记后 ContextCoordinator 自动同步稳定。
- [ ] MiniMax CN 只填写 API Key 即可使用。
- [ ] 模型列表和思考强度能够正确加载、刷新和保存。
- [ ] 发送消息、流式回复、中断生成和错误提示正常。
- [ ] Keychain 不再反复要求授权。
- [ ] 设置、首次引导、空状态和异常恢复流程完整。

### 2. 始终使用沙盒 Release 验证

开发阶段不能只验证非沙盒 Debug 版本。每个涉及 Notes、文件、网络、Keychain 或进程调用的改动，都要运行：

```bash
scripts/verify_app_store_sandbox.sh
```

并实际启动产物：

```text
.build/app-store-sandbox/Build/Products/Release/NotesSidecar.app
```

### 3. 做干净环境测试

- [ ] 在新的 macOS 用户账户中验证首次启动。
- [ ] 如果条件允许，在另一台 Mac 上验证。
- [ ] 验证第一次控制 Notes 时的系统授权弹窗。
- [ ] 验证允许、拒绝、之后重新开启权限三种路径。
- [ ] 验证全新 Keychain、没有 Provider 配置和 Notes 未运行的情况。
- [ ] 检查 Console 中是否存在 sandbox deny 或崩溃日志。

### 4. 免费完成 StoreKit 开发

在 Xcode 中创建本地 StoreKit Configuration，模拟一次性购买，无需先创建 App Store Connect 商品。

- [ ] 确定收费方式：优先考虑一次性购买或一次性 Pro 解锁。
- [ ] 实现购买按钮。
- [ ] 实现恢复购买。
- [ ] 实现本地交易验证和权益缓存。
- [ ] 模拟购买成功、取消、失败、退款和撤销。
- [ ] App Store 构建中不得出现许可证密钥、自定义支付或第三方购买入口。

正式产品 ID、真实 Sandbox 购买和 TestFlight 测试需要付费会员，留到最后阶段完成。

### 5. 提前准备审核材料

- [ ] App 名称、副标题、描述和关键词。
- [ ] App 图标和商店截图。
- [ ] 隐私政策与支持页面。
- [ ] 数据收集与隐私问卷答案。
- [ ] 审核演示账号或无需账号的测试方式。
- [ ] Notes 自动化操作视频和逐步说明。
- [ ] 明确说明笔记内容只在本机处理；仅在用户发送时传给其自行配置的模型服务商。
- [ ] 解释 API Key 只存入本机 Keychain。

### 6. 免费降低 Apple Events 审核风险

Notes 的脚本字典没有为“读取当前选中笔记”提供足够的 scripting access group，因此当前实现需要临时 Apple Events 例外。这是无法仅凭本机测试完全消除的风险。

付费申请前可以先做：

1. 准备一个只保留“读取当前 Notes 笔记”功能的最小复现工程。
2. 通过免费的 Feedback Assistant 提交功能请求或兼容性反馈。
3. 保存 Feedback 编号、提交内容和 Apple 的回复。
4. 在 Apple Developer Forums 发布技术问题，询问这种最小权限用例的实践。
5. 在未来 App Store Connect 的 App Sandbox Entitlement Usage Information 中填写 Feedback 编号，并解释临时例外的必要性。

论坛或 Feedback 回复只能降低不确定性，不等于 App Review 的预先批准。

## 什么时候才申请付费开发者账号

以下条件全部满足后再申请：

- [ ] 沙盒版核心功能全部可用。
- [ ] 至少两个干净环境完成验收。
- [ ] 不再出现 `-10004`、反复权限提示或 Keychain 反复弹窗。
- [ ] 没有会阻断使用的 sandbox deny。
- [ ] 本地 StoreKit 一次性购买流程完整通过。
- [ ] 隐私政策、支持页面、截图和审核说明已准备好。
- [ ] Apple Events 临时例外已有清晰理由和 Feedback 编号。
- [ ] Developer ID + 公证 + 第三方许可证的备用方案已有设计，确保审核失败也能发布。

此时项目应处于“除了 Apple 的正式签名与人工审核，其余都已准备完成”的状态。

## 付费后的集中执行顺序

```text
申请 Apple Developer Program
        ↓
配置 Team、App ID、正式证书和 Provisioning Profile
        ↓
创建 App Store Connect 应用与一次性购买商品
        ↓
使用正式签名生成 Archive
        ↓
上传 TestFlight，验证全新安装和真实 StoreKit Sandbox
        ↓
填写临时 entitlement 使用说明和 Feedback 编号
        ↓
提交 App Review
        ↓
通过：在 App Store 销售
拒绝：沟通、修改或申诉；必要时启用官网直装方案
```

## 必须接受的剩余不确定性

免费阶段可以证明产品在 App Sandbox 中技术上运行，但无法证明 Apple 审核团队一定接受 Notes 的临时 Apple Events 例外。

不存在免费的、具有约束力的 App Review 预审。真正的审核结论只有加入 Apple Developer Program、上传构建并提交审核后才能获得。

因此本计划的目标不是把审核风险降为零，而是：

1. 在付费前排除所有可由工程测试发现的问题。
2. 把会员申请推迟到最接近提交审核的时间。
3. 即使审核失败，也保留 Developer ID 直装收费的商业化路线。

## 费用控制原则

- 不因“可能以后要上架”而提前开始会员计费周期。
- 不在核心功能尚未稳定时创建正式商品或准备大量营销素材。
- 先使用 Xcode 本地 StoreKit 测试替代真实内购配置。
- 账号申请后集中完成正式签名、TestFlight、审核和申诉，减少无效会员时间。
- 第一年是否续费，根据审核结果、产品完成度和实际销售情况决定。

## 官方参考

- Apple：[会员方案对比](https://developer.apple.com/support/compare-memberships/)
- Apple：[App Review](https://developer.apple.com/app-store/review/)
- Apple：[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Apple：[App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
- Apple：[App Sandbox 临时例外](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
- Apple：[TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- Apple：[代码级技术支持](https://developer.apple.com/support/technical/)

## 与其他文档的关系

- 商业发行与收费方式总览：[`上线须知.md`](./上线须知.md)
- 本文只负责回答：什么时候申请 Apple Developer Program，付费前应完成哪些验证。
