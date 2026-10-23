import Foundation
import LOMTCore

// MARK: - LOMTEngine
//
// 本地翻译推理进程。由输入法主程序通过 stdin/stdout 启动，
// 按 JSON Lines 收发请求；进程崩溃不会影响输入法本身的稳定性。
//
// 协议见 LOMTCore/MTProtocol.swift。

setvbuf(stdout, nil, _IOLBF, 0)

let host = EngineHost()
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]

func write(_ response: MTEngineResponse) {
    guard let data = try? encoder.encode(response),
          let line = String(data: data, encoding: .utf8) else { return }
    print(line)
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }

    guard let data = trimmed.data(using: .utf8),
          let request = try? JSONDecoder().decode(MTEngineRequest.self, from: data) else {
        let response = MTEngineResponse.failure(id: 0, code: .protocolMismatch, message: "请求不是合法 JSON")
        write(response)
        continue
    }

    let response = host.handle(request)
    write(response)
    if host.shouldExit { break }
}
