import AppKit
import ApplicationServices

@main struct Bridge {
    static func main() async {
        if CommandLine.arguments.dropFirst().first == "--frames" { await frameWorker(); return }
        if Array(CommandLine.arguments.dropFirst()) == ["capture", "macos-system-audio"] {
            guard #available(macOS 13, *) else { exit(1) }
            do { try await streamAudio() } catch { exit(1) }
            return
        }
        if CommandLine.arguments.dropFirst().first == "--request-permissions" {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary)
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        }
        if ["--permissions", "--request-permissions"].contains(CommandLine.arguments.dropFirst().first ?? "") {
            let status = ["screenRecording": CGPreflightScreenCaptureAccess(), "accessibility": AXIsProcessTrusted()]
            if let data = try? JSONSerialization.data(withJSONObject: status) { FileHandle.standardOutput.write(data) }
            return
        }
        let result: Row
        do {
            guard let line = readLine(), line.utf8.count <= 65536,
                  let command = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? Row else {
                throw BridgeError.unavailable("Invalid request.")
            }
            result = try action(command)
        } catch BridgeError.unavailable(let message) { result = ["ok":false,"error":message] }
        catch { result = ["ok":false,"error":"Desktop action failed."] }
        if let data = try? JSONSerialization.data(withJSONObject:result) { FileHandle.standardOutput.write(data) }
    }
}
