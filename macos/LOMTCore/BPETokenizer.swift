import Foundation

// MARK: - BPE 分词（M2M100 等）

/// 从 Hugging Face `tokenizer.json` 读取词表、合并规则与语言标记。
///
/// M2M100 使用 SentencePiece BPE，但目标语言由 `__en__` / `__zh__` 这类
/// 特殊标记强制指定，因此必须按 BPE 规则分词，不能复用 OPUS-MT 的 Unigram 实现。
public final class BPETokenizer {

    public enum ParseError: Error, LocalizedError {
        case invalidFile
        case invalidModel(String)

        public var errorDescription: String? {
            switch self {
            case .invalidFile: return "tokenizer.json 解析失败"
            case .invalidModel(let detail): return "分词模型不可用：\(detail)"
            }
        }
    }

    /// 合并规则在字典中的分隔符（词片本身不会包含控制字符）
    private static let pairSeparator = "\u{1F}"

    private let vocab: [String: Int]
    private let pieces: [String]
    private let ranks: [String: Int]
    private let specials: Set<String>
    private let languageIDs: [String: Int]

    public let eosId: Int
    public let unkId: Int

    public init(tokenizerURL: URL) throws {
        guard let data = try? Data(contentsOf: tokenizerURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any] else {
            throw ParseError.invalidFile
        }
        guard let rawVocab = model["vocab"] as? [String: Int],
              let merges = model["merges"] as? [String] else {
            throw ParseError.invalidModel("缺少 vocab 或 merges")
        }

        var maxId = 0
        for value in rawVocab.values { maxId = max(maxId, value) }
        var pieceTable = [String](repeating: "", count: maxId + 1)
        for (piece, id) in rawVocab where id >= 0 && id < pieceTable.count {
            pieceTable[id] = piece
        }

        guard let eos = rawVocab["</s>"] else { throw ParseError.invalidModel("词表缺少 </s>") }
        self.eosId = eos
        self.unkId = rawVocab["<unk>"] ?? 3
        self.vocab = rawVocab
        self.pieces = pieceTable

        var rankTable: [String: Int] = [:]
        rankTable.reserveCapacity(merges.count)
        for (rank, merge) in merges.enumerated() {
            let parts = merge.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            rankTable[String(parts[0]) + Self.pairSeparator + String(parts[1])] = rank
        }
        self.ranks = rankTable

        var specialTokens: Set<String> = ["<s>", "</s>", "<pad>", "<unk>"]
        var languages: [String: Int] = [:]
        if let added = root["added_tokens"] as? [[String: Any]] {
            for token in added {
                guard let content = token["content"] as? String,
                      let id = token["id"] as? Int else { continue }
                specialTokens.insert(content)
                // 语言标记形如 __en__ / __zh__
                if content.hasPrefix("__"), content.hasSuffix("__"), content.count > 4 {
                    let code = String(content.dropFirst(2).dropLast(2))
                    languages[code.lowercased()] = id
                }
            }
        }
        self.specials = specialTokens
        self.languageIDs = languages
    }

    /// 目标语言对应的强制起始标记；不支持时返回 nil
    public func languageToken(for code: String) -> Int? {
        languageIDs[BPETokenizer.languageCode(code)]
    }

    /// BCP 47 代码归一化：zh-Hans → zh，en-GB → en，pt-BR → pt
    public static func languageCode(_ raw: String) -> String {
        switch raw {
        case "zh-Hans", "zh-Hant", "zh_CN", "zh_TW", "zh": return "zh"
        default: return String(raw.prefix(2)).lowercased()
        }
    }

    /// 分词：WhitespaceSplit + Metaspace（每个词前加 ▁），再按 BPE 合并
    public func encode(_ text: String) -> [Int] {
        var ids: [Int] = []
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            for piece in mergePieces("▁" + word) {
                ids.append(vocab[piece] ?? unkId)
            }
        }
        return ids
    }

    /// 解码：拼接词片，`▁` 还原空格，忽略特殊标记
    public func decode(_ ids: [Int]) -> String {
        var text = ""
        for id in ids {
            guard id >= 0, id < pieces.count else { continue }
            let piece = pieces[id]
            guard !piece.isEmpty, !specials.contains(piece) else { continue }
            text += piece.replacingOccurrences(of: "▁", with: " ")
        }
        if text.hasPrefix(" ") { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - BPE 合并

    private func mergePieces(_ word: String) -> [String] {
        var symbols = word.map { String($0) }
        guard symbols.count > 1 else { return symbols }

        while symbols.count > 1 {
            var bestRank = Int.max
            var bestIndex = -1
            for index in 0..<(symbols.count - 1) {
                let key = symbols[index] + Self.pairSeparator + symbols[index + 1]
                if let rank = ranks[key], rank < bestRank {
                    bestRank = rank
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { break }

            let left = symbols[bestIndex]
            let right = symbols[bestIndex + 1]
            let merged = left + right
            var next: [String] = []
            next.reserveCapacity(symbols.count)
            var index = 0
            while index < symbols.count {
                if index < symbols.count - 1,
                   symbols[index] == left, symbols[index + 1] == right {
                    next.append(merged)
                    index += 2
                } else {
                    next.append(symbols[index])
                    index += 1
                }
            }
            symbols = next
        }
        return symbols
    }
}
