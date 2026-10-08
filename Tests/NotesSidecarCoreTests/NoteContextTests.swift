import XCTest
@testable import NotesSidecar

final class NoteContextTests: XCTestCase {
    func testAutomaticInterfaceLanguageUsesOnlySimplifiedChineseSystems() {
        XCTAssertEqual(
            AppModel.InterfaceLanguage.automatic.resolvedIdentifier(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppModel.InterfaceLanguage.automatic.resolvedIdentifier(preferredLanguages: ["zh-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppModel.InterfaceLanguage.automatic.resolvedIdentifier(preferredLanguages: ["zh-Hant-TW"]),
            "en"
        )
        XCTAssertEqual(
            AppModel.InterfaceLanguage.automatic.resolvedIdentifier(preferredLanguages: ["ja-JP"]),
            "en"
        )
        XCTAssertEqual(
            AppModel.InterfaceLanguage.automatic.resolvedIdentifier(preferredLanguages: []),
            "en"
        )
    }

    func testExplicitInterfaceLanguageOverridesSystemLanguage() {
        XCTAssertEqual(
            AppModel.InterfaceLanguage.english.resolvedIdentifier(preferredLanguages: ["zh-Hans"]),
            "en"
        )
        XCTAssertEqual(
            AppModel.InterfaceLanguage.simplifiedChinese.resolvedIdentifier(preferredLanguages: ["en-US"]),
            "zh-Hans"
        )
    }

    func testReadCurrentScriptDereferencesNotesSelectionDirectly() {
        let source = AppleScriptBridge.readCurrentScript(timeoutSeconds: 6)

        XCTAssertTrue(source.contains("first item of (get selection)"))
        XCTAssertFalse(source.contains("item 1 of nList"))
    }

    func testHash_isStableForSamePlaintext() {
        let a = NoteContext.hash(plaintext: "hello world")
        let b = NoteContext.hash(plaintext: "hello world")
        XCTAssertEqual(a, b)
        let c = NoteContext.hash(plaintext: "hello world!")
        XCTAssertNotEqual(a, c)
    }

    func testHash_isHexOfLength32() {
        let h = NoteContext.hash(plaintext: "anything")
        XCTAssertEqual(h.count, 32)
        XCTAssertTrue(h.allSatisfy { $0.isHexDigit })
    }

    func testSlashCommand_matchesFirst() {
        XCTAssertEqual(SlashCommand.match("/summary 测试"), SlashCommand.all.first { $0.id == "summary" })
        XCTAssertEqual(SlashCommand.match("/translate to en"), SlashCommand.all.first { $0.id == "translate" })
        XCTAssertNil(SlashCommand.match("普通问句"))
    }
}
