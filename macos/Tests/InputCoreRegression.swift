// Standalone regression harness. Compile with the application Swift sources (except main.swift).
// Uses only a temporary Rime user directory and a mock IMK client; never installs an input source.
import AppKit
import InputMethodKit
import CRime

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
        let activeMarkedRange = NSRange(location: 4, length: 3)
        check(LOTextInsertion.replacementRange(markedRange: activeMarkedRange, selectedRange: collapsedSelection) == activeMarkedRange,
            "Composition commits replace the active marked range")
        client.insertText("，", replacementRange: LOTextInsertion.replacementRange(
            markedRange: noMarkedText, selectedRange: client.selectedRange()))
        check(client.text == "，", "A leading punctuation commit inserts into an empty client")
        var tracker = LOShiftTapTracker()
        func flags(_ modifiers: NSEvent.ModifierFlags, at time: TimeInterval, keyCode: UInt16 = 56) -> NSEvent {
            NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: modifiers,
                timestamp: time, windowNumber: 0, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
        }
        check(!tracker.shouldToggle(for: flags(.shift, at: 1), threshold: 0.4), "Shift down waits for release")
        check(tracker.shouldToggle(for: flags([], at: 1.1), threshold: 0.4), "Short standalone Shift toggles")
        _ = tracker.shouldToggle(for: flags(.shift, at: 2), threshold: 0.4)
        tracker.noteKeyDown(modifiers: .shift)
        check(!tracker.shouldToggle(for: flags([], at: 2.1), threshold: 0.4), "Shift letter chord never toggles")
        _ = tracker.shouldToggle(for: flags(.shift, at: 3), threshold: 0.4)
        check(!tracker.shouldToggle(for: flags([], at: 4), threshold: 0.4), "Long Shift never toggles")
        tracker.reset(modifiers: .shift)
        check(!tracker.shouldToggle(for: flags([], at: 5), threshold: 0.4), "Shift held during activation never toggles on release")
        _ = tracker.shouldToggle(for: flags(.shift, at: 6), threshold: 0.4)
        _ = tracker.shouldToggle(for: flags([.shift, .command], at: 6.05, keyCode: 55), threshold: 0.4)
        _ = tracker.shouldToggle(for: flags(.shift, at: 6.07, keyCode: 55), threshold: 0.4)
        check(!tracker.shouldToggle(for: flags([], at: 6.1), threshold: 0.4), "Shift Command chord never toggles")
        _ = tracker.shouldToggle(for: flags(.shift, at: 7, keyCode: 0), threshold: 0.4)
        check(tracker.shouldToggle(for: flags([], at: 7.1, keyCode: 0), threshold: 0.4), "Modifier fallback supports remote keyboard keyCode zero")

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
        print("Input core regression: \(passed) checks passed")
    }
}
