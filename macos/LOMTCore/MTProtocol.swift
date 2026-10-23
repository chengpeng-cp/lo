import Foundation

// MARK: - 本地翻译协议与模型清单
//
// 这些类型同时被输入法主程序与 LOMTEngine 使用，保证两端对协议、
// 模型目录结构和错误码的理解完全一致。

public enum MTProtocolVersion {
    public static let current = 1
}

/// 本地翻译错误码。UI 与回退逻辑只依赖这些码，不解析文案。
public enum MTErrorCode: String, Codable, Sendable {
    case protocolMismatch = "protocol_mismatch"
    case modelNotFound = "model_not_found"
    case modelCorrupt = "model_corrupt"
    case unsupportedLangPair = "unsupported_lang_pair"
    case outOfMemory = "oom"
    case timeout
    case cancelled
    case engineError = "engine_error"

    /// 是否值得回退到在线翻译
    public var isRetryable: Bool {
        switch self {
        case .timeout, .outOfMemory, .engineError:
            return true
        case .protocolMismatch, .modelNotFound, .modelCorrupt,
             .unsupportedLangPair, .cancelled:
            return false
        }
    }
}

// MARK: - 清单

/// 模型包中的单个文件（下载与校验单位）
public struct MTModelFile: Codable, Sendable {
    public var path: String
    public var bytes: Int64
    public var sha256: String
    public var urls: [String]

    public init(path: String, bytes: Int64, sha256: String, urls: [String]) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
        self.urls = urls
    }
}

/// 本地模型包描述。写入模型目录下的 manifest.json，下载完成后参与校验。
public struct MTModelManifest: Codable, Sendable {
    public var schema: Int
    public var id: String
    public var displayName: String
    /// light（轻量）或 quality（高质量）
    public var tier: String
    /// 目前只有 onnx
    public var engine: String
    public var src: String
    public var tgt: String
    public var bytes: Int64
    /// 机器物理内存门槛，0 表示不限
    public var minRAMBytes: Int64
    public var arch: [String]
    public var licenseName: String
    public var licenseURL: String
    public var attribution: String
    /// 以下均为模型目录内的相对路径
    public var encoder: String
    public var decoder: String
    public var vocab: String
    public var sourceSpm: String
    public var targetSpm: String
    public var maxNewTokens: Int
    public var files: [MTModelFile]

    public init(schema: Int = 1,
                id: String,
                displayName: String,
                tier: String,
                engine: String = "onnx",
                src: String,
                tgt: String,
                bytes: Int64,
                minRAMBytes: Int64 = 0,
                arch: [String] = ["arm64", "x86_64"],
                licenseName: String,
                licenseURL: String,
                attribution: String,
                encoder: String,
                decoder: String,
                vocab: String,
                sourceSpm: String,
                targetSpm: String,
                maxNewTokens: Int = 256,
                files: [MTModelFile]) {
        self.schema = schema
        self.id = id
        self.displayName = displayName
        self.tier = tier
        self.engine = engine
        self.src = src
        self.tgt = tgt
        self.bytes = bytes
        self.minRAMBytes = minRAMBytes
        self.arch = arch
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.attribution = attribution
        self.encoder = encoder
        self.decoder = decoder
        self.vocab = vocab
        self.sourceSpm = sourceSpm
        self.targetSpm = targetSpm
        self.maxNewTokens = maxNewTokens
        self.files = files
    }

    public func file(named name: String) -> MTModelFile? {
        files.first { $0.path == name }
    }
}

// MARK: - helper 协议

public struct MTEngineRequest: Codable, Sendable {
    public var id: Int
    public var op: String
    public var model: String?
    public var dir: String?
    public var text: String?
    public var src: String?
    public var tgt: String?
    public var timeoutMs: Int?

    public init(id: Int, op: String, model: String? = nil, dir: String? = nil,
                text: String? = nil, src: String? = nil, tgt: String? = nil,
                timeoutMs: Int? = nil) {
        self.id = id
        self.op = op
        self.model = model
        self.dir = dir
        self.text = text
        self.src = src
        self.tgt = tgt
        self.timeoutMs = timeoutMs
    }
}

public struct MTEngineResponse: Codable, Sendable {
    public var id: Int
    public var ok: Bool
    public var text: String?
    public var code: String?
    public var message: String?
    public var ms: Int?
    public var engine: String?
    public var model: String?
    public var loaded: Bool?
    public var protocolVersion: Int?
    public var engines: [String]?
    public var arch: String?
    public var ramBytes: Int64?
    public var requests: Int?
    public var avgMs: Int?

    public init(id: Int, ok: Bool, text: String? = nil, code: String? = nil,
                message: String? = nil, ms: Int? = nil, engine: String? = nil,
                model: String? = nil, loaded: Bool? = nil, protocolVersion: Int? = nil,
                engines: [String]? = nil, arch: String? = nil, ramBytes: Int64? = nil,
                requests: Int? = nil, avgMs: Int? = nil) {
        self.id = id
        self.ok = ok
        self.text = text
        self.code = code
        self.message = message
        self.ms = ms
        self.engine = engine
        self.model = model
        self.loaded = loaded
        self.protocolVersion = protocolVersion
        self.engines = engines
        self.arch = arch
        self.ramBytes = ramBytes
        self.requests = requests
        self.avgMs = avgMs
    }

    public static func failure(id: Int, code: MTErrorCode, message: String) -> MTEngineResponse {
        MTEngineResponse(id: id, ok: false, code: code.rawValue, message: message)
    }
}
