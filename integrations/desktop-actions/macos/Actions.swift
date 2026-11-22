import AppKit
import ApplicationServices
import CryptoKit

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func elementRect(_ element: AXUIElement) -> CGRect? {
    guard let pos = attr(element, kAXPositionAttribute), let size = attr(element, kAXSizeAttribute),
          CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
    return CGRect(origin: p, size: s)
}
struct Item {
    let element: AXUIElement
    let row: Row
}
func controls(_ app: NSRunningApplication, _ bounds: CGRect) throws -> [Item] {
    guard AXIsProcessTrusted() else { throw BridgeError.unavailable("Allow Accessibility access for Capri in System Settings.") }
    let owner = AXUIElementCreateApplication(app.processIdentifier)
    guard let win = attr(owner, kAXFocusedWindowAttribute), CFGetTypeID(win) == AXUIElementGetTypeID(),
          let axBounds = elementRect(win as! AXUIElement), axBounds.equalTo(bounds) else {
        throw BridgeError.unavailable("Focus the application window and try again.")
    }
    let focused = attr(owner, kAXFocusedUIElementAttribute)
    var items = [Item](), visited = 0
    func walk(_ e: AXUIElement, _ path: String, _ depth: Int) {
        guard visited < 350, items.count < 65, depth < 18 else { return }
        visited += 1
        let role = attr(e, kAXRoleAttribute) as? String ?? ""
        let secure = (attr(e, kAXSubroleAttribute) as? String) == "AXSecureTextField"
        if secure { return }
        if let r = elementRect(e), r.width > 0, r.height > 0, bounds.contains(CGPoint(x:r.midX,y:r.midY)),
           ["AXButton","AXCheckBox","AXRadioButton","AXTextField","AXTextArea","AXPopUpButton","AXLink","AXComboBox"].contains(role) {
            let name = String(((attr(e, kAXTitleAttribute) ?? attr(e, kAXDescriptionAttribute)) as? String ?? role).prefix(100))
            let editable = ["AXTextField","AXTextArea","AXComboBox"].contains(role)
            let token = [path, role, name, attr(e, kAXIdentifierAttribute) as? String ?? "", NSStringFromRect(r)].joined(separator:"|")
            let id = SHA256.hash(data:Data(token.utf8)).map { String(format:"%02x",$0) }.joined()
            items.append(Item(element:e, row:["id":id, "name":name, "untrustedName":name, "editable":editable,
                "type":editable ? "ControlType.Edit" : "ControlType.Button", "clickKind":"control",
                "focused":focused.map { CFEqual($0,e) } ?? false, "bounds":rectRow(r), "x":Int(r.midX), "y":Int(r.midY)]))
        }
        for (i, child) in ((attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []).prefix(100).enumerated() {
            walk(child, path + ".\(i)", depth + 1)
        }
    }
    walk(win as! AXUIElement,"w",0)
    return items
}
func identity(_ app: NSRunningApplication, _ row: Row) throws -> Row {
    guard let date = app.launchDate, let id = row[kCGWindowNumber as String] as? UInt32 else {
        throw BridgeError.unavailable("Application identity unavailable.")
    }
    let bounds = windowRect(row)
    try require(!bounds.isNull && !bounds.isEmpty,"Window has no visible bounds.")
    var result = rectRow(bounds)
    result["windowId"] = String(id)
    result["processId"] = String(app.processIdentifier)
    result["startedAtTicks"] = String(Int64(date.timeIntervalSince1970 * 1000000))
    result["executable"] = app.bundleURL?.path
    result["untrustedTitle"] = String((row[kCGWindowName as String] as? String ?? "").prefix(180))
    result["ok"] = true
    return result
}
let keyCodes: [String:UInt16] = [
    "A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,
    "R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,
    "O":31,"U":32,"I":34,"P":35,"ENTER":36,"L":37,"J":38,"K":40,"N":45,"M":46,"TAB":48,"SPACE":49,
    "BACKSPACE":51,"ESC":53,"ESCAPE":53,"CTRL":55,"SHIFT":56,"ALT":58,"HOME":115,"PAGEUP":116,"DELETE":117,
    "END":119,"PAGEDOWN":121,"LEFT":123,"RIGHT":124,"DOWN":125,"UP":126]
let flags: [String:CGEventFlags] = ["CTRL":.maskCommand,"SHIFT":.maskShift,"ALT":.maskAlternate]

func action(_ q: Row) throws -> Row {
    let op = q["action"] as? String ?? ""
    let ws = NSWorkspace.shared
    if op == "computer_release" { return ["ok":true] } // Events below use complete chords or AX operations.
    if op == "catalog_discover" { return try discover(q) }
    return try applicationAction(q, op, ws)
}

func discover(_ q: Row) throws -> Row {
    let fm = FileManager.default
    let dirs = ["/Applications","/System/Applications","/System/Applications/Utilities"]
    let bundles: [URL] = dirs.flatMap { dir in
        ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath:dir), includingPropertiesForKeys:nil)) ?? [])
            .filter { $0.pathExtension == "app" }
    }
    let query = q["query"] as? String ?? ""
    let matches = bundles.filter { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query) }
    return ["ok":true,"matches":matches.prefix(40).map { ["name":$0.deletingPathExtension().lastPathComponent,"executable":$0.path] }]
}
func applicationAction(_ q: Row, _ op: String, _ ws: NSWorkspace) throws -> Row {
    let fixed = ["notepad":"com.apple.TextEdit","calculator":"com.apple.calculator"]
    let appName = q["app"] as? String ?? ""
    let fixedURL = fixed[appName].flatMap { ws.urlForApplication(withBundleIdentifier:$0) }
    let url = (q["executable"] as? String).map { URL(fileURLWithPath:$0) } ?? fixedURL
    let running = url.flatMap { target in ws.runningApplications.first { $0.bundleURL?.standardizedFileURL == target.standardizedFileURL } }
    if op == "launch" || op == "focus" || op == "catalog_launch" {
        guard let url, url.pathExtension == "app", Bundle(url:url)?.executableURL != nil else { throw BridgeError.unavailable("Invalid app bundle.") }
        try require(q["windowTitle"] == nil && q["windowId"] == nil,"A specific window must already be focused.")
        if op == "focus" { try require(running?.activate(options:[]) == true,"Could not focus app.") }
        else { try require(ws.open(url),"Could not open app.") }
        for _ in 0..<25 {
            if let (active, window) = try? foreground(), active.bundleURL?.standardizedFileURL == url.standardizedFileURL {
                var result = try identity(active, window)
                result.merge(["app":appName, "launched":op != "focus", "windowVerified":true,
                              "running":true, "focused":true, "confirmation":"Focused the selected application."]) { _,new in new }
                return result
            }
            RunLoop.current.run(until:Date(timeIntervalSinceNow:0.08))
        }
        return ["ok":true,"app":appName,"launched":op != "focus","focused":false,"windowVerified":false,"confirmation":"Requested application activation; focus is unconfirmed."]
    }
    if op == "status" { return ["ok":true,"app":appName,"running":running != nil,"focused":running?.isActive ?? false] }
    if op == "computer_window_exists" {
        let pid = Int32(q["processId"] as? String ?? "")
        let row = windows().first { ($0[kCGWindowNumber as String] as? NSNumber)?.stringValue == q["windowId"] as? String && $0[kCGWindowOwnerPID as String] as? Int32 == pid }
        let info = try row.flatMap { r in try pid.flatMap { NSRunningApplication(processIdentifier:$0) }.map { try identity($0,r) } }
        return ["ok":true,"exists":info != nil && info?["startedAtTicks"] as? String == q["startedAtTicks"] as? String]
    }
    let (app,row) = try foreground()
    if let url { try require(app.bundleURL?.standardizedFileURL == url.standardizedFileURL,"Focus the selected app first.") }
    let bounds = windowRect(row)
    var state = try identity(app,row)
    let items = try controls(app,bounds)
    func verify() throws {
        let (current, window) = try foreground()
        let live = try identity(current,window)
        for key in ["windowId","processId","startedAtTicks"] {
            guard let expected = q[key] as? String, expected == live[key] as? String else { throw BridgeError.unavailable("Foreground changed. Observe again.") }
        }
        try require(windowRect(window).equalTo(bounds),"Window moved. Observe again.")
    }
    if ["controls","catalog_inspect","computer_state"].contains(op) {
        if let id = q["windowId"] as? String { try require(id == state["windowId"] as? String,"Focus the selected window.") }
        try require(q["windowTitle"] == nil || q["windowTitle"] as? String == state["untrustedTitle"] as? String,"Window title changed.")
        try require(q["ignoreProcessId"] as? String != state["processId"] as? String,"Focus the target application.")
        state["untrustedControls"] = items.map(\.row)
        return state
    }
    try verify()
    try require(q["expectedValueSha256"] == nil && q["expectedDiscordPaneId"] == nil && q["surface"] == nil,"Unsupported guarded operation.")
    let item = items.first { $0.row["id"] as? String == q["controlId"] as? String }
    if ["catalog_type","computer_type"].contains(op) {
        guard let item, item.row["editable"] as? Bool == true, let text = q["text"] as? String, text.count <= 4000 else { throw BridgeError.unavailable("Editable field changed.") }
        var prefix = ""
        if q["mode"] as? String == "append" {
            guard let old = attr(item.element,kAXValueAttribute) as? String else { throw BridgeError.unavailable("Field unavailable.") }
            prefix = old
        }
        try verify()
        try require(AXUIElementSetAttributeValue(item.element,kAXValueAttribute as CFString,(prefix+text) as CFString) == .success,"Field did not accept text.")
    } else if op == "computer_keys" {
        guard let keys = q["keys"] as? [String], let key = keys.filter({flags[$0] == nil}).only,
              let code = keyCodes[key], keys.count <= 4, (q["holdMs"] as? Int ?? 0) == 0 else { throw BridgeError.unavailable("Unsupported key chord.") }
        if let id = q["focusedControlId"] as? String {
            try require(items.contains { $0.row["id"] as? String == id && $0.row["focused"] as? Bool == true },"Keyboard focus changed.")
        }
        let modifiers = keys.reduce(CGEventFlags()) { $0.union(flags[$1] ?? []) }
        guard let down = CGEvent(keyboardEventSource:nil, virtualKey:code, keyDown:true),
              let up = CGEvent(keyboardEventSource:nil, virtualKey:code, keyDown:false) else { throw BridgeError.unavailable("Keyboard unavailable.") }
        try verify()
        for event in [down, up] { event.flags = modifiers; event.postToPid(app.processIdentifier) }
    } else if ["computer_click","computer_pointer","computer_scroll","computer_drag"].contains(op) {
        func point(_ x: String,_ y: String) throws -> CGPoint {
            guard let px = q[x] as? Int, let py = q[y] as? Int else { throw BridgeError.unavailable("Invalid point.") }
            let p = CGPoint(x:px,y:py)
            try require(bounds.contains(p),"Target outside observed window.")
            let top = windows().first { windowRect($0).contains(p) && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0 }
            try require(top?[kCGWindowNumber as String] as? UInt32 == row[kCGWindowNumber as String] as? UInt32,"Target is covered.")
            return p
        }
        if let expected = q["observedWindowBounds"] as? [String:Int] {
            try require(expected == rectRow(bounds) as? [String:Int],"Window moved.")
        }
        if q["controlId"] != nil {
            try require(item != nil && item?.row["x"] as? Int == q["x"] as? Int && item?.row["y"] as? Int == q["y"] as? Int,"Target changed.")
        }
        try require(q["exactLabel"] == nil || q["exactLabel"] as? String == item?.row["untrustedName"] as? String,"Label changed.")
        if op == "computer_scroll" {
            guard let amount = q["amount"] as? Int, (-10...10).contains(amount),
                  let event = CGEvent(scrollWheelEvent2Source:nil, units:.line,wheelCount:1,wheel1:Int32(amount),wheel2:0,wheel3:0) else { throw BridgeError.unavailable("Invalid scroll.") }
            try verify()
            event.location = CGPoint(x:bounds.midX,y:bounds.midY)
            event.postToPid(app.processIdentifier)
        } else {
            let p = try point("x","y")
            let button = q["button"] as? String ?? "left"
            let b: CGMouseButton = button == "right" ? .right : button == "middle" ? .center : .left
            let down: CGEventType = b == .left ? .leftMouseDown : b == .right ? .rightMouseDown : .otherMouseDown
            let up: CGEventType = b == .left ? .leftMouseUp : b == .right ? .rightMouseUp : .otherMouseUp
            func mouse(_ kind: CGEventType,_ location:CGPoint,_ count:Int = 1) {
                let event = CGEvent(mouseEventSource:nil,mouseType:kind,mouseCursorPosition:location,mouseButton:b)
                event?.setIntegerValueField(.mouseEventClickState,value:Int64(count))
                event?.postToPid(app.processIdentifier)
            }
            if op == "computer_pointer" { try verify(); CGWarpMouseCursorPosition(p) }
            else if op == "computer_drag" {
                let end = try point("toX","toY")
                try require((q["modifiers"] as? [String] ?? []).isEmpty && q["trajectory"] == nil,"Unsupported drag modifiers or path.")
                if let to = q["toControlId"] as? String { try require(items.contains { $0.row["id"] as? String == to && $0.row["x"] as? Int == Int(end.x) && $0.row["y"] as? Int == Int(end.y) },"Drag target changed.") }
                try verify()
                mouse(down,p); mouse(.leftMouseDragged,end); mouse(up,end)
            } else {
                let count = q["clickCount"] as? Int ?? 1
                try require((1...2).contains(count),"Invalid click count.")
                try verify()
                for n in 1...count { mouse(down,p,n); mouse(up,p,n) }
            }
        }
    } else { throw BridgeError.unavailable("This desktop action is unavailable on macOS.") }
    return ["ok":true,"confirmation":"Completed the requested action."]
}
extension Array {
    var only: Element? { count == 1 ? first : nil }
}
