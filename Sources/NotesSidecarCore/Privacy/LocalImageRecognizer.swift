import Foundation
import ImageIO
import Vision
import Speech
import AVFoundation

public enum LocalAudioTranscriptionError: LocalizedError, Sendable {
    case permissionDenied, recognizerUnavailable, onDeviceRecognitionUnavailable, noSpeechDetected
    public var errorDescription: String? { switch self { case .permissionDenied: return "Speech Recognition permission was not granted"; case .recognizerUnavailable: return "On-device speech recognition is unavailable for this language"; case .onDeviceRecognitionUnavailable: return "This Mac cannot transcribe this language on device"; case .noSpeechDetected: return "No recognizable speech was found in this audio" } }
}
public struct LocalAudioSegment: Sendable, Hashable { public let timestamp: TimeInterval; public let duration: TimeInterval; public let text: String }
public struct LocalAudioAnalysis: Sendable, Hashable {
    public let fileName: String; public let languageCode: String; public let duration: TimeInterval; public let safeSegments: [LocalAudioSegment]; public let privacyFindings: [SensitiveContentFirewall.Finding]; public let excludedSegmentCount: Int; public let privacyScanFailed: Bool
    public var safeText: String { safeSegments.map { "[\(LocalAudioTranscriber.timestampLabel($0.timestamp))] \($0.text)" }.joined(separator: "\n") }
    public var containsPrivateContent: Bool { !privacyFindings.isEmpty || privacyScanFailed }
}
public actor LocalAudioTranscriber {
    public static let shared = LocalAudioTranscriber()
    public func transcribe(url: URL, locale: Locale = .current) async throws -> LocalAudioAnalysis {
        let status = await authorizationStatus(); guard status == .authorized else { throw LocalAudioTranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw LocalAudioTranscriptionError.recognizerUnavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw LocalAudioTranscriptionError.onDeviceRecognitionUnavailable }
        let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
        let segments = try await recognize(recognizer: recognizer, request: request)
        let lines = segments.map { "[\(Self.timestampLabel($0.timestamp))] \($0.text)" }
        guard !lines.isEmpty else { throw LocalAudioTranscriptionError.noSpeechDetected }
        let evaluation = await SensitiveContentFirewall.shared.evaluateAudioTranscript(lines.joined(separator: "\n"))
        let safe = evaluation.safeText.components(separatedBy: .newlines).compactMap(Self.segment)
        let duration = (try? await AVURLAsset(url: url).load(.duration)).map(CMTimeGetSeconds) ?? 0
        return LocalAudioAnalysis(fileName: url.lastPathComponent, languageCode: locale.identifier, duration: max(0, duration), safeSegments: safe, privacyFindings: evaluation.findings, excludedSegmentCount: evaluation.excludedLineCount, privacyScanFailed: evaluation.failedClosed)
    }
    public nonisolated static func timestampLabel(_ seconds: TimeInterval) -> String { let s = max(0, Int(seconds)); return String(format: "%02d:%02d", s / 60, s % 60) }
    private func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus { let current = SFSpeechRecognizer.authorizationStatus(); guard current == .notDetermined else { return current }; return await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } } }
    private func recognize(recognizer: SFSpeechRecognizer, request: SFSpeechURLRecognitionRequest) async throws -> [LocalAudioSegment] { try await withCheckedThrowingContinuation { continuation in var done = false; _ = recognizer.recognitionTask(with: request) { result, error in guard !done else { return }; if let error { done = true; continuation.resume(throwing: error) } else if let result, result.isFinal { let segments = result.bestTranscription.segments.map { LocalAudioSegment(timestamp: $0.timestamp, duration: $0.duration, text: $0.substring) }; done = true; continuation.resume(returning: segments) } } } }
    private static func segment(_ line: String) -> LocalAudioSegment? { guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return nil }; let pieces = line[line.index(after: line.startIndex)..<end].split(separator: ":").compactMap { Int($0) }; let text = line[line.index(after: end)...].trimmingCharacters(in: .whitespaces); guard pieces.count == 2, !text.isEmpty else { return nil }; return .init(timestamp: TimeInterval(pieces[0] * 60 + pieces[1]), duration: 0, text: text) }
}

public enum LocalImageRecognitionError: LocalizedError, Sendable {
    case unreadableImage
    case noRecognizableContent

    public var errorDescription: String? {
        switch self {
        case .unreadableImage: return SidecarLocalizer.text("无法在本机读取这张图片", "This image could not be read locally")
        case .noRecognizableContent: return SidecarLocalizer.text("图片中没有识别到可用于对话的文字或内容", "No text or content usable for conversation was recognized in this image")
        }
    }
}

public struct LocalImageAnalysis: Sendable, Hashable {
    public let fileName: String
    public let safeText: String
    public let privacyFindings: [SensitiveContentFirewall.Finding]
    public let excludedLineCount: Int
    public let privacyScanFailed: Bool
    public let recognizedLineCount: Int

    public var containsPrivateContent: Bool { !privacyFindings.isEmpty || privacyScanFailed }
}

/// 图片仅在本机进入 ImageIO / Vision。输出只包含经过隐私门处理后的文本，
/// 类型中不保存图片 Data、URL 或原始 OCR，防止后续误传 Provider。
public actor LocalImageRecognizer {
    public static let shared = LocalImageRecognizer()

    public func analyze(url: URL) async throws -> LocalImageAnalysis {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LocalImageRecognitionError.unreadableImage
        }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]

        let classificationRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([textRequest, classificationRequest])

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let labels = (classificationRequest.results ?? [])
            .filter { $0.confidence >= 0.15 }
            .prefix(5)
            .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }

        var localDescription: [String] = []
        localDescription.append(contentsOf: lines)
        if !labels.isEmpty {
            localDescription.append(SidecarLocalizer.text("本机图像分类：", "Local image classification: ") + labels.joined(separator: ", "))
        }
        guard !localDescription.isEmpty else { throw LocalImageRecognitionError.noRecognizableContent }

        let evaluation = await SensitiveContentFirewall.shared.evaluateImageOCR(
            localDescription.joined(separator: "\n")
        )
        return LocalImageAnalysis(
            fileName: url.lastPathComponent,
            safeText: evaluation.safeText,
            privacyFindings: evaluation.findings,
            excludedLineCount: evaluation.excludedLineCount,
            privacyScanFailed: evaluation.failedClosed,
            recognizedLineCount: localDescription.count
        )
    }
}
