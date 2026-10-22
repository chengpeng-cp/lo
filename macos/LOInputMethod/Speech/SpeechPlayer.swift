import AVFoundation
import Foundation

// MARK: - 语音播报

/// 朗读翻译结果。使用 macOS 内置语音合成（AVSpeechSynthesizer）：
/// 离线、免费、无需 API Key，短句场景延迟最低。
///
/// 播报时机：只在翻译完成时朗读一次。流式翻译的增量回调不朗读，
/// 否则同一段译文会被反复读出。
@MainActor
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = SpeechPlayer()

    private let synthesizer = AVSpeechSynthesizer()

    /// 朗读期间保持进程活跃，避免 App Nap 降频打断合成
    private var activity: NSObjectProtocol?

    /// 上一次朗读的文本，用于避免同一译文重复播报
    private var lastSpokenText: String?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 朗读文本（有译文时读译文，无译文时读原文）。
    /// 只受播报开关控制，与翻译开关无关。
    func speakTranslation(_ text: String) {
        let settings = LOSettings.load()
        guard settings.speechEnabled else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 单个标点或单字没有播报价值
        guard trimmed.count >= 2 else {
            debugLog("[Speech] 跳过：内容过短 \"\(trimmed)\"")
            return
        }
        guard trimmed != lastSpokenText else {
            debugLog("[Speech] 跳过：与上次播报相同")
            return
        }
        lastSpokenText = trimmed

        // 新译文立即打断旧朗读，避免多段排队造成播报严重滞后
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let language = Self.voiceLanguage(for: trimmed, targetLanguage: settings.targetLanguage)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = Float(settings.speechRate)
        debugLog("[Speech] 开始播报 lang=\(language) rate=\(settings.speechRate) voice=\(utterance.voice?.name ?? "默认") text=\(trimmed.prefix(40))")
        beginActivity()
        synthesizer.speak(utterance)
    }

    /// 停止朗读并清除去重记录（关闭播报、切换引擎时调用）
    func stop() {
        lastSpokenText = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else {
            endActivity()
        }
    }

    /// 设置变更后调用：关闭播报时立即停止当前朗读
    func reloadSettings() {
        let settings = LOSettings.load()
        if !settings.speechEnabled {
            stop()
        }
    }

    // MARK: - 内部

    /// 选择朗读语音。
    /// 播报原文时文本是中文，若直接用目标语言（通常是英文）语音会读得很怪，
    /// 因此先按文本内容判断：含 CJK 字符就用中文语音，否则用目标语言。
    private static func voiceLanguage(for text: String, targetLanguage: String) -> String {
        let hasCJK = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
        if hasCJK { return "zh-CN" }
        switch targetLanguage {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return targetLanguage
        }
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Speak translated text"
        )
    }

    private func endActivity() {
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            debugLog("[Speech] 播报完成")
            self.endActivity()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.endActivity() }
    }
}
