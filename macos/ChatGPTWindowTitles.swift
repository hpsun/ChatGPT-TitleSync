// macOS draft — NOT compiled or tested on a Mac.
// Build on Mac: swiftc ChatGPTWindowTitles.swift -framework AppKit -framework ApplicationServices -o chatgpt-titlesync-swift
import AppKit
import ApplicationServices

// A shared per-user login preference and one LaunchAgent cover all Mac implementations.
// Source-only on this host: native macOS compilation and login behavior remain unverified.
enum TitleSyncStartup {
    static let preferences = UserDefaults(suiteName: "io.github.hpsun.ChatGPTTitleSync")!
    static var enabled: Bool {
        return preferences.object(forKey: "AutoStartEnabled") == nil ? true : preferences.bool(forKey: "AutoStartEnabled")
    }
    static func apply(_ wanted: Bool) throws {
        let manager = FileManager.default
        let directory = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let target = directory.appendingPathComponent("io.github.hpsun.ChatGPTTitleSync.plist")
        if wanted {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
            guard executable.path.hasPrefix("/"), manager.isExecutableFile(atPath: executable.path) else {
                throw NSError(domain: "TitleSyncStartup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Executable path is unavailable."])
            }
            let values: [String: Any] = ["Label": "io.github.hpsun.ChatGPTTitleSync", "ProgramArguments": [executable.path], "RunAtLoad": true, "KeepAlive": false]
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: target, options: .atomic)
        } else if manager.fileExists(atPath: target.path) {
            try manager.removeItem(at: target)
        }
        preferences.set(wanted, forKey: "AutoStartEnabled")
    }
}


extension TitleSyncStartup {
    struct Snapshot { let file: Data?; let preference: Any? }
    static var target: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/io.github.hpsun.ChatGPTTitleSync.plist")
    }
    static func checkpoint() throws -> Snapshot {
        let data: Data?
        if FileManager.default.fileExists(atPath: target.path) { data = try Data(contentsOf: target) } else { data = nil }
        return Snapshot(file: data, preference: preferences.object(forKey: "AutoStartEnabled"))
    }
    static func restore(_ before: Snapshot) throws {
        if let data = before.file {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: target, options: .atomic)
        } else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        if let value = before.preference { preferences.set(value, forKey: "AutoStartEnabled") }
        else { preferences.removeObject(forKey: "AutoStartEnabled") }
        guard preferences.synchronize() else { throw TitleSyncIcons.failure("Could not restore login preference.") }
    }
}

// Shared icon state is confined to the main/AppKit thread. This source-only
// implementation is unverified on native macOS; tests inject preferences/time/RNG.
final class TitleSyncIcons {
    struct State: Equatable {
        var mode = "fixed", fixed = 45, period = "day", random = 45, slot = ""
        var id: Int { mode == "fixed" ? fixed : random }
        var values: [String: Any] {
            ["IconMode": mode, "FixedIcon": fixed, "IconPeriod": period, "RandomIcon": random, "IconSlot": slot]
        }
    }
    struct Snapshot { let values: [String: Any]; let state: State }
    static let names = ["IconMode", "FixedIcon", "IconPeriod", "RandomIcon", "IconSlot"]
    let preferences: UserDefaults, assets: URL
    let clock: () -> Date, picker: ([Int]) -> Int
    var state = State()
    private var failedSlot: String?
    init(preferences: UserDefaults = TitleSyncStartup.preferences, assets: URL? = nil,
         clock: @escaping () -> Date = Date.init,
         picker: @escaping ([Int]) -> Int = { $0.randomElement()! }) {
        self.preferences = preferences; self.assets = assets ?? Self.findAssets()
        self.clock = clock; self.picker = picker
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "TitleSyncIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func findAssets() -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates += [resources.appendingPathComponent("themes"), resources.appendingPathComponent("assets/themes")]
        }
        candidates += [executable.deletingLastPathComponent().appendingPathComponent("assets/themes"),
                       executable.deletingLastPathComponent().appendingPathComponent("../assets/themes").standardizedFileURL]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? candidates[0]
    }
    static func slot(_ period: String, _ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        formatter.dateFormat = period == "day" ? "yyyyMMdd" : "yyyyMMddHHZ"
        if period != "5min" { return formatter.string(from: date) }
        formatter.dateFormat = "yyyyMMddHH"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let bin = calendar.component(.minute, from: date) / 5
        let head = formatter.string(from: date); formatter.dateFormat = "Z"
        return head + String(format: "%02d", bin) + formatter.string(from: date)
    }
    func image(_ id: Int) throws -> NSImage {
        guard (45...52).contains(id), let image = NSImage(contentsOf: assets.appendingPathComponent("\(id).png")), image.isValid else {
            throw Self.failure("Icon asset \(id) is unavailable.")
        }
        image.size = NSSize(width: 18, height: 18); image.isTemplate = false
        return image
    }
    func validate(_ value: State) throws {
        guard ["fixed", "random"].contains(value.mode), (45...52).contains(value.fixed),
              ["day", "hour", "5min"].contains(value.period), (45...52).contains(value.random) else {
            throw Self.failure("Invalid icon mode, palette or period.")
        }
        for id in value.mode == "random" ? Array(45...52) : [value.fixed] { _ = try image(id) }
    }
    func checkpoint() -> Snapshot {
        var values: [String: Any] = [:]
        for key in Self.names { values[key] = preferences.object(forKey: key) ?? NSNull() }
        return Snapshot(values: values, state: state)
    }
    func restore(_ before: Snapshot) throws {
        for key in Self.names {
            let old = before.values[key]!
            if old is NSNull { preferences.removeObject(forKey: key) } else { preferences.set(old, forKey: key) }
        }
        guard preferences.synchronize() else { throw Self.failure("Could not restore icon preferences.") }
        state = before.state
    }
    func prepare(mode: String, fixed: Int, period: String) throws -> State {
        var plan = state; plan.mode = mode; plan.fixed = fixed; plan.period = period
        try validate(plan)
        if mode == "random" {
            let currentSlot = Self.slot(period, clock())
            if state.mode != mode || state.period != period || state.slot != currentSlot {
                let choices = (45...52).filter { $0 != state.random }, selected = picker((45...52).filter { $0 != state.random })
                guard choices.contains(selected) else { throw Self.failure("Icon picker repeated or left the palette.") }
                plan.random = selected; plan.slot = currentSlot
            }
        }
        return plan
    }
    func commit(_ plan: State) throws {
        try validate(plan); let before = checkpoint()
        do {
            for (key, value) in plan.values {
                let unchanged = (preferences.object(forKey: key) as? NSObject)?.isEqual(value) ?? false
                if !unchanged { preferences.set(value, forKey: key) }
            }
            guard preferences.synchronize() else { throw Self.failure("Could not save icon preferences.") }
            for (key, value) in plan.values {
                guard let saved = preferences.object(forKey: key) as? NSObject, saved.isEqual(value) else {
                    throw Self.failure("Icon preference readback failed.")
                }
            }
        } catch {
            do { try restore(before) } catch { throw Self.failure("Icon save and rollback failed.") }
            throw error
        }
        state = plan; failedSlot = nil
    }
    func initialize() throws {
        var value = State()
        func text(_ key: String, _ fallback: String) throws -> String {
            guard let raw = preferences.object(forKey: key) else { return fallback }
            guard let result = raw as? String else { throw Self.failure("Invalid type for \(key).") }; return result
        }
        func number(_ key: String, _ fallback: Int) throws -> Int {
            guard let raw = preferences.object(forKey: key) else { return fallback }
            guard let result = raw as? NSNumber, result.doubleValue == Double(result.intValue) else { throw Self.failure("Invalid type for \(key).") }; return result.intValue
        }
        value.mode = try text("IconMode", "fixed"); value.fixed = try number("FixedIcon", 45)
        value.period = try text("IconPeriod", "day"); value.random = try number("RandomIcon", 45); value.slot = try text("IconSlot", "")
        try validate(value); state = value
        if value.mode == "random" {
            let plan = try prepare(mode: value.mode, fixed: value.fixed, period: value.period)
            if plan != value { try commit(plan) }
        }
    }
    func tick(report: (String) -> Void) -> Bool {
        guard state.mode == "random" else { return false }
        let currentSlot = Self.slot(state.period, clock())
        guard currentSlot != state.slot, currentSlot != failedSlot else { return false }
        do { try commit(prepare(mode: state.mode, fixed: state.fixed, period: state.period)); return true }
        catch { failedSlot = currentSlot; report(currentSlot); return false }
    }
}

// Legacy preferences domain retained so existing settings survive the product rename.
let scanPreferences = UserDefaults(suiteName: "org.chatgpt-title.swift")!

final class WindowRecord {
    let window: AXUIElement
    let pid: pid_t
    let launched: Date
    let token: Int
    var original: String?
    var lastWritten: String?
    var retry = Date.distantPast
    var cachedTitle: String?
    var rawSourceName: String? // Verified source, never a formatted display value.
    var nextForegroundRead = Date.distantPast
    var nextBackgroundRead = Date.distantPast
    var manualOverride = false
    var sourceRevision = 0 // state-queue-only; newer reads invalidate older role results
    var observedForeground: Bool?
    init(_ window: AXUIElement, _ pid: pid_t, _ launched: Date, _ token: Int) {
        self.window = window; self.pid = pid; self.launched = launched; self.token = token
    }
}
func axValue(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
    return value
}
func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
    return axValue(element, attribute) as? String
}
func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    return axValue(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
}
// Candidate Mac locator: bounded native envelope only; NEVER enter AXWebArea children.
// The actual ChatGPT Mac hierarchy is unverified. Ambiguity/failure is reported.
func conversationTitle(_ window: AXUIElement, stillActive: () -> Bool) throws -> String {
    let containers: Set<String> = ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea"]
    var queue: [(AXUIElement, Int)] = [(window, 0)]
    var head = 0
    let deadline = Date().addingTimeInterval(2)
    var documents: [AXUIElement] = []
    while head < queue.count {
        guard stillActive() && head < 64 && Date() < deadline else { throw NSError(domain: "AXTitleDraft", code: 1, userInfo: [NSLocalizedDescriptionKey: "native envelope exceeds 64 nodes"]) }
        let (node, depth) = queue[head]; head += 1
        _ = AXUIElementSetMessagingTimeout(node, 0.5)
        guard let role = axString(node, kAXRoleAttribute as CFString) else {
            throw NSError(domain: "AXTitleDraft", code: 2, userInfo: [NSLocalizedDescriptionKey: "AXRole unreadable"])
        }
        if role == "AXWebArea" { documents.append(node); continue }
        if containers.contains(role) {
            guard depth < 8 else { throw NSError(domain: "AXTitleDraft", code: 3, userInfo: [NSLocalizedDescriptionKey: "native envelope depth exceeded"]) }
            guard let children = axValue(node, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
                throw NSError(domain: "AXTitleDraft", code: 4, userInfo: [NSLocalizedDescriptionKey: "AXChildren unreadable"])
            }
            guard queue.count + children.count <= 64 else { throw NSError(domain: "AXTitleDraft", code: 1) }; queue += children.map { ($0, depth + 1) }
        }
    }
    guard documents.count == 1, let title = axString(documents[0], kAXTitleAttribute as CFString),
          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 512,
          stillActive() else {
        throw NSError(domain: "AXTitleDraft", code: 5, userInfo: [NSLocalizedDescriptionKey: "current conversation title unavailable or ambiguous"])
    }
    return title
}
final class Monitor: NSObject, NSApplicationDelegate {
    let queue = DispatchQueue(label: "ChatGPTTitleDraft.State")
    let foregroundQueue = DispatchQueue(label: "ChatGPTTitleDraft.Foreground")
    let backgroundQueue = DispatchQueue(label: "ChatGPTTitleDraft.Background")
    var foregroundBusy = false
    var backgroundBusy = false
    var status: NSStatusItem!
    var timer: Timer?
    var records: [WindowRecord] = [] // accessed only on queue
    var nextToken = 1
    var paused = false              // accessed only on main
    var queued = false
    var generation = 0 // main-thread pause/exit revision
    var quitting = false
    var lines = ["尚未检查；Mac AX 行为未实机验证"]
    let bundleID: String = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--bundle-id"), i + 1 < args.count { return args[i + 1] }
        return "com.openai.chat" // expected identifier; verify on target Mac or use --bundle-id
    }()
    // Rules have a separate presentation generation and never reset source deadlines.
    lazy var nameRules: CTSRulesClient = {
        let executable = CommandLine.arguments[0]
        let state = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChatGPT-TitleSync/runtime/swift").path
        return CTSRulesClient(executablePath: CTSRulesCompanionPath(executable), rulesPath: CTSRulesDefaultPath(), stateDirectory: state)
    }()
    var lastRulesDisplayRevision: UInt64 = 0
    let timingLock = NSLock()
    var settingsPanel: NSPanel?
    var foregroundInput: NSTextField?
    var backgroundInput: NSTextField?
    var settingsMessage: NSTextField?
    var autoStartInput: NSButton?
    let icons = TitleSyncIcons()
    var iconModeInput: NSPopUpButton?
    var fixedIconInput: NSPopUpButton?
    var iconPeriodInput: NSPopUpButton?
    var autoStartEnabled = TitleSyncStartup.enabled
    var interval: TimeInterval = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--interval"), i + 1 < args.count, let value = Double(args[i + 1]), value >= 1, value <= 3600 { return value }
        let saved = (scanPreferences.dictionary(forKey: "ScanIntervals")?["ForegroundSeconds"] as? NSNumber)?.intValue ?? 2
        return TimeInterval((1...3600).contains(saved) ? saved : 2)
    }()
    var backgroundInterval: TimeInterval = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--background-interval"), i + 1 < args.count,
           let value = Double(args[i + 1]), value >= 5, value <= 3600 { return value }
        let saved = (scanPreferences.dictionary(forKey: "ScanIntervals")?["BackgroundSeconds"] as? NSNumber)?.intValue ?? 5
        return TimeInterval((5...3600).contains(saved) ? saved : 5)
    }()
    func log(_ event: String, _ record: WindowRecord? = nil, _ error: String? = nil) {
        var row: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "event": event]
        if let record = record { row["pid"] = record.pid; row["windowToken"] = record.token }
        if let error = error { row["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "GPT"
        status.button?.toolTip = "ChatGPT-TitleSync / ChatGPT 标题同步助手"
        do { try icons.initialize() } catch { log("icon_preferences_failed", nil, error.localizedDescription) }
        do { applyIcon(try icons.image(icons.state.id)) } catch { log("icon_load_failed", nil, "baseline_or_saved_asset") }
        do { try TitleSyncStartup.apply(autoStartEnabled) }
        catch { autoStartEnabled = false; lines.append("登录自启动失败：\(error.localizedDescription)"); log("startup_registration_failed", nil, error.localizedDescription) }
        rebuildMenu()
        // Repeating Timer is deadline-based; it is not scheduled after an AX pass completes.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateIconForSlot(); self?.enqueueScan() }
        enqueueScan()
    }
    func applyIcon(_ image: NSImage) {
        status.button?.image = image; status.button?.title = ""
        NSApp.applicationIconImage = image
    }
    func updateIconForSlot() {
        guard !quitting else { return }
        if icons.tick(report: { slot in self.log("icon_rotation_failed", nil, slot) }) {
            do { applyIcon(try icons.image(icons.state.id)) } catch { log("icon_load_failed", nil, icons.state.slot) }
        }
    }
    @objc func iconModeChanged() {
        fixedIconInput?.isEnabled = iconModeInput?.indexOfSelectedItem == 0
        iconPeriodInput?.isEnabled = iconModeInput?.indexOfSelectedItem == 1
    }
    func rebuildMenu() {
        let menu = NSMenu()
        let state = NSMenuItem(title: paused ? "已暂停；关闭功能后尝试还原" : "监听中（每 \(interval) 秒）", action: nil, keyEquivalent: "")
        state.isEnabled = false; menu.addItem(state)
        for line in lines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false; menu.addItem(item)
        }
        menu.addItem(.separator())
        let startup = NSMenuItem(title: "开机自启动 / Start at sign-in", action: #selector(toggleAutoStart), keyEquivalent: "")
        startup.target = self; startup.state = autoStartEnabled ? .on : .off; menu.addItem(startup)
        let timing = NSMenuItem(title: "扫描间隔设置…", action: #selector(showScanSettings), keyEquivalent: "")
        timing.target = self; menu.addItem(timing)
        let replacements = NSMenuItem(title: "Name replacement… / 名称替换…", action: #selector(showNameReplacement), keyEquivalent: "")
        replacements.target = self; menu.addItem(replacements)
        let pause = NSMenuItem(title: paused ? "恢复监听" : "暂停并还原", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)
        let permission = NSMenuItem(title: "检查／请求辅助功能权限", action: #selector(requestPermission), keyEquivalent: "")
        permission.target = self; menu.addItem(permission)
        let quit = NSMenuItem(title: "退出并还原", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        status.menu = menu
    }
    @objc func showNameReplacement() {
        // Snapshot only already-observed names on their owning queue. The editor
        // has no AX reader and cannot modify a conversation or source cadence.
        queue.async {
            self.nameRules.publishSources(self.records.compactMap { $0.rawSourceName })
            DispatchQueue.main.async {
                if let error = CTSRulesOpenEditor(self.nameRules, CTSRulesHelpPath(CommandLine.arguments[0])) {
                    let alert = NSAlert(); alert.messageText = "Name replacement"; alert.informativeText = error; alert.runModal()
                }
            }
        }
    }
    @objc func toggleAutoStart() {
        let wanted = !autoStartEnabled
        do {
            try TitleSyncStartup.apply(wanted)
            autoStartEnabled = wanted; autoStartInput?.state = wanted ? .on : .off; rebuildMenu()
        } catch {
            let alert = NSAlert(); alert.messageText = "开机自启动"; alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
    // A modeless panel keeps the event loop responsive while editing settings.
    func timingSnapshot() -> (TimeInterval, TimeInterval) {
        timingLock.lock(); defer { timingLock.unlock() }
        return (interval, backgroundInterval)
    }
    @objc func showScanSettings() {
        if settingsPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "ChatGPT-TitleSync — 扫描间隔设置"; panel.isReleasedWhenClosed = false
            let view = panel.contentView!
            for (text, y) in [("前台来源读取（秒）：", 298.0), ("后台来源刷新（秒）：", 262.0)] {
                let label = NSTextField(labelWithString: text)
                label.frame = NSRect(x: 14, y: y, width: 190, height: 24); view.addSubview(label)
            }
            let fg = NSTextField(frame: NSRect(x: 222, y: 298, width: 110, height: 24))
            let bg = NSTextField(frame: NSRect(x: 222, y: 262, width: 110, height: 24))
            view.addSubview(fg); view.addSubview(bg); foregroundInput = fg; backgroundInput = bg
            let startup = NSButton(checkboxWithTitle: "开机自启动 / Start at sign-in", target: nil, action: nil)
            startup.frame = NSRect(x: 14, y: 337, width: 360, height: 24); view.addSubview(startup); autoStartInput = startup
            let hint = NSTextField(labelWithString: "前台1–3600秒；后台5–3600秒。原生标题维护固定1秒。")
            hint.font = NSFont.systemFont(ofSize: 11); hint.frame = NSRect(x: 14, y: 230, width: 365, height: 22); view.addSubview(hint)
            let message = NSTextField(labelWithString: "")
            message.textColor = .systemRed; message.font = NSFont.systemFont(ofSize: 11)
            message.frame = NSRect(x: 14, y: 43, width: 365, height: 22); view.addSubview(message); settingsMessage = message
            let save = NSButton(title: "保存", target: self, action: #selector(saveScanSettings))
            save.frame = NSRect(x: 216, y: 8, width: 76, height: 28); save.keyEquivalent = "\r"; view.addSubview(save)
            let cancel = NSButton(title: "取消", target: self, action: #selector(cancelScanSettings))
            cancel.frame = NSRect(x: 300, y: 8, width: 76, height: 28); cancel.keyEquivalent = "\u{1b}"; view.addSubview(cancel)
            let definitions: [(String, Double, [String])] = [
                ("图标模式 / Icon mode", 186, ["固定 / Fixed", "随机 / Random"]),
                ("固定配色 / Palette", 150, (45...52).map(String.init)),
                ("随机周期 / Period", 114, ["每日 / Daily", "每小时 / Hourly", "每5分钟 / Every 5 minutes"])]
            var choices: [NSPopUpButton] = []
            for (labelText, y, values) in definitions {
                let label = NSTextField(labelWithString: labelText); label.frame = NSRect(x: 14, y: y, width: 200, height: 24); view.addSubview(label)
                let popup = NSPopUpButton(frame: NSRect(x: 222, y: y, width: 190, height: 26), pullsDown: false)
                popup.addItems(withTitles: values); view.addSubview(popup); choices.append(popup)
            }
            let replacements = NSButton(title: "Name replacement… / 名称替换…", target: self, action: #selector(showNameReplacement))
            replacements.frame = NSRect(x: 14, y: 73, width: 398, height: 28); view.addSubview(replacements)
            iconModeInput = choices[0]; fixedIconInput = choices[1]; iconPeriodInput = choices[2]
            iconModeInput?.target = self; iconModeInput?.action = #selector(iconModeChanged)
            settingsPanel = panel
        }
        foregroundInput?.stringValue = String(Int(interval)); backgroundInput?.stringValue = String(Int(backgroundInterval))
        autoStartInput?.state = autoStartEnabled ? .on : .off
        iconModeInput?.selectItem(at: icons.state.mode == "fixed" ? 0 : 1)
        fixedIconInput?.selectItem(at: icons.state.fixed - 45)
        iconPeriodInput?.selectItem(at: ["day", "hour", "5min"].firstIndex(of: icons.state.period) ?? 0)
        iconModeChanged()
        settingsMessage?.stringValue = ""; settingsPanel?.center(); settingsPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func cancelScanSettings() { settingsPanel?.orderOut(nil) }
    @objc func saveScanSettings() {
        guard let fgText = foregroundInput?.stringValue, let bgText = backgroundInput?.stringValue,
              let fg = Int(fgText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let bg = Int(bgText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...3600).contains(fg), (5...3600).contains(bg) else {
            settingsMessage?.stringValue = "请输入整数：前台1–3600秒，后台5–3600秒。"; return
        }
        let wantedStartup = autoStartInput?.state == .on
        let modeIndex = iconModeInput?.indexOfSelectedItem ?? -1, fixedIndex = fixedIconInput?.indexOfSelectedItem ?? -1, periodIndex = iconPeriodInput?.indexOfSelectedItem ?? -1
        guard (0...1).contains(modeIndex), (0...7).contains(fixedIndex), (0...2).contains(periodIndex) else { settingsMessage?.stringValue = "Choose all icon settings."; return }
        let plan: TitleSyncIcons.State, image: NSImage
        do {
            plan = try icons.prepare(mode: modeIndex == 0 ? "fixed" : "random",
                fixed: 45 + fixedIndex,
                period: ["day", "hour", "5min"][periodIndex])
            image = try icons.image(plan.id) // Validate/load before startup or preference writes.
        } catch { settingsMessage?.stringValue = error.localizedDescription; return }
        let beforeIcons = icons.checkpoint(), beforeScan = scanPreferences.object(forKey: "ScanIntervals")
        let beforeStartup: TitleSyncStartup.Snapshot
        do { beforeStartup = try TitleSyncStartup.checkpoint() }
        catch { settingsMessage?.stringValue = error.localizedDescription; return }
        do {
            try TitleSyncStartup.apply(wantedStartup); try icons.commit(plan)
            scanPreferences.set(["ForegroundSeconds": fg, "BackgroundSeconds": bg], forKey: "ScanIntervals")
            guard scanPreferences.synchronize(),
                (scanPreferences.dictionary(forKey: "ScanIntervals")?["ForegroundSeconds"] as? NSNumber)?.intValue == fg,
                (scanPreferences.dictionary(forKey: "ScanIntervals")?["BackgroundSeconds"] as? NSNumber)?.intValue == bg else {
                throw TitleSyncIcons.failure("Could not verify interval settings.")
            }
        } catch {
            var message = error.localizedDescription
            do { try icons.restore(beforeIcons) } catch { message += "; icon rollback failed" }
            do { try TitleSyncStartup.restore(beforeStartup) } catch { message += "; startup rollback failed" }
            if let old = beforeScan { scanPreferences.set(old, forKey: "ScanIntervals") }
            else { scanPreferences.removeObject(forKey: "ScanIntervals") }
            if !scanPreferences.synchronize() { message += "; interval rollback failed" }
            settingsMessage?.stringValue = message; return
        }
        autoStartEnabled = wantedStartup; applyIcon(image)
        generation += 1
        timingLock.lock(); interval = TimeInterval(fg); backgroundInterval = TimeInterval(bg); timingLock.unlock()
        queue.async {
            for record in self.records {
                record.sourceRevision += 1; record.nextForegroundRead = .distantPast; record.nextBackgroundRead = .distantPast
            }
        }
        settingsPanel?.orderOut(nil); rebuildMenu(); enqueueScan(); log("scan_intervals_changed")
    }
    @objc func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options) // user decides; never change privacy settings
        enqueueScan()
    }
    func identityAlive(_ record: WindowRecord) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: record.pid),
              app.launchDate == record.launched, !app.isTerminated else { return false }
        var pid: pid_t = 0
        return AXUIElementGetPid(record.window, &pid) == .success && pid == record.pid
    }
    func releaseChangedLease(_ record: WindowRecord, current: String) {
        guard let last = record.lastWritten, current != last else { return }
        record.original = nil; record.lastWritten = nil
        log("lease_released_external_caption", record)
    }
    func restoreAll() {
        for record in records {
            guard let last = record.lastWritten, let original = record.original else { continue }
            guard identityAlive(record), let current = axString(record.window, kAXTitleAttribute as CFString) else {
                log("restore_skipped_identity_or_external_change", record); continue
            }
            guard current == last else {
                releaseChangedLease(record, current: current)
                log("restore_skipped_identity_or_external_change", record); continue
            }
            let result = AXUIElementSetAttributeValue(record.window, kAXTitleAttribute as CFString, original as CFString)
            if result == .success && identityAlive(record) && axString(record.window, kAXTitleAttribute as CFString) == original {
                log("restored", record); record.lastWritten = nil; record.original = nil
            } else { log("restore_failed", record, "AXError \(result.rawValue)") }
        }
    }
    @objc func togglePause() {
        generation += 1; paused.toggle()
        if paused {
            queue.async { self.restoreAll() }
            lines = ["已暂停；还原请求已排队，结果见日志"]
        } else { enqueueScan() }
        rebuildMenu()
    }
    @objc func quit() {
        guard !quitting else { return }
        generation += 1; quitting = true; timer?.invalidate()
        queue.async {
            self.restoreAll()
            self.nameRules.publishSources([]); self.nameRules.dispose()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
    func enqueueScan() {
        guard !paused, !queued, !quitting else { return }
        queued = true
        queue.async {
            let rows = self.scan()
            DispatchQueue.main.async {
                self.queued = false
                if !self.paused { self.lines = rows; self.rebuildMenu() }
            }
        }
    }
    // Native app check happens first; no AX is queried for a non-target foreground app.
    func focusedTarget() -> (AXUIElement, pid_t, Date)? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID,
              let launched = front.launchDate, !front.isTerminated else { return nil }
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide(); _ = AXUIElementSetMessagingTimeout(system, 0.5)
        guard let appRef = axValue(system, kAXFocusedApplicationAttribute as CFString), CFGetTypeID(appRef) == AXUIElementGetTypeID() else { return nil }
        let axApp = appRef as! AXUIElement; var pid: pid_t = 0
        guard AXUIElementGetPid(axApp, &pid) == .success, pid == front.processIdentifier else { return nil }
        _ = AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard let winRef = axValue(axApp, kAXFocusedWindowAttribute as CFString), CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        let window = winRef as! AXUIElement; _ = AXUIElementSetMessagingTimeout(window, 0.5)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        return (window, pid, launched)
    }
    func active(_ record: WindowRecord) -> Bool {
        guard let (window,pid,launched) = focusedTarget() else { return false }
        return pid == record.pid && launched == record.launched && CFEqual(window, record.window)
    }
    // Only this serial state queue owns leases. Source reads use independent queues.
    func allowed() -> Bool {
        if Thread.isMainThread { return !paused && !quitting }
        return DispatchQueue.main.sync { !self.paused && !self.quitting }
    }
    func generic(_ title: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.caseInsensitiveCompare("ChatGPT") == .orderedSame
    }
    func eligible(_ record: WindowRecord, foreground: Bool) -> Bool {
        return allowed() && identityAlive(record) && active(record) == foreground
    }
    // Enumerate only target-app window metadata, never another app or web-area children.
    func discover() -> [WindowRecord] {
        guard AXIsProcessTrusted() else { return [] }
        var found: [WindowRecord] = []
        var completeSnapshots: [(pid_t, Date, [AXUIElement])] = []
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).prefix(16) {
            guard let launched = app.launchDate, !app.isTerminated else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            _ = AXUIElementSetMessagingTimeout(appElement, 0.5)
            guard let windows = axValue(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] else { continue }
            // Failed or capped enumerations cannot prove that an old window closed.
            if windows.count <= 64 { completeSnapshots.append((app.processIdentifier, launched, windows)) }
            for window in windows.prefix(64) {
                _ = AXUIElementSetMessagingTimeout(window, 0.5)
                if let old = records.first(where: { $0.pid == app.processIdentifier && $0.launched == launched && CFEqual($0.window, window) }) {
                    found.append(old)
                } else {
                    let record = WindowRecord(window, app.processIdentifier, launched, nextToken)
                    nextToken += 1; records.append(record); found.append(record)
                }
            }
        }
        // Retire closed AX windows only after a successful complete snapshot for that app.
        records.removeAll { record in
            if !identityAlive(record) { return true }
            guard let snapshot = completeSnapshots.first(where: { $0.0 == record.pid && $0.1 == record.launched }) else { return false }
            return !snapshot.2.contains(where: { CFEqual($0, record.window) })
        }
        let retained = Set(records.map { ObjectIdentifier($0) })
        return found.filter { retained.contains(ObjectIdentifier($0)) }
    }
    @discardableResult func write(_ record: WindowRecord, wanted: String, expected: String, foreground: Bool) -> Bool {
        guard eligible(record, foreground: foreground), axString(record.window, kAXTitleAttribute as CFString) == expected else { return false }
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(record.window, kAXTitleAttribute as CFString, &writable) == .success && writable.boolValue else { return false }
        releaseChangedLease(record, current: expected)
        let original = record.original ?? expected
        let result = AXUIElementSetAttributeValue(record.window, kAXTitleAttribute as CFString, wanted as CFString)
        guard result == .success else { log("caption_write_failed", record); return false }
        // Keep ownership after a successful write even if focus changes before readback.
        record.original = original; record.lastWritten = wanted
        let verified = identityAlive(record) && axString(record.window, kAXTitleAttribute as CFString) == wanted
        log(verified ? "caption_written" : "caption_readback_unconfirmed", record)
        return verified
    }
    func applySource(_ record: WindowRecord, name: String, foreground: Bool) {
        guard records.contains(where: { $0 === record }), eligible(record, foreground: foreground),
              let current = axString(record.window, kAXTitleAttribute as CFString) else { return }
        releaseChangedLease(record, current: current)
        if generic(name) {
            record.cachedTitle = nil; record.rawSourceName = nil
            nameRules.publishSources(records.compactMap { $0.rawSourceName })
            if current == record.lastWritten, let original = record.original {
                if write(record, wanted: original, expected: current, foreground: foreground) { record.lastWritten = nil; record.original = nil }
            }
            return
        }
        record.rawSourceName = name
        nameRules.publishSources(records.compactMap { $0.rawSourceName })
        guard let display = nameRules.resolve(name) else { record.cachedTitle = nil; return }
        let wanted = display + " — ChatGPT"
        record.cachedTitle = wanted
        if generic(current) { record.manualOverride = false }
        if current == wanted { return }
        if !generic(current) && current != record.lastWritten {
            record.manualOverride = true; log("custom_caption_preserved", record); return
        }
        guard !record.manualOverride else { return }
        _ = write(record, wanted: wanted, expected: current, foreground: foreground)
    }
    func startSource(_ record: WindowRecord, foreground: Bool) {
        record.sourceRevision += 1
        let sourceRevision = record.sourceRevision
        let timing = timingSnapshot()
        if foreground { foregroundBusy = true; record.nextForegroundRead = Date().addingTimeInterval(timing.0) }
        else { backgroundBusy = true; record.nextBackgroundRead = Date().addingTimeInterval(timing.1) }
        let revision = DispatchQueue.main.sync { self.generation }
        let worker = foreground ? foregroundQueue : backgroundQueue
        worker.async {
            var name: String?
            do { name = try conversationTitle(record.window, stillActive: { self.eligible(record, foreground: foreground) && DispatchQueue.main.sync { self.generation == revision } }) }
            catch { name = nil }
            let result = name
            self.queue.async {
                if foreground { self.foregroundBusy = false } else { self.backgroundBusy = false }
                guard self.allowed(), DispatchQueue.main.sync(execute: { self.generation == revision }),
                      record.sourceRevision == sourceRevision else { return }
                if let title = result { self.applySource(record, name: title, foreground: foreground) }
                else { self.log("source_read_failed_or_role_changed", record) }
            }
        }
    }
    // A display-only completion can repaint an owned caption without taking a
    // fresh AX source sample, invalidating a source request, or changing timing.
    func refreshRuleDisplays() {
        nameRules.poll()
        let revision = nameRules.displayRevision
        guard revision != lastRulesDisplayRevision else { return }
        lastRulesDisplayRevision = revision
        for record in records {
            guard let raw = record.rawSourceName, let display = nameRules.resolve(raw) else { continue }
            let wanted = display + " — ChatGPT"
            let previous = record.cachedTitle; record.cachedTitle = wanted
            guard previous != wanted, !record.manualOverride,
                  let current = axString(record.window, kAXTitleAttribute as CFString),
                  let last = record.lastWritten, current == last else { continue }
            _ = write(record, wanted: wanted, expected: current, foreground: active(record))
        }
    }
    func scan() -> [String] {
        guard allowed(), AXIsProcessTrusted() else { return ["Accessibility permission required"] }
        let timing = timingSnapshot()
        let candidates = discover()
        nameRules.publishSources(records.compactMap { $0.rawSourceName })
        refreshRuleDisplays()
        var foreground: WindowRecord?
        let now = Date()
        for record in candidates {
            let isForeground = active(record)
            if let previous = record.observedForeground, previous != isForeground { record.sourceRevision += 1 }
            record.observedForeground = isForeground
            if isForeground { foreground = record; continue }
            guard let current = axString(record.window, kAXTitleAttribute as CFString) else { continue }
            releaseChangedLease(record, current: current)
            // Reset repair uses only remembered source data; it never starts a source read.
            if generic(current), let cached = record.cachedTitle {
                record.manualOverride = false
                if write(record, wanted: cached, expected: current, foreground: false) { log("background_reset_repaired_from_cache", record) }
            } else if current != record.lastWritten && !generic(current) {
                record.manualOverride = true
            }
        }
        if let record = foreground, !foregroundBusy, (timing.0 <= 1 || now >= record.nextForegroundRead) {
            startSource(record, foreground: true) // Never restore the active window from cache.
        }
        if !backgroundBusy, let due = candidates.filter({ !active($0) && now >= $0.nextBackgroundRead }).min(by: { $0.nextBackgroundRead < $1.nextBackgroundRead }) {
            startSource(due, foreground: false)
        }
        return ["Foreground source: \(timing.0)s; background source: \(timing.1)s", "Background reset repair: 1s, cached titles only"]
    }
}

// CLI-built accessory app; keep the delegate strongly owned for the run-loop lifetime.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let monitor = Monitor()
application.delegate = monitor
application.run()
