import AppKit
import ServiceManagement

/// 터미널 없이 앱 혼자서 Claude Code(~/.claude/settings.json)에 훅을 연결하고 떼어 낸다.
/// hooks/install-hooks.py 와 같은 일을 한다. 훅 스크립트는 앱 번들에서 ~/.clawd-touchbar/bin 으로 복사해 두고
/// 그 경로를 적어서, 앱을 다른 폴더로 옮겨도 연결이 끊기지 않게 한다.
enum ClaudeSetup {
    static let settingsFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    static let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".clawd-touchbar/bin")
    static var hookScript: String { scriptsDir.appendingPathComponent("clawd-hook.sh").path }
    static var statusScript: String { scriptsDir.appendingPathComponent("clawd-statusline.sh").path }

    private static let events: [(String, String?)] = [
        ("UserPromptSubmit", nil), ("PreToolUse", "*"), ("PostToolUse", "*"),
        ("Notification", nil), ("Stop", nil), ("SessionEnd", nil),
    ]

    /// 앱 번들 안의 훅 스크립트를 ~/.clawd-touchbar/bin 에 복사한다 (실행할 때마다 최신으로)
    static func installScripts() {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("hooks") else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        for name in ["clawd-hook.sh", "clawd-statusline.sh"] {
            let from = source.appendingPathComponent(name)
            let to = scriptsDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: to)
            try? fm.copyItem(at: from, to: to)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: to.path)
        }
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String ?? "").hasSuffix("clawd-hook.sh")
    }

    private static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func save(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsFile.path) {
            let backup = settingsFile.appendingPathExtension("bak-clawd")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: settingsFile, to: backup)
        }
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: settingsFile)
    }

    /// 훅이 연결되어 있고, 가리키는 스크립트가 실제로 있는지
    static var isConnected: Bool {
        let hooks = load()["hooks"] as? [String: Any] ?? [:]
        for (_, groups) in hooks {
            for group in groups as? [[String: Any]] ?? [] {
                for entry in group["hooks"] as? [[String: Any]] ?? [] where isOurs(entry) {
                    return FileManager.default.fileExists(atPath: entry["command"] as? String ?? "")
                }
            }
        }
        return false
    }

    /// 훅 6개와 (비어 있을 때만) statusLine을 연결한다. 돌려주는 글은 사용자에게 보여 줄 안내.
    @discardableResult
    static func connect() throws -> String {
        installScripts()
        var settings = load()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, matcher) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var found = false
            for g in groups.indices {
                var entries = groups[g]["hooks"] as? [[String: Any]] ?? []
                for e in entries.indices where isOurs(entries[e]) {
                    entries[e]["command"] = hookScript   // 예전 위치를 가리키고 있으면 지금 위치로
                    found = true
                }
                groups[g]["hooks"] = entries
            }
            if !found {
                var group: [String: Any] = ["hooks": [["type": "command", "command": hookScript, "timeout": 5]]]
                if let matcher { group["matcher"] = matcher }
                groups.append(group)
            }
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        var note = tr("Claude Code와 연결했어요. 새로 시작하는 Claude Code 세션부터 Clawd가 따라 움직여요.", "Connected to Claude Code. Clawd will follow along from your next new Claude Code session.")
        let current = (settings["statusLine"] as? [String: Any])?["command"] as? String ?? ""
        if current.isEmpty || current.hasSuffix("clawd-statusline.sh") {
            settings["statusLine"] = ["type": "command", "command": statusScript]
        } else {
            note += tr("\n\n이미 다른 상태줄(statusLine)을 쓰고 있어서 그대로 두었어요. Claude 사용량 표시만 빠져요.", "\n\nYou already use your own statusLine, so it was left as is. Only the Claude usage display will be missing.")
        }
        try save(settings)
        return note
    }

    /// 우리 훅과 statusLine만 떼어 내고 나머지는 그대로 둔다
    static func disconnect() throws {
        var settings = load()
        guard !settings.isEmpty else { return }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in Array(hooks.keys) {
            let groups = (hooks[event] as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var g = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
                guard !entries.isEmpty else { return nil }
                g["hooks"] = entries
                return g
            }
            if groups.isEmpty { hooks[event] = nil } else { hooks[event] = groups }
        }
        if hooks.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = hooks }
        if ((settings["statusLine"] as? [String: Any])?["command"] as? String ?? "").hasSuffix("clawd-statusline.sh") {
            settings["statusLine"] = nil
        }
        try save(settings)
    }

    // MARK: - 로그인 시 자동 실행 (macOS 13+)

    static var canAutoLaunch: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    static var launchesAtLogin: Bool {
        get {
            if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
            return false
        }
        set {
            guard #available(macOS 13, *) else { return }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("로그인 항목 설정 실패: \(error)")
            }
        }
    }

    // MARK: - Touch Bar가 있는 맥인지

    /// Touch Bar가 달린 모델(2016~2020 MacBook Pro, M1 13형). 아니면 화면 위 모드를 기본으로 켠다.
    static var hasTouchBar: Bool {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let model = String(cString: buffer)
        let touchBarModels = ["MacBookPro13,2", "MacBookPro13,3", "MacBookPro14,2", "MacBookPro14,3",
                              "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
                              "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
                              "MacBookPro17,1"]
        return touchBarModels.contains(model)
    }
}
