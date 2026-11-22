import AppKit
import ScreenCaptureKit

typealias Row = [String: Any]
enum BridgeError: Error { case unavailable(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw BridgeError.unavailable(message) }
}
func windows() -> [Row] {
    CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [Row] ?? []
}
func windowRect(_ row: Row) -> CGRect {
    guard let bounds = row[kCGWindowBounds as String] as? NSDictionary else { return .null }
    return CGRect(dictionaryRepresentation: bounds) ?? .null
}
func foreground() throws -> (NSRunningApplication, Row) {
    guard let app = NSWorkspace.shared.frontmostApplication,
          let row = windows().first(where: {
            $0[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier &&
            $0[kCGWindowLayer as String] as? Int == 0
          }) else { throw BridgeError.unavailable("No foreground application window.") }
    return (app,row)
}
func rectRow(_ r: CGRect) -> Row {
    ["x": Int(r.minX), "y": Int(r.minY), "width": Int(r.width), "height": Int(r.height)]
}

@available(macOS 14.0, *)
func capture(_ line: String) async throws -> (CGRect, CGImage, Bool) {
    let a = line.components(separatedBy: "|")
    try require(a.count == 9, "Invalid frame request.")
    try require(["owned", "window-region", "region", "foreground"].contains(a[0]) && ["png", "bgra"].contains(a[8]), "Invalid source or format.")
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var area: CGRect
    var filter: SCContentFilter
    let config = SCStreamConfiguration()
    config.showsCursor = false
    if a[0] == "owned" || a[0] == "window-region" {
        let identity = a[1].components(separatedBy: ":")
        guard let window = content.windows.first(where: { String($0.windowID) == identity.first }) else {
            throw BridgeError.unavailable("Window disappeared.")
        }
        filter = SCContentFilter(desktopIndependentWindow: window)
        config.ignoreShadowsSingleWindow = true
        area = window.frame
        if a[0] == "window-region" {
            try require(identity.count == 2 && window.owningApplication?.processID == Int32(identity[1]), "Window changed.")
            area = try requestedRect(a)
            try require(window.frame.contains(area), "Region outside window.")
            config.sourceRect = area.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        }
    } else {
        let display: SCDisplay
        if a[0] == "region" {
            area = try requestedRect(a)
            guard let d = content.displays.first(where: { $0.frame.contains(area) }) else {
                throw BridgeError.unavailable("Region outside display.")
            }
            display = d
        } else {
            try require(a[0] == "foreground", "Invalid source.")
            let (_, row) = try foreground()
            let id = row[kCGWindowNumber as String] as? UInt32
            try require(a[1].isEmpty || id == UInt32(a[1]), "Foreground changed.")
            let rect = windowRect(row)
            guard let d = content.displays.max(by: { overlap($0.frame, rect) < overlap($1.frame, rect) }),
                  overlap(d.frame, rect) > 0 else { throw BridgeError.unavailable("No display.") }
            display = d
            area = display.frame
        }
        filter = SCContentFilter(display: display, excludingWindows: [])
        config.sourceRect = area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }
    guard let w = Int(a[6]), let h = Int(a[7]), (1...16384).contains(w), (1...16384).contains(h),
          area.width > 0, area.height > 0, area.width * area.height <= 40000000 else {
        throw BridgeError.unavailable("Invalid dimensions.")
    }
    let scale = min(1, CGFloat(w) / area.width, CGFloat(h) / area.height)
    config.width = max(1, Int((area.width * scale).rounded()))
    config.height = max(1, Int((area.height * scale).rounded()))
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    return (area, image, a[8] == "png")
}
func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let r = a.intersection(b)
    return r.isNull ? 0 : r.width * r.height
}
func requestedRect(_ a: [String]) throws -> CGRect {
    guard let x = Int32(a[2]), let y = Int32(a[3]), let w = Int32(a[4]), let h = Int32(a[5]), w > 0, h > 0 else {
        throw BridgeError.unavailable("Invalid region.")
    }
    return CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
}
func frameWorker() async {
    while let line = readLine() {
        do {
            guard #available(macOS 14.0, *) else { throw BridgeError.unavailable("Requires macOS 14.") }
            let (area, image, png) = try await capture(line)
            let data: Data
            if png {
                guard let encoded = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw BridgeError.unavailable("PNG encoding failed.")
                }
                data = encoded
            } else {
                var pixels = Data(count: image.width * image.height * 4)
                try pixels.withUnsafeMutableBytes { ptr in
                    guard let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                        throw BridgeError.unavailable("Invalid bitmap.")
                    }
                    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
                data = pixels
            }
            let header: [Int32] = [0, Int32(area.minX), Int32(area.minY), Int32(area.width), Int32(area.height),
                                   Int32(image.width), Int32(image.height), Int32(data.count)]
            FileHandle.standardOutput.write(header.withUnsafeBytes { Data($0) })
            FileHandle.standardOutput.write(data)
        } catch {
            let header: [Int32] = [1,0,0,0,0,0,0,0]
            FileHandle.standardOutput.write(header.withUnsafeBytes { Data($0) })
        }
    }
}
