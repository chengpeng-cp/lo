import Foundation

// MARK: - SentencePiece 轻量实现

/// 从官方 `.spm`（SentencePiece ModelProto）与 `vocab.json` 构建的 Unigram 分词器。
///
/// 只实现 OPUS-MT 所需的子集：
/// - 归一化：NFKC + 折叠空白 + dummy prefix（与 SentencePiece 默认行为一致）
/// - 编码：Unigram Viterbi（按词片 score 最大路径）
/// - 解码：词片拼接、`▁` 还原空格、`<0xNN>` 字节回退
///
/// 这样运行时不需要链接 libsentencepiece，也不需要额外的 protobuf 依赖。
public final class SentencePieceModel {

    /// 词片表：下标为模型 vocab id
    public let pieces: [String]
    /// 每个 id 对应的词片分数（未出现在 spm 中的 id 为 -inf）
    public let scores: [Float]
    public let eosId: Int
    public let padId: Int
    public let unkId: Int

    private let pieceIndex: [String: Int]
    private let maxPieceLength: Int

    public enum ParseError: Error, LocalizedError {
        case invalidModel(String)
        case invalidVocab
        case missingSpecialToken(String)

        public var errorDescription: String? {
            switch self {
            case .invalidModel(let detail): return "分词模型解析失败：\(detail)"
            case .invalidVocab: return "vocab.json 解析失败"
            case .missingSpecialToken(let token): return "词表缺少特殊符号 \(token)"
            }
        }
    }

    public init(spmURL: URL, vocabURL: URL) throws {
        let spmData = try Data(contentsOf: spmURL)
        let entries = try Self.parseModel(spmData)

        guard let vocabData = try? Data(contentsOf: vocabURL),
              let raw = try? JSONSerialization.jsonObject(with: vocabData) as? [String: Int] else {
            throw ParseError.invalidVocab
        }

        var maxId = 0
        for value in raw.values { maxId = max(maxId, value) }
        var pieceTable = [String](repeating: "", count: maxId + 1)
        var scoreTable = [Float](repeating: -Float.infinity, count: maxId + 1)
        for (piece, id) in raw where id >= 0 {
            pieceTable[id] = piece
        }
        for entry in entries {
            guard let id = raw[entry.piece], id >= 0, id < pieceTable.count else { continue }
            scoreTable[id] = entry.score
        }

        guard let eos = raw["</s>"] else { throw ParseError.missingSpecialToken("</s>") }
        guard let pad = raw["<pad>"] else { throw ParseError.missingSpecialToken("<pad>") }
        guard let unk = raw["<unk>"] else { throw ParseError.missingSpecialToken("<unk>") }

        self.pieces = pieceTable
        self.scores = scoreTable
        self.eosId = eos
        self.padId = pad
        self.unkId = unk
        self.pieceIndex = raw
        self.maxPieceLength = entries.reduce(1) { max($0, min(32, $1.piece.count)) }
    }

    // MARK: - 编码

    public func encode(_ text: String) -> [Int] {
        let prepared = Self.normalize(text)
        let characters = Array(prepared)
        let count = characters.count
        guard count > 0 else { return [] }

        var best = [Float](repeating: -Float.infinity, count: count + 1)
        var back = [(previous: Int, id: Int)](repeating: (0, unkId), count: count + 1)
        best[0] = 0

        for start in 0..<count where best[start] > -Float.infinity {
            let limit = min(maxPieceLength, count - start)
            var candidate = ""
            candidate.reserveCapacity(limit)
            for length in 1...limit {
                candidate.append(characters[start + length - 1])
                guard let id = pieceIndex[candidate], id < scores.count else { continue }
                let score = scores[id]
                guard score > -Float.infinity else { continue }
                let total = best[start] + score
                if total > best[start + length] {
                    best[start + length] = total
                    back[start + length] = (start, id)
                }
            }
        }

        guard best[count] > -Float.infinity else {
            // 极端情况（含未登录字符）：逐个字符退化为 unk，保证不阻塞翻译
            return characters.map { _ in unkId }
        }

        var ids: [Int] = []
        var cursor = count
        while cursor > 0 {
            let step = back[cursor]
            ids.append(step.id)
            cursor = step.previous
        }
        return ids.reversed()
    }

    /// SentencePiece 默认预处理：NFKC、折叠空白、加 dummy prefix、空格转 `▁`
    public static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
        let collapsed = folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return "▁" + collapsed.replacingOccurrences(of: " ", with: "▁")
    }

    // MARK: - 解码

    public func decode(_ ids: [Int]) -> String {
        var output = ""
        var pendingBytes: [UInt8] = []

        func flushBytes() {
            guard !pendingBytes.isEmpty else { return }
            output += String(decoding: pendingBytes, as: UTF8.self)
            pendingBytes.removeAll(keepingCapacity: true)
        }

        for id in ids {
            guard id >= 0, id < pieces.count else { continue }
            let piece = pieces[id]
            guard !piece.isEmpty else { continue }
            if piece.first == "<", piece.last == ">" {
                if piece.hasPrefix("<0x"), piece.hasSuffix(">"),
                   let byte = UInt8(piece.dropFirst(3).dropLast(), radix: 16) {
                    pendingBytes.append(byte)
                    continue
                }
                continue  // <s> </s> <unk> <pad>
            }
            flushBytes()
            output += piece.replacingOccurrences(of: "▁", with: " ")
        }
        flushBytes()

        if output.first == " " { output.removeFirst() }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ModelProto 解析

    private struct Entry {
        let piece: String
        let score: Float
    }

    /// 解析 SentencePiece ModelProto 中 `repeated SentencePiece pieces = 1` 字段。
    /// 只读取 piece(string, field 1) 与 score(float, field 2)，其余字段跳过。
    private static func parseModel(_ data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        var index = 0
        var entries: [Entry] = []

        while index < bytes.count {
            let key = try readVarint(bytes, &index)
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            if field == 1 && wire == 2 {
                let length = Int(try readVarint(bytes, &index))
                guard index + length <= bytes.count else {
                    throw ParseError.invalidModel("字段长度越界")
                }
                let slice = Array(bytes[index..<(index + length)])
                index += length
                if let entry = try parseEntry(slice) { entries.append(entry) }
            } else {
                try skip(bytes, &index, wire: wire)
            }
        }
        guard !entries.isEmpty else { throw ParseError.invalidModel("没有词片") }
        return entries
    }

    private static func parseEntry(_ bytes: [UInt8]) throws -> Entry? {
        var index = 0
        var piece: String?
        var score: Float = 0
        while index < bytes.count {
            let key = try readVarint(bytes, &index)
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            if field == 1 && wire == 2 {
                let length = Int(try readVarint(bytes, &index))
                guard index + length <= bytes.count else { return nil }
                piece = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
                index += length
            } else if field == 2 && wire == 5 {
                guard index + 4 <= bytes.count else { return nil }
                let raw = UInt32(bytes[index])
                    | (UInt32(bytes[index + 1]) << 8)
                    | (UInt32(bytes[index + 2]) << 16)
                    | (UInt32(bytes[index + 3]) << 24)
                index += 4
                score = Float(bitPattern: raw)
            } else {
                try skip(bytes, &index, wire: wire)
            }
        }
        guard let text = piece else { return nil }
        return Entry(piece: text, score: score)
    }

    private static func readVarint(_ bytes: [UInt8], _ index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { break }
        }
        throw ParseError.invalidModel("varint 越界")
    }

    private static func skip(_ bytes: [UInt8], _ index: inout Int, wire: Int) throws {
        switch wire {
        case 0:
            _ = try readVarint(bytes, &index)
        case 1:
            index += 8
        case 2:
            let length = Int(try readVarint(bytes, &index))
            index += length
        case 5:
            index += 4
        default:
            throw ParseError.invalidModel("不支持的 wire type \(wire)")
        }
        guard index <= bytes.count else { throw ParseError.invalidModel("字段越界") }
    }
}
