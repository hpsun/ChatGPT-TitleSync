import Foundation

// Compile only. Never call executeAndReturnError or any script handler.
guard CommandLine.arguments.count == 2 else {
    print("Usage: swift tools/diagnose-applescript.swift <AppleScript source>")
    exit(2)
}
let input = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
func diagnose(_ label: String, _ source: String) {
    let text = source as NSString
    print("SOURCE \(label) utf16=\(text.length)")
    guard let script = NSAppleScript(source: source) else { print("CREATE_FAILED"); return }
    var error: NSDictionary?
    let ok = script.compileAndReturnError(&error)
    print("COMPILED \(ok)")
    if let details = error { print("ERROR_DICTIONARY \(details)") }
    guard !ok, let value = error?[NSAppleScript.errorRange] as? NSValue else { return }
    let range = value.rangeValue
    print("ERROR_UTF16_RANGE location=\(range.location) length=\(range.length)")
    guard range.location != NSNotFound && range.location <= text.length else { return }
    let low = max(0, range.location - 100)
    let high = min(text.length, range.location + max(1, range.length) + 100)
    let context = text.substring(with: NSRange(location: low, length: high - low))
    print("ERROR_CONTEXT \(String(reflecting: context))")
    if range.length <= text.length - range.location {
        print("ERROR_TOKEN \(String(reflecting: text.substring(with: range)))")
    }
}
diagnose("raw", input)
let lf = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
diagnose("LF-only", lf)