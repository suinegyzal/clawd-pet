import AppKit

/// Claude Code 훅(hooks/clawd-hook.sh)이 ~/.clawd-touchbar/events 에 떨군 JSON을 읽어
/// 세션마다 "지금 무엇을 하고 있는지"를 정리한다.
final class ClaudeLink {
    enum Work: Equatable {
        case think      // 프롬프트를 받고 생각 중
        case study      // 읽기·검색 → 공부
        case exercise   // 명령 실행 → 운동
        case craft      // 파일 수정 등 → 작업
    }

    enum Status: Equatable {
        case working(Work, String)
        case waiting(String)    // 권한 확인처럼 사람이 봐 줘야 하는 상태
        case done(String)       // 방금 끝낸 일 요약
    }

    struct Session {
        let id: String
        var status: Status
        var lastEvent: Date
        var prompt = ""
        var promptAt: Date?
        /// 이번 일을 시작한 때 (오래 걸릴수록 Clawd가 짜증을 낸다)
        var workStart: Date
        /// Stop을 받았지만 마지막 답변이 아직 대화 기록에 안 써졌을 때
        var pendingStop: (transcript: String?, at: Date)?
        var transcript: String?
        /// 세션 제목(주제). 제목은 도중에 생기거나 바뀔 수 있어서 가끔 다시 읽는다.
        var topic: String?
        var topicCheckedAt = Date.distantPast
        /// 이 세션이 도는 앱의 실행 파일 (훅이 적어 준다). 완료를 확인하면 이 앱을 앞으로 가져온다
        var appPath: String?
        /// 아이디어 리서치 루틴 세션: 끝나도 완료 알림 대신 아이디어 말풍선으로 알린다
        var isRoutine = false
    }

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".clawd-touchbar/events", isDirectory: true)

    private let directory: URL
    private(set) var sessions: [String: Session] = [:] {
        didSet { savePendingIfChanged() }
    }
    private(set) var lastEventAt: Date?
    private let startedAt = Date()
    private let staleAfter: TimeInterval = 30
    private let workTimeout: TimeInterval = 1800

    /// 확인 안 한 완료 알림을 앱을 다시 켜도 잃지 않게 저장해 두는 곳
    static let pendingFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".clawd-touchbar/pending-done.json")
    private let pendingFile: URL?
    private var savedPending: [[String: String]] = []

    init(directory: URL = ClaudeLink.directory, pendingFile: URL? = nil) {
        self.directory = directory
        self.pendingFile = pendingFile
        restorePending()
    }

    private func restorePending() {
        guard let pendingFile, let data = try? Data(contentsOf: pendingFile),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        let now = Date()
        for item in list {
            guard let id = item["id"], let summary = item["summary"] else { continue }
            var session = Session(id: id, status: .done(summary), lastEvent: now, workStart: now)
            session.topic = item["topic"]
            sessions[id] = session
        }
        savedPending = list
    }

    /// 완료 알림 목록이 바뀌었을 때만 파일에 쓴다
    private func savePendingIfChanged() {
        guard let pendingFile else { return }
        let list: [[String: String]] = sessions.values.sorted { $0.id < $1.id }.compactMap { session in
            guard case .done(let summary) = session.status else { return nil }
            var item = ["id": session.id, "summary": summary]
            if let topic = session.topic { item["topic"] = topic }
            return item
        }
        guard list != savedPending, let data = try? JSONSerialization.data(withJSONObject: list) else { return }
        savedPending = list
        try? data.write(to: pendingFile, options: .atomic)
    }

    /// Claude가 마지막으로 움직인 뒤 흐른 시간 (오래 쉬면 Clawd가 더 자주 잔다)
    var idleSeconds: TimeInterval {
        active.isEmpty ? Date().timeIntervalSince(lastEventAt ?? startedAt) : 0
    }

    /// 보여줄 순서: 완료 알림 > 확인 필요 > 작업 중, 같은 급이면 최근 것 먼저
    var active: [Session] {
        sessions.values.sorted { a, b in
            let pa = Self.priority(a.status), pb = Self.priority(b.status)
            return pa != pb ? pa > pb : a.lastEvent > b.lastEvent
        }
    }

    var summaryLine: String {
        guard let first = active.first else {
            return lastEventAt == nil ? tr("Claude 연동: 아직 신호 없음", "Claude: no signal yet") : tr("Claude: 쉬는 중", "Claude: resting")
        }
        switch first.status {
        case .working: return tr("Claude: 일하는 중", "Claude: working") + (active.count > 1 ? tr(" (\(active.count)개 세션)", " (\(active.count) sessions)") : "")
        case .waiting: return tr("Claude: 확인을 기다리는 중", "Claude: waiting for your OK")
        case .done:
            let count = active.filter { if case .done = $0.status { return true } else { return false } }.count
            return tr("Claude: 확인 안 한 완료 알림 \(count)개", "Claude: \(count) unread done notice(s)")
        }
    }

    private static func priority(_ status: Status) -> Int {
        switch status {
        case .done: return 3
        case .waiting: return 2
        case .working: return 1
        }
    }

    // MARK: - 이벤트 읽기

    func poll(now: Date = Date()) {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        let dated = urls.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now)
        }
        for (url, date) in dated.sorted(by: { $0.1 < $1.1 }) {
            defer { try? fm.removeItem(at: url) }
            guard now.timeIntervalSince(date) < staleAfter,
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(json, at: date)
        }

        resolvePendingStops(now: now)

        for (id, session) in sessions {
            let expired: Bool
            switch session.status {
            case .done: expired = false   // 확인할 때까지 남겨 둔다
            case .working, .waiting: expired = now.timeIntervalSince(session.lastEvent) > workTimeout
            }
            if expired { sessions[id] = nil }
        }
    }

    func handle(_ json: [String: Any], at date: Date = Date()) {
        let id = json["session_id"] as? String ?? "default"
        let event = json["hook_event_name"] as? String ?? ""
        lastEventAt = date
        var session = sessions[id] ?? Session(id: id, status: .working(.think, ""), lastEvent: date, workStart: date)
        session.lastEvent = date
        if let path = json["transcript_path"] as? String { session.transcript = path }
        if let app = json["clawd_app"] as? String, !app.isEmpty { session.appPath = app }

        switch event {
        case "UserPromptSubmit":
            session.prompt = json["prompt"] as? String ?? ""
            if session.prompt.contains("#clawd-idea-routine") { session.isRoutine = true }
            session.promptAt = date
            session.workStart = date
            session.status = .working(.think, topic(&session, now: date) ?? "")
        case "PreToolUse":
            if case .done = session.status { session.workStart = date }   // 새 일이 시작됐다
            let tool = json["tool_name"] as? String ?? ""
            let input = json["tool_input"] as? [String: Any] ?? [:]
            session.status = .working(Self.work(for: tool), topic(&session, now: date) ?? Self.detail(tool: tool, input: input))
        case "PostToolUse":
            // 권한을 허락받고 도구가 실행됐다면 다시 일하는 중
            if case .waiting = session.status {
                let tool = json["tool_name"] as? String ?? ""
                let input = json["tool_input"] as? [String: Any] ?? [:]
                session.status = .working(Self.work(for: tool), topic(&session, now: date) ?? Self.detail(tool: tool, input: input))
            }
        case "Notification":
            let message = json["message"] as? String ?? ""
            guard Self.needsPermission(message) else { return }
            session.status = .waiting(Self.permissionText(message))
        case "Stop":
            if session.isRoutine {
                sessions[id] = nil
                return
            }
            if let message = json["last_assistant_message"] as? String, let summary = Self.brief(message) {
                finish(&session, summary, at: date)
            } else {
                session.pendingStop = (json["transcript_path"] as? String, date)
            }
        case "SessionEnd":
            sessions[id] = nil
            return
        default:
            return
        }
        if event != "Stop" { session.pendingStop = nil }
        sessions[id] = session
    }

    /// 실행 파일 경로에서 가장 바깥 .app 번들 (Orca Helper.app 안이면 Orca.app)
    static func bundlePath(from executable: String) -> String? {
        guard let range = executable.range(of: ".app/") else { return nil }
        return String(executable[..<range.lowerBound]) + ".app"
    }

    /// 그 세션을 돌리던 앱(터미널, Claude 데스크톱…)을 앞으로 가져온다
    func focusApp(of id: String) {
        guard let exe = sessions[id]?.appPath, let bundle = Self.bundlePath(from: exe) else { return }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == bundle }) {
            running.activate(options: [.activateIgnoringOtherApps])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: bundle))
        }
    }

    /// 완료 알림을 확인했다 (Touch Bar에서 톡 치거나 메뉴에서)
    func acknowledge(_ id: String) {
        if case .done = sessions[id]?.status { sessions[id] = nil }
    }

    func acknowledgeAll() {
        for (id, session) in sessions {
            if case .done = session.status { sessions[id] = nil }
        }
    }

    /// 지금 무슨 일을 하는지 보여 줄 주제: 앱이 붙인 세션 제목, 없으면 요청 앞부분
    private func topic(_ session: inout Session, now: Date) -> String? {
        if now.timeIntervalSince(session.topicCheckedAt) > 20, let path = session.transcript {
            session.topicCheckedAt = now
            if let title = Transcript.title(path) { session.topic = title }
        }
        if let topic = session.topic { return Self.clip(topic, 28) }
        return Self.brief(session.prompt, limit: 24)
    }

    private func finish(_ session: inout Session, _ summary: String, at date: Date) {
        session.pendingStop = nil
        session.status = .done(summary)
    }

    /// 대화 기록에 마지막 답변이 써질 때까지 잠깐 기다렸다가 요약한다.
    private func resolvePendingStops(now: Date) {
        for (id, var session) in sessions {
            guard let pending = session.pendingStop else { continue }
            let entries = pending.transcript.map(Transcript.recentEntries) ?? []
            if let text = Transcript.finalAnswer(entries), let summary = Self.brief(text) {
                finish(&session, summary, at: now)
            } else if now.timeIntervalSince(pending.at) > 2.5 {
                let since = session.promptAt ?? .distantPast
                let summary = Transcript.lastAnswer(entries, since: since).flatMap { Self.brief($0) }
                    ?? Self.brief(session.prompt, limit: 40).map { tr("‘\($0)’ 끝!", "‘\($0)’ done!") }
                    ?? tr("다 했어요", "All done")
                finish(&session, summary, at: now)
            }
            sessions[id] = session
        }
    }

    // MARK: - 해석

    static func work(for tool: String) -> Work {
        switch tool {
        case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch", "NotebookRead", "ToolSearch":
            return .study
        case "Bash", "BashOutput", "KillShell", "KillBash", "TaskStop", "Monitor":
            return .exercise
        case "Task", "Agent":
            return .think
        default:
            let t = tool.lowercased()
            if t.hasPrefix("mcp__"), ["read", "search", "get", "list", "fetch", "query", "find", "view"].contains(where: t.contains) {
                return .study
            }
            return .craft
        }
    }

    static func detail(tool: String, input: [String: Any]) -> String {
        func string(_ key: String) -> String? {
            guard let s = input[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        var text: String
        if let path = string("file_path") ?? string("notebook_path") ?? string("path") {
            text = (path as NSString).lastPathComponent
        } else if let description = string("description") {
            text = description
        } else if let command = string("command") {
            text = command.split(separator: " ").prefix(2).joined(separator: " ")
        } else if let url = string("url"), let host = URL(string: url)?.host {
            text = host
        } else if let query = string("pattern") ?? string("query") ?? string("prompt") {
            text = query
        } else if tool.hasPrefix("mcp__") {
            text = tool.components(separatedBy: "__").last ?? tool
        } else {
            text = tool
        }
        text = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return clip(text, 26)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    static func needsPermission(_ message: String) -> Bool {
        let m = message.lowercased()
        return ["permission", "approve", "approval", "권한", "허락", "허용"].contains(where: m.contains)
    }

    static func permissionText(_ message: String) -> String {
        if let range = message.range(of: "to use ") {
            let tool = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !tool.isEmpty { return tr("\(tool) 써도 될까요?", "Can I use \(tool)?") }
        }
        return tr("확인이 필요해요", "Needs your OK")
    }

    static func brief(_ text: String, limit: Int = 64) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            // 제목·코드·표·"다음과 같아요:" 같은 줄은 요약이 아니다
            if ["```", "|", "<", "#"].contains(where: line.hasPrefix) { continue }
            line = line.replacingOccurrences(of: #"^(>\s*|[-*+]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespaces)
            guard line.count >= 2, !line.hasSuffix(":") else { continue }
            if let sentence = line.range(of: #"^.+?[.!?。](\s|$)"#, options: .regularExpression) {
                line = line[sentence].trimmingCharacters(in: .whitespaces)
            }
            return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
        }
        return nil
    }
}
