// Standalone regression harness. Compile with the application Swift sources (except main.swift).
// Uses only a temporary Rime user directory and a mock IMK client; never installs an input source.
import AppKit
import InputMethodKit
import CRime
import LOMTCore

private final class MockInputClient: NSObject, IMKTextInput {
    var text = ""
    var marked = NSRange(location: NSNotFound, length: 0)
    var selection = NSRange(location: 0, length: 0)
    var inserted: [String] = []

    private func plainText(_ value: Any) -> String {
        (value as? NSAttributedString)?.string ?? (value as? String ?? "")
    }

    private func replace(_ value: String, range: NSRange) -> NSRange {
        let effective = range.location == NSNotFound
            ? (marked.location == NSNotFound ? selection : marked) : range
        let storage = NSMutableString(string: text)
        storage.replaceCharacters(in: effective, with: value)
        text = storage as String
        let result = NSRange(location: effective.location, length: value.utf16.count)
        selection = NSRange(location: NSMaxRange(result), length: 0)
        return result
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let value = plainText(string ?? "")
        _ = replace(value, range: replacementRange)
        marked = NSRange(location: NSNotFound, length: 0)
        inserted.append(value)
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let value = plainText(string ?? "")
        // An empty marked update after a commit must not delete the current selection.
        if value.isEmpty && marked.location == NSNotFound { return }
        marked = replace(value, range: replacementRange)
        selection = NSRange(location: marked.location + selectionRange.location, length: selectionRange.length)
        if value.isEmpty { marked = NSRange(location: NSNotFound, length: 0) }
    }
    func selectedRange() -> NSRange { selection }
    func markedRange() -> NSRange { marked }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        NSAttributedString(string: (text as NSString).substring(with: range))
    }
    func length() -> Int { text.utf16.count }
    func characterIndex(for point: NSPoint, tracking mappingMode: Int, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect.pointee = NSRect(x: 200, y: 500, width: 1, height: 20)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "lo.regression.mock" }
    func windowLevel() -> Int32 { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "lo-regression-mock" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
        actualRange?.pointee = range
        return (text as NSString).substring(with: range)
    }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect {
        NSRect(x: 200, y: 500, width: 1, height: 20)
    }
}

@main
struct InputCoreRegression {
    private static var passed = 0
    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("FAIL: \(label)") }
        passed += 1
        print("PASS: \(label)")
    }

    static func main() throws {
        setbuf(stdout, nil)
        print("Preparing isolated Rime deployment")
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lo-input-regression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = RimeEngine()
        engine.initialize(sharedDataDir: workspace.appendingPathComponent("macos/LOInputMethod/Resources/rime").path, userDir: root.path)
        defer { engine.finalize() }
        let engineSession = engine.createSession()
        check(engineSession != 0, "Isolated Rime session starts")
        for scalar in "nihao".unicodeScalars {
            _ = engine.processKey(Int32(scalar.value), modifiers: 0, session: engineSession)
        }
        check(!engine.getCandidates(session: engineSession).isEmpty, "Bundled Rime dictionary returns candidates")
        _ = engine.processKey(32, modifiers: 0, session: engineSession)
        check(engine.getCommit(session: engineSession) == "你好", "Rime commits expected Chinese text")
        engine.setAsciiMode(true, session: engineSession)
        let uppercaseHandled = engine.processKey(RimeEngine.convertKeyCode(0, chars: "A"), modifiers: 1, session: engineSession)
        check(!uppercaseHandled && engine.getCommit(session: engineSession) == nil,
            "English uppercase passes through to the client without conversion")
        engine.setAsciiMode(false, session: engineSession)
        _ = engine.processKey(Int32(",".utf8.first!), modifiers: 0, session: engineSession)
        check(engine.getCommit(session: engineSession) == "，",
            "Comma on an empty document line commits Chinese punctuation")
        for scalar in "nihao".unicodeScalars {
            _ = engine.processKey(Int32(scalar.value), modifiers: 0, session: engineSession)
        }
        _ = engine.processKey(32, modifiers: 0, session: engineSession)
        check(engine.getCommit(session: engineSession) == "你好", "Chinese composition commits before punctuation")
        _ = engine.processKey(Int32(",".utf8.first!), modifiers: 0, session: engineSession)
        check(engine.getCommit(session: engineSession) == "，",
            "Comma immediately after committed Chinese is preserved")
        engine.destroySession(engineSession)
        if CommandLine.arguments.contains("--engine-only") {
            print("Input engine regression: \(passed) checks passed")
            return
        }
        print("Initializing AppKit candidate UI and Shift state checks")
        _ = NSApplication.shared
        let client = MockInputClient()
        let noMarkedText = NSRange(location: NSNotFound, length: 0)
        let collapsedSelection = NSRange(location: 0, length: 0)
        check(LOTextInsertion.replacementRange(markedRange: noMarkedText, selectedRange: collapsedSelection) == collapsedSelection,
            "Unmarked commits target the insertion point instead of NSNotFound")
        let electronAbsentMarked = NSRange(location: NSNotFound, length: NSIntegerMax)
        check(LOTextInsertion.isAbsentMarkedRange(electronAbsentMarked),
            "Electron clients report an absent marked range with NSIntegerMax length")
        check(LOTextInsertion.replacementRange(markedRange: electronAbsentMarked, selectedRange: NSRange(location: 0, length: 0))
                == NSRange(location: NSNotFound, length: 0),
            "Electron clients receive no explicit range so punctuation lands at the real caret")
        client.text = "abc\n"
        client.selection = NSRange(location: 4, length: 0)
        client.insertText("-", replacementRange: LOTextInsertion.replacementRange(
            markedRange: electronAbsentMarked, selectedRange: NSRange(location: 0, length: 0)))
        check(client.text == "abc\n-", "Symbol on an empty line in Electron clients appends at the caret, not position zero")
        // 复位客户端，后续断言依赖空文档状态
        client.text = ""
        client.selection = NSRange(location: 0, length: 0)
        let activeMarkedRange = NSRange(location: 4, length: 3)
        check(LOTextInsertion.replacementRange(markedRange: activeMarkedRange, selectedRange: collapsedSelection) == activeMarkedRange,
            "Composition commits replace the active marked range")
        client.insertText("，", replacementRange: LOTextInsertion.replacementRange(
            markedRange: noMarkedText, selectedRange: client.selectedRange()))
        check(client.text == "，", "A leading punctuation commit inserts into an empty client")
        var tap = LOShiftTapState()
        func pollTap(_ shiftDown: Bool, at time: TimeInterval, other: Bool = false, mouse: Bool = false, nonMod: Bool = false) -> Bool {
            LOShiftTapDecision.evaluate(
                shiftDown: shiftDown, now: time, state: &tap,
                otherModifiersHeld: other, mouseButtonDown: mouse,
                nonModifierKeyDown: nonMod, threshold: 0.4)
        }
        check(!pollTap(true, at: 1), "Shift down waits for release")
        check(pollTap(false, at: 1.1), "Short standalone Shift toggles")
        _ = pollTap(true, at: 2)
        check(!pollTap(true, at: 2.05, nonMod: true), "Shift letter chord marks the non-modifier key")
        check(!pollTap(false, at: 2.1), "Shift letter chord never toggles")
        _ = pollTap(true, at: 3)
        check(!pollTap(false, at: 4), "Long Shift never toggles")
        // 激活输入法时 Shift 已处于按住状态（downAt 为空）：松开不触发切换
        check(!pollTap(false, at: 5), "Shift held during activation never toggles on release")
        _ = pollTap(true, at: 6)
        _ = pollTap(true, at: 6.05, other: true)
        _ = pollTap(true, at: 6.07, other: true)
        check(!pollTap(false, at: 6.1), "Shift Command chord never toggles")
        _ = pollTap(true, at: 7)
        check(pollTap(false, at: 7.1), "Modifier fallback supports remote keyboard keyCode zero")

        let session = engine.createSession()
        defer { engine.destroySession(session) }
        func type(_ text: String) {
            engine.clearComposition(session: session)
            engine.setAsciiMode(false, session: session)
            for scalar in text.unicodeScalars {
                _ = engine.processKey(Int32(scalar.value), modifiers: 0, session: session)
            }
        }
        type("nihao")
        check(engine.getRawInput(session: session) == "nihao", "Raw preedit is available without syllable separators")
        check(engine.commitComposition(session: session) == "你好", "Explicit composition commit returns text for client delivery")
        check(!engine.isComposing(session: session), "Explicit commit clears composition")
        type("nihao")
        _ = engine.processKey(0xFF1B, modifiers: 0, session: session)
        check(!engine.isComposing(session: session) && engine.getCommit(session: session) == nil,
            "Escape cancels preedit without inserting text")
        type("nihao")
        _ = engine.processKey(0xFF08, modifiers: 0, session: session)
        check(engine.getRawInput(session: session) == "niha", "Backspace removes exactly one preedit character")
        type("ni")
        let candidates = engine.getCandidates(session: session)
        check(candidates.count > 1, "Candidate list contains multiple choices")
        let window = LOCandidateWindow()
        window.show(candidates: candidates, client: client, highlightedIndex: 1)
        check(window.isVisible && window.selectedCandidateIndex() == 1, "Candidate UI respects engine highlight")
        _ = window.navigateByArrow(forward: true)
        check(window.selectedCandidateIndex() == 2, "Right arrow moves candidate highlight")
        var pageRequested = false
        window.onPageChange = { backward in pageRequested = !backward }
        window.show(candidates: candidates, client: client, highlightedIndex: candidates.count - 1)
        _ = window.navigateByArrow(forward: true)
        check(pageRequested, "Right arrow at last candidate requests the next page")
        window.hide()
        check(!window.isVisible && window.candidates.isEmpty, "Hidden candidate UI clears stale candidates")
        var overlayConfig = OverlayConfig()
        overlayConfig.autoDismissInterval = 0
        let overlay = LOTranslationOverlay(config: overlayConfig)
        overlay.show(originalText: "first", translation: "first result")
        overlay.hide()
        overlay.show(originalText: "second", translation: "new result")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        check(overlay.isVisible, "A previous fade completion cannot hide a newer translation")
        overlay.hide()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        engine.selectCandidateOnCurrentPage(index: 1, session: session)
        check(engine.getCommit(session: session) == candidates[1].text, "Selecting candidate index commits the requested candidate")
        check(RimeEngine.convertKeyCode(0, chars: "A") == 65, "Uppercase key values remain uppercase")
        check(RimeEngine.convertKeyCode(76) == 0xFF0D, "Numpad Enter maps to Return")
        check(RimeEngine.convertKeyCode(117) == 0xFFFF, "Forward Delete is mapped")
        check(engine.getCandidates(session: session, count: -1).isEmpty, "Invalid candidate count is harmless")
        check(engine.getCandidates(session: 0).isEmpty, "Invalid session is harmless")

        // 本地翻译：模式与模型目录一致性
        check(MTEngineMode.from("unknown") == .online, "Unknown engine mode falls back to online")
        check(MTEngineMode.from("localFirst") == .light, "Legacy local mode maps to light engine")
        check(MTModelCatalog.lightModels.map { $0.id } == ["opus-mt-zh-en"],
              "Light tier keeps Chinese to English only")
        check(MTModelCatalog.manifest(forSource: "zh", target: "en")?.id == "opus-mt-zh-en",
              "Catalog resolves zh to en")
        check(MTModelCatalog.manifest(forSource: "zh", target: "ja") == nil,
              "No direct Chinese to Japanese ONNX model")
        check(MTModelCatalog.manifest(forSource: "en", target: "zh") == nil,
              "Reverse direction is not bundled")
        check(MTModelCatalog.normalized("zh-Hans") == "zh",
              "Catalog normalizes zh-Hans to zh")
        check(MTLanguageCatalog.lightCodes == ["en"],
              "Light engine targets English only")
        check(!MTLanguageCatalog.onlineCodes.contains("zh-Hans")
              && !MTLanguageCatalog.onlineCodes.contains("zh-Hant"),
              "Chinese targets are excluded for Chinese input")
        check(MTModelCatalog.lightModels[0].files.first?.urls.first?.contains("modelscope.cn") == true,
              "ModelScope is the primary download source")
        check(MTLanguageCatalog.normalizedCode("ceb") == "ceb",
              "Three letter language codes are preserved")
        check(!MTLanguageCatalog.supports("ja", mode: .light),
              "Unsupported target is rejected for the light engine")
        check(MTErrorCode.timeout.isRetryable, "Timeout errors are retryable (fallback to online)")
        check(!MTErrorCode.modelNotFound.isRetryable, "Missing model errors are not retryable")
        print("Input core regression: \(passed) checks passed")
    }
}
