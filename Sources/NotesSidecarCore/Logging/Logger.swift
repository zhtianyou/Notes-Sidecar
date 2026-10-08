import Foundation
import OSLog

public actor SidecarLogger {
    public static let shared = SidecarLogger()
    private let os: Logger

    public init(subsystem: String = "com.youwin.NotesSidecar", category: String = "core") {
        self.os = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) { os.info("\(message, privacy: .public)") }
    public func debug(_ message: String) { os.debug("\(message, privacy: .public)") }
    public func warn(_ message: String) { os.warning("\(message, privacy: .public)") }
    public func error(_ message: String) { os.error("\(message, privacy: .public)") }

    /// 任何写日志的接口都必须经这里走一道；脱敏是必经步骤。
    public func safe(_ message: String) {
        let redacted = Redactor.shared.truncateBody(message)
        os.info("\(redacted, privacy: .public)")
    }
}