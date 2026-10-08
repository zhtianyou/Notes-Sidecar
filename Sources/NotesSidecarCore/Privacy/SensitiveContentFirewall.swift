import Foundation
import CryptoKit

/// 隐私硬隔离：单一强制出口。覆盖正文、用户输入、历史消息、提示词，
/// 以及只在本机生成的图片 OCR / Vision 描述；图片原始字节不进入该出口。
/// 关键规则：**Fail closed** —— 扫描超时、崩溃或规则未加载时，禁止发起远程请求。
public actor SensitiveContentFirewall {
    public static let shared = SensitiveContentFirewall()
    public static let policyVersion = "firewall.v4.line-level-private-content"

    private var loaded = false
    private let redactor = Redactor.shared

    private init() {}

    public struct Finding: Sendable, Hashable {
        public let kind: Kind
        public let source: SafeContext.SafeSourceKind
        public let redactedSample: String

        public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
            case bearerToken
            case openAIStyleKey
            case anthropicStyleKey
            case privateKeyBlock
            case apiKeyAssignment
            case recoveryCode
            case otpCode
            case passwordProximity
            case databaseConnectionString
            case awsAccessKey
            case githubToken
            case jwtToken
            case personName
            case emailAddress
            case phoneNumber
            case nationalId
            case bankCardNumber
            case preciseAddress

            public var displayName: String {
                switch self {
                case .bearerToken:             return "Bearer Token"
                case .openAIStyleKey:          return "OpenAI-style Key"
                case .anthropicStyleKey:        return "Anthropic-style Key"
                case .privateKeyBlock:         return SidecarLocalizer.text("私钥块", "Private key block")
                case .apiKeyAssignment:        return SidecarLocalizer.text("API Key 赋值", "API key assignment")
                case .recoveryCode:             return SidecarLocalizer.text("恢复码", "Recovery code")
                case .otpCode:                  return SidecarLocalizer.text("一次性验证码", "One-time passcode")
                case .passwordProximity:        return SidecarLocalizer.text("用户名+密码邻近", "Username and password together")
                case .databaseConnectionString: return SidecarLocalizer.text("数据库/云连接串", "Database or cloud connection string")
                case .awsAccessKey:            return "AWS Access Key"
                case .githubToken:             return "GitHub Token"
                case .jwtToken:                return "JWT"
                case .personName:              return SidecarLocalizer.text("姓名", "Name")
                case .emailAddress:            return SidecarLocalizer.text("邮箱", "Email address")
                case .phoneNumber:             return SidecarLocalizer.text("电话号码", "Phone number")
                case .nationalId:              return SidecarLocalizer.text("证件号码", "Government ID number")
                case .bankCardNumber:          return SidecarLocalizer.text("银行卡号", "Bank card number")
                case .preciseAddress:           return SidecarLocalizer.text("详细地址", "Detailed address")
                }
            }
        }
    }

    public struct Evaluation: Sendable {
        public let status: SafeContext
        public let findings: [Finding]
        public let failedClosed: Bool
    }

    public struct ImageOCREvaluation: Sendable, Hashable {
        public let safeText: String
        public let findings: [Finding]
        public let excludedLineCount: Int
        public let failedClosed: Bool

        public var containsPrivateContent: Bool { !findings.isEmpty || failedClosed }
    }

    /// 加载（可被外部驱动）。MVP 同步完成，规则都是确定性 NSRegularExpression / substring。
    public func load() {
        loaded = true
    }

    public func isReady() -> Bool { loaded }

    /// 主入口：从候选字段构造 SafeContext。命中行被排除，来源内其余安全行可继续使用；
    /// 扫描抛错或未加载 → 整张 SafeContext 走 protected/scanFailedClosed，不允许后续出站。
    public func evaluate(noteText: String,
                         userQuestion: String,
                         conversationSummary: String,
                         imageText: String = "",
                         audioTranscript: String = "",
                         requestId: String) -> Evaluation {
        guard loaded else { return failClosed(requestId: requestId) }

        let sources: [(SafeContext.SafeSourceKind, String)] = [
            (.noteText, noteText),
            (.userQuestion, userQuestion),
            (.previousTurns, conversationSummary),
            (.ocrText, imageText),
            (.audioTranscript, audioTranscript)
        ]

        var included: [(SafeContext.SafeSourceKind, String)] = []
        var findings: [Finding] = []
        var excluded: Set<SafeContext.SafeSourceKind> = []

        for (kind, text) in sources {
            guard !text.isEmpty else { continue }
            let sanitized = sanitizeLines(text, source: kind)
            findings.append(contentsOf: sanitized.findings)
            if sanitized.safeText.isEmpty {
                excluded.insert(kind)
            } else {
                included.append((kind, sanitized.safeText))
            }
        }

        let safe = SafeContext(
            noteTextSnapshot: included.first(where: { $0.0 == .noteText })?.1 ?? "",
            userQuestion:     included.first(where: { $0.0 == .userQuestion })?.1 ?? "",
            conversationSummary: included.first(where: { $0.0 == .previousTurns })?.1 ?? "",
            imageTextSnapshot: included.first(where: { $0.0 == .ocrText })?.1 ?? "",
            audioTranscriptSnapshot: included.first(where: { $0.0 == .audioTranscript })?.1 ?? "",
            sourceKinds: Set(included.map { $0.0 }),
            protectedReason: excluded.isEmpty ? nil : .credentialDetected
        )

        return Evaluation(status: safe, findings: findings, failedClosed: false)
    }

    /// 给 URL 用的最小过滤（Phase 2 会扩展）。MVP：检查 query 中是否含常见 token 名。
    public func isExcluded(_ url: URL) -> URL? {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let comps = comps else { return nil }
        if let items = comps.queryItems {
            for it in items {
                let lower = it.name.lowercased()
                let suspectNames = ["token", "api_key", "apikey", "secret", "session", "code", "auth"]
                if suspectNames.contains(where: { lower.contains($0) }), let v = it.value, !v.isEmpty {
                    var s = comps
                    s.queryItems = items.filter { $0.name != it.name }
                    return s.url ?? url
                }
            }
        }
        return url
    }

    /// 图片 OCR 的本地隐私门。按行排除敏感片段，只返回可进入远程上下文的文字；
    /// 原始 OCR 和图片字节永远不属于返回值。规则未加载时 fail closed。
    public func evaluateImageOCR(_ recognizedText: String) -> ImageOCREvaluation {
        guard loaded else {
            return ImageOCREvaluation(safeText: "", findings: [], excludedLineCount: 0, failedClosed: true)
        }

        var safeLines: [String] = []
        var findings: [Finding] = []
        var excluded = 0

        for rawLine in recognizedText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let kinds = scan(text: line) + scanPersonalInformation(text: line)
            var seen = Set<Finding.Kind>()
            let uniqueKinds = kinds.filter { seen.insert($0).inserted }
            if uniqueKinds.isEmpty {
                safeLines.append(line)
            } else {
                excluded += 1
                findings.append(contentsOf: uniqueKinds.map {
                    Finding(kind: $0, source: .ocrText, redactedSample: "•••")
                })
            }
        }

        return ImageOCREvaluation(
            safeText: safeLines.joined(separator: "\n"),
            findings: findings,
            excludedLineCount: excluded,
            failedClosed: false
        )
    }

    /// Audio is represented as timestamped lines; a sensitive timestamped
    /// segment is removed while unrelated segments remain available locally.
    public func evaluateAudioTranscript(_ transcript: String) -> ImageOCREvaluation {
        guard loaded else {
            return ImageOCREvaluation(safeText: "", findings: [], excludedLineCount: 0, failedClosed: true)
        }
        let sanitized = sanitizeLines(transcript, source: .audioTranscript)
        let lineCount = transcript.split(whereSeparator: \.isNewline).count
        let safeCount = sanitized.safeText.split(whereSeparator: \.isNewline).count
        return ImageOCREvaluation(
            safeText: sanitized.safeText,
            findings: sanitized.findings,
            excludedLineCount: max(0, lineCount - safeCount),
            failedClosed: false
        )
    }

    // MARK: - 私有

    private func scan(text: String) -> [Finding.Kind] {
        guard !text.isEmpty else { return [] }
        let t = text.lowercased()

        // 规则采用确定性匹配，规则都注释清楚。规则可被 canary 测试验证。
        var hits: [Finding.Kind] = []

        if t.contains("bearer ") { hits.append(.bearerToken) }
        if t.range(of: #"sk-[a-z0-9_-]{20,}"#, options: .regularExpression) != nil { hits.append(.openAIStyleKey) }
        if t.range(of: #"sk-ant-[a-z0-9_-]{10,}"#, options: .regularExpression) != nil { hits.append(.anthropicStyleKey) }
        if t.range(of: #"-----begin [a-z ]*private key-----"#, options: .regularExpression) != nil { hits.append(.privateKeyBlock) }
        // Credential assignments are commonly pasted without quotes (for example
        // `App Secret: ...` in Notes). Match the field/value shape, not the bare
        // word "token", so titles such as "token 权限设计" remain safe.
        let credentialField = #"(?:api[ _-]?key|apikey|app[ _-]?(?:id|secret)|client[ _-]?(?:id|secret)|access[ _-]?token|refresh[ _-]?token|tenant[ _-]?access[ _-]?token|app[ _-]?access[ _-]?token|id[ _-]?token|secret|token)"#
        let credentialValue = #"['"]?[a-z0-9][a-z0-9_./+\-=]{11,}['"]?"#
        if t.range(of: credentialField + #"\s*[:：=]\s*"# + credentialValue, options: .regularExpression) != nil {
            hits.append(.apiKeyAssignment)
        }
        if t.range(of: #"\b(?:[a-z0-9]{4}-){4,}[a-z0-9]{4}\b"#, options: .regularExpression) != nil { hits.append(.recoveryCode) }
        if t.range(of: #"\b\d{6}\b"#, options: .regularExpression) != nil && t.contains("验证码") { hits.append(.otpCode) }
        if t.range(of: #"(用户名|账号|邮箱|username|email)\s*[:：]?\s*\S+.{0,40}(密码|password|口令|pin)"#, options: .regularExpression) != nil { hits.append(.passwordProximity) }
        if t.range(of: #"(postgres|mysql|mongodb(\+srv)?|redis|amqp)://[^\s]+"#) != nil { hits.append(.databaseConnectionString) }
        if t.range(of: #"akia[0-9a-z]{16}"#, options: .regularExpression) != nil { hits.append(.awsAccessKey) }
        if t.range(of: #"ghp_[a-z0-9]{20,}"#, options: .regularExpression) != nil { hits.append(.githubToken) }
        if t.range(of: #"eyj[a-z0-9_-]+\.eyj[a-z0-9_-]+\.[a-z0-9_-]+"#, options: .regularExpression) != nil { hits.append(.jwtToken) }

        // 去重保留命中顺序
        var seen: Set<Finding.Kind> = []
        return hits.filter { seen.insert($0).inserted }
    }

    private func sanitizeLines(_ text: String, source: SafeContext.SafeSourceKind) -> (safeText: String, findings: [Finding]) {
        var safeLines: [String] = []
        var findings: [Finding] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            var seen = Set<Finding.Kind>()
            let kinds = (scan(text: line) + scanPersonalInformation(text: line))
                .filter { seen.insert($0).inserted }
            if kinds.isEmpty {
                safeLines.append(line)
            } else {
                findings.append(contentsOf: kinds.map { Finding(kind: $0, source: source, redactedSample: "•••") })
            }
        }
        return (safeLines.joined(separator: "\n"), findings)
    }

    private func scanPersonalInformation(text: String) -> [Finding.Kind] {
        let lower = text.lowercased()
        var hits: [Finding.Kind] = []
        if lower.range(of: #"\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b"#, options: .regularExpression) != nil {
            hits.append(.emailAddress)
        }
        if lower.range(of: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#, options: .regularExpression) != nil ||
            lower.range(of: #"(?<!\d)0\d{2,3}[- ]?\d{7,8}(?!\d)"#, options: .regularExpression) != nil {
            hits.append(.phoneNumber)
        }
        if lower.range(of: #"(?<!\d)\d{17}[0-9x](?!\d)"#, options: .regularExpression) != nil {
            hits.append(.nationalId)
        }
        let digitsOnly = text.filter(\.isNumber)
        if (16...19).contains(digitsOnly.count), text.rangeOfCharacter(from: .decimalDigits) != nil {
            hits.append(.bankCardNumber)
        }
        if lower.range(of: #"(?:姓名|name)\s*[:：]\s*\S+"#, options: .regularExpression) != nil {
            hits.append(.personName)
        }
        // A field name such as `[手机号]` plus a formula literal `1` used to
        // look like "号 + number" and was wrongly classified as an address.
        // Require address-specific structure instead. Formula/schema syntax is
        // not a personal address, but actual phone, email, ID and key rules
        // above remain active for every kind of text.
        let looksLikeFormulaOrSchema =
            text.range(of: #"\[[^\]]+\]"#, options: .regularExpression) != nil &&
            lower.range(of: #"\b(?:fixed|sum|count|countd|if|then|else)\b"#, options: .regularExpression) != nil
        let hasExplicitAddressLabel = lower.range(of: #"(?:地址|住址|address)\s*[:：]\s*\S+"#, options: .regularExpression) != nil
        let hasStructuredAddress = lower.range(
            of: #"(?:省|市|区|县).{0,24}(?:路|街|巷).{0,24}\d+(?:号|室)?|(?:路|街|巷)\s*\d+(?:号|室)"#,
            options: .regularExpression
        ) != nil
        if hasExplicitAddressLabel || (!looksLikeFormulaOrSchema && hasStructuredAddress) {
            hits.append(.preciseAddress)
        }
        return hits
    }

    private func hash(_ s: String) -> String {
        let d = SHA256.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private func failClosed(requestId: String) -> Evaluation {
        let empty = SafeContext(
            noteTextSnapshot: "", userQuestion: "", conversationSummary: "",
            sourceKinds: [], protectedReason: .scanFailedClosed
        )
        return Evaluation(status: empty, findings: [], failedClosed: true)
    }
}
