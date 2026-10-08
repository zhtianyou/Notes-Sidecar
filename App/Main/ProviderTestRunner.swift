import Foundation
import SwiftUI

/// 提供商连接测试和实时模型目录读取。
/// 不维护任何 Provider 的静态模型名单；成功响应中的模型 ID 才能进入 UI。
/// 用 actor 隔离 + 闭包回调把结果送到 UI 线程。
public enum ProviderTestRunner {

    public struct Result: Sendable {
        public let statusLabel: String      // 给 UI 显示
        public let httpStatus: Int?         // 给 UI 判断红/绿
        public let models: [String]         // 解析自 /models data[] 字段
        public let rawError: String?        // 给 log 用

        public init(statusLabel: String, httpStatus: Int? = nil, models: [String] = [], rawError: String? = nil) {
            self.statusLabel = statusLabel
            self.httpStatus = httpStatus
            self.models = models
            self.rawError = rawError
        }
    }

    /// 跑一次 GET 测试，并把模型列表一并返回（成功后从 /models 响应里取）。
    /// 通过 `into` 回调把 Result 送回（通常 @MainActor）。
    public static func runTest(
        profile: ProviderProfile,
        key: String,
        into: @escaping @Sendable (Result) -> Void
    ) async {
        let effectiveKey = await resolvedKey(profile: profile, draft: key)
        var urlStr = profile.baseURL.trimmingCharacters(in: .whitespaces)
        if urlStr.hasSuffix("/") { urlStr.removeLast() }
        let testPath: String
        switch profile.kind {
        case .anthropic: testPath = "/v1/models"
        default:         testPath = "/models"
        }
        guard let url = URL(string: urlStr + testPath) else {
            into(Result(statusLabel: SidecarLocalizer.text("URL 格式错误", "The URL is invalid")))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !effectiveKey.isEmpty {
            switch profile.kind {
            case .anthropic:
                if usesBearerAuthentication(profile) {
                    req.setValue("Bearer \(effectiveKey)", forHTTPHeaderField: "Authorization")
                } else {
                    req.setValue(effectiveKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                }
            default:         req.setValue("Bearer \(effectiveKey)", forHTTPHeaderField: "Authorization")
            }
        }
        req.timeoutInterval = 8
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                into(Result(statusLabel: SidecarLocalizer.text("无响应", "No response"), rawError: "non-http"))
                return
            }
            let code = http.statusCode
            let detail = ProviderResponseDetail.message(from: data)
            let label: String
            switch code {
            case 200...299:
                label = SidecarLocalizer.text("连接成功 · 状态 \(code)", "Connected · Status \(code)")
            case 401, 403:
                label = withProviderDetail(
                    SidecarLocalizer.text("鉴权失败 · \(code)", "Authentication failed · \(code)"),
                    detail
                )
            case 429:
                label = withProviderDetail(
                    SidecarLocalizer.text("速率限制 · \(code)", "Rate limited · \(code)"),
                    detail
                )
            default:
                label = withProviderDetail(
                    SidecarLocalizer.text("异常状态 · \(code)", "Unexpected status · \(code)"),
                    detail
                )
            }
            // 解析模型列表：OpenAI 风格 {"data":[{"id":"..."}, ...]}；
            // 有些 provider 会把 data 嵌在 result 里、或者直接返回数组，宽松解析。
            var models: [String] = []
            if (200..<300).contains(code) {
                models = await modelsForSuccessfulConnection(profile: profile, providerData: data)
            }
            into(Result(statusLabel: label, httpStatus: code, models: models, rawError: detail.isEmpty ? nil : detail))
        } catch {
            into(Result(
                statusLabel: SidecarLocalizer.text("网络失败，请检查网络后重试", "Network failure. Check your connection and try again."),
                rawError: String(describing: error)
            ))
        }
    }

    /// 仅拉模型列表（不更新 UI 状态，只返回 [String]）。
    public static func fetchModelsAsync(
        profile: ProviderProfile,
        key: String
    ) async -> [String] {
        var urlStr = profile.baseURL.trimmingCharacters(in: .whitespaces)
        if urlStr.hasSuffix("/") { urlStr.removeLast() }
        let testPath: String
        switch profile.kind {
        case .anthropic: testPath = "/v1/models"
        default:         testPath = "/models"
        }
        guard let url = URL(string: urlStr + testPath) else { return [] }
        let effectiveKey = await resolvedKey(profile: profile, draft: key)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !effectiveKey.isEmpty {
            switch profile.kind {
            case .anthropic:
                if usesBearerAuthentication(profile) {
                    req.setValue("Bearer \(effectiveKey)", forHTTPHeaderField: "Authorization")
                } else {
                    req.setValue(effectiveKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                }
            default:         req.setValue("Bearer \(effectiveKey)", forHTTPHeaderField: "Authorization")
            }
        }
        req.timeoutInterval = 8
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return await modelsForSuccessfulConnection(profile: profile, providerData: data)
        } catch {
            return []
        }
    }

    /// 仅拉模型列表（回调版本，保留给未来非 async 调用）。
    public static func fetchModels(
        profile: ProviderProfile,
        key: String,
        into: @escaping @Sendable ([String]) -> Void
    ) async {
        let models = await fetchModelsAsync(profile: profile, key: key)
        into(models)
    }

    private static func resolvedKey(profile: ProviderProfile, draft: String) async -> String {
        if profile.preset == ProviderPreset.openai.rawValue,
           profile.authenticationMode == .chatGPTSubscription {
            return (try? await OpenAIChatGPTAuth.shared.accessToken(profile: profile)) ?? ""
        }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return (try? await KeychainStore.shared.readString(ref: profile.keychainCredentialRef)) ?? ""
    }

    /// MiniMax exposes an Anthropic-compatible request shape but authenticates
    /// with `Authorization: Bearer`, unlike Anthropic's `x-api-key` header.
    private static func usesBearerAuthentication(_ profile: ProviderProfile) -> Bool {
        profile.preset == ProviderPreset.minimax.rawValue ||
            profile.preset == ProviderPreset.minimaxGlobal.rawValue
    }

    private static func withProviderDetail(_ prefix: String, _ detail: String) -> String {
        detail.isEmpty ? prefix : "\(prefix) · \(detail)"
    }

    private static func modelsForSuccessfulConnection(profile: ProviderProfile, providerData: Data) async -> [String] {
        if profile.preset == ProviderPreset.openai.rawValue,
           profile.authenticationMode == .chatGPTSubscription {
            return parseChatGPTSubscriptionModels(data: providerData)
        }
        return parseModels(data: providerData, kind: profile.kind)
    }

    /// Sign in with ChatGPT uses an account-specific catalog shaped as
    /// `{ "models": [{ "slug", "display_name", "visibility" }] }` rather
    /// than the public API's `{ "data": [{ "id" }] }` response. `slug` is
    /// the value accepted by Responses; fields such as `priority` are metadata,
    /// never a model identifier.
    private static func parseChatGPTSubscriptionModels(data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else {
            return []
        }
        var seen = Set<String>()
        return models.compactMap { model in
            guard model["visibility"] as? String == "list",
                  let slug = model["slug"] as? String,
                  !slug.isEmpty,
                  seen.insert(slug).inserted else { return nil }
            return slug
        }
    }

    /// 解析 /models 响应。宽松处理多种 JSON 形态。
    private static func parseModels(data: Data, kind: ProviderKind) -> [String] {
        // 优先尝试 JSON
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let dict = obj as? [String: Any] {
                if let arr = dict["data"] as? [[String: Any]] {
                    let ids = arr.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
                    if !ids.isEmpty { return Array(NSOrderedSet(array: ids).array as! [String]) }
                }
                if let arr = dict["models"] as? [[String: Any]] {
                    let ids = arr.compactMap { $0["id"] as? String ?? $0["name"] as? String }.filter { !$0.isEmpty }
                    if !ids.isEmpty { return Array(NSOrderedSet(array: ids).array as! [String]) }
                }
            } else if let arr = obj as? [[String: Any]] {
                let ids = arr.compactMap { $0["id"] as? String ?? $0["name"] as? String }.filter { !$0.isEmpty }
                if !ids.isEmpty { return Array(NSOrderedSet(array: ids).array as! [String]) }
            }
        }
        // Anthropic 直接返回 {data:[{id,display_name}]}
        if let s = String(data: data, encoding: .utf8) {
            // 退而求其次：扫 "id":"..." 字段
            var ids: [String] = []
            let scanner = Scanner(string: s)
            while !scanner.isAtEnd {
                _ = scanner.scanUpToString("\"id\"")
                if scanner.scanString("\"id\"") != nil {
                    _ = scanner.scanString(":")
                    if let quoted = scanner.scanUpToString(",") {
                        let trimmed = quoted.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t\"{}"))
                        if !trimmed.isEmpty { ids.append(trimmed) }
                    }
                }
            }
            if !ids.isEmpty { return Array(NSOrderedSet(array: ids).array as! [String]) }
        }
        return []
    }
}
