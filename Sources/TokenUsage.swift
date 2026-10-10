import Foundation

/// Claude Code가 남기는 대화 기록(~/.claude/projects 아래 .jsonl)에서 사용량을 센다.
/// 데스크톱 앱 세션도 같은 곳에 기록이 남아서, 터미널 상태줄이 없어도 볼 수 있다.
///
/// 한도 대비 몇 %인지는 Anthropic만 알기 때문에, 직관적으로 보이도록 기준을 스스로 잡는다.
/// - 한도에 걸린 적이 있으면: 그때 그 5시간 구간에서 쓴 양을 100%로
/// - 없으면: 지난 7일 동안 가장 많이 쓴 5시간 구간을 100%로
/// 양은 가격 비율로 환산한다 (출력 ×5, 캐시 쓰기 ×1.25~2, 캐시 읽기 ×0.1). 캐시 읽기는 토큰 수는 많아도 부담이 적기 때문.
final class TokenUsage {
    struct Tally {
        var input = 0, output = 0, cacheWrite = 0, cacheRead = 0, messages = 0
        /// 가격 비율로 환산한 양 (입력 토큰 1개 = 1)
        var weighted = 0.0
        var total: Int { input + output + cacheWrite + cacheRead }

        static func += (lhs: inout Tally, rhs: Tally) {
            lhs.input += rhs.input
            lhs.output += rhs.output
            lhs.cacheWrite += rhs.cacheWrite
            lhs.cacheRead += rhs.cacheRead
            lhs.messages += rhs.messages
            lhs.weighted += rhs.weighted
        }
    }

    /// 5시간 게이지의 100%를 무엇으로 잡았는지
    enum Reference {
        case limitHit       // 한도에 걸렸던 때
        case personalPeak   // 지난 7일 중 가장 많이 쓴 5시간
    }

    struct Snapshot {
        /// 지금 진행 중인 5시간 구간. 첫 요청 시각(정시로 내림)부터 5시간 (쉬는 중이면 nil)
        var block: (tally: Tally, start: Date, end: Date)?
        /// 지금 구간이 기준의 몇 배인지 (0.46 = 46%). 비교할 기록이 없으면 nil
        var share: Double?
        var reference: Reference?
        var today = Tally()
        var week = Tally()
        /// 최근 7일, 하루씩 (오래된 날 → 오늘)
        var days: [(day: Date, tally: Tally)] = []
        /// 최근 7일, 많이 쓴 모델 순
        var models: [(name: String, tally: Tally)] = []
        /// 최근 8일의 답변마다 (시각, 환산량). 한도 기준을 맞출 때 쓴다
        var timeline: [(date: Date, weighted: Double)] = []

        /// 그때부터 지금까지 쓴 환산량
        func weighted(since start: Date) -> Double {
            timeline.reduce(0) { $1.date >= start ? $0 + $1.weighted : $0 }
        }
    }

    static let window: TimeInterval = 5 * 3600
    private static let keepDays = 8.0

    /// 메인 스레드에서 읽는다
    private(set) var snapshot: Snapshot?

    private struct Entry {
        let date: Date
        let model: String
        let tally: Tally
    }

    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    private let queue = DispatchQueue(label: "clawd.token-usage", qos: .utility)
    // 아래는 queue에서만 만진다
    private var offsets: [URL: UInt64] = [:]
    private var leftovers: [URL: Data] = [:]
    private var entries: [Entry] = []
    private var seen = Set<String>()
    /// 사용량 한도에 걸렸다는 오류가 기록된 때
    private var limitHits: [Date] = []
    private let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 문서용 그림: 기록을 읽지 않고 이 숫자를 보여 준다
    func preview(_ snapshot: Snapshot) { self.snapshot = snapshot }

    /// 새로 쌓인 기록만 이어서 읽고, 다 되면 메인 스레드에서 snapshot을 바꾼다
    func refresh(then done: (() -> Void)? = nil) {
        queue.async { [self] in
            scan()
            let next = summarize(now: Date())
            DispatchQueue.main.async {
                self.snapshot = next
                done?()
            }
        }
    }

    // MARK: - 읽기

    private func scan() {
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86400)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                          options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, modified > cutoff,
                  let size = values.fileSize.map(UInt64.init) else { continue }
            var offset = offsets[url] ?? 0
            if size < offset { offset = 0; leftovers[url] = nil }   // 파일이 새로 쓰였다
            guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            // 큰 기록도 메모리를 많이 쓰지 않게 4MB씩
            while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                offset += UInt64(chunk.count)
                var data = (leftovers[url] ?? Data()) + chunk
                if let lastNewline = data.lastIndex(of: 0x0A) {
                    let complete = data[data.startIndex...lastNewline]
                    for line in complete.split(separator: 0x0A) { read(line) }
                    data = Data(data[data.index(after: lastNewline)...])
                }
                leftovers[url] = data
            }
            offsets[url] = offset
        }
        entries.removeAll { $0.date < cutoff }
        limitHits.removeAll { $0 < cutoff }
    }

    private static let usageMarker = Data("\"output_tokens\"".utf8)
    private static let errorMarker = Data("\"isApiErrorMessage\":true".utf8)

    private func read(_ line: Data) {
        let isError = line.range(of: Self.errorMarker) != nil
        guard isError || line.range(of: Self.usageMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let stamp = json["timestamp"] as? String, let date = iso.date(from: stamp) else { return }
        if isError {
            // "…usage limit reached… resets 6pm" 같은 오류면 그때가 한도
            let text = ((message["content"] as? [[String: Any]])?.first?["text"] as? String ?? "").lowercased()
            if text.contains("limit"), text.contains("reset") { limitHits.append(date) }
            return
        }
        // 같은 답변이 여러 줄로 나뉘어 기록되므로 메시지 id로 한 번만 센다
        guard let usage = message["usage"] as? [String: Any] else { return }
        let key = "\(message["id"] as? String ?? stamp):\(json["requestId"] as? String ?? "")"
        guard seen.insert(key).inserted else { return }
        func count(_ dict: [String: Any]?, _ name: String) -> Int { (dict?[name] as? NSNumber)?.intValue ?? 0 }
        var tally = Tally(input: count(usage, "input_tokens"), output: count(usage, "output_tokens"),
                          cacheWrite: count(usage, "cache_creation_input_tokens"), cacheRead: count(usage, "cache_read_input_tokens"), messages: 1)
        guard tally.total > 0 else { return }   // 오류로 만들어진 가짜 답변
        // 캐시 쓰기는 5분짜리 ×1.25, 1시간짜리 ×2
        let split = usage["cache_creation"] as? [String: Any]
        let longWrite = min(tally.cacheWrite, count(split, "ephemeral_1h_input_tokens"))
        tally.weighted = Double(tally.input) + Double(tally.output) * 5 + Double(tally.cacheWrite - longWrite) * 1.25
            + Double(longWrite) * 2 + Double(tally.cacheRead) * 0.1
        entries.append(Entry(date: date, model: message["model"] as? String ?? "?", tally: tally))
    }

    // MARK: - 묶기

    private func summarize(now: Date) -> Snapshot {
        var result = Snapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        let firstDay = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var models: [String: Tally] = [:]
        var days = (0..<7).map { (calendar.date(byAdding: .day, value: $0, to: firstDay) ?? firstDay, Tally()) }

        // 5시간 구간: 첫 요청 시각을 정시로 내린 때부터 5시간. 그 뒤 첫 요청에서 새 구간이 시작된다.
        var blocks: [(start: Date, tally: Tally, entries: [Entry])] = []
        let sorted = entries.sorted(by: { $0.date < $1.date })
        result.timeline = sorted.map { (date: $0.date, weighted: $0.tally.weighted) }
        for entry in sorted {
            if entry.date >= today { result.today += entry.tally }
            if entry.date >= weekAgo {
                result.week += entry.tally
                models[entry.model, default: Tally()] += entry.tally
            }
            if entry.date >= firstDay {
                let index = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: entry.date)).day ?? 0
                if days.indices.contains(index) { days[index].1 += entry.tally }
            }
            if blocks.last.map({ entry.date >= $0.start.addingTimeInterval(Self.window) }) ?? true {
                blocks.append((calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date, Tally(), []))
            }
            blocks[blocks.count - 1].tally += entry.tally
            blocks[blocks.count - 1].entries.append(entry)
        }
        result.days = days.map { (day: $0.0, tally: $0.1) }
        result.models = models.map { (name: $0.key, tally: $0.value) }.sorted { $0.tally.total > $1.tally.total }

        var current: (start: Date, tally: Tally, entries: [Entry])?
        if let last = blocks.last, now < last.start.addingTimeInterval(Self.window) {
            current = last
            result.block = (last.tally, last.start, last.start.addingTimeInterval(Self.window))
        }
        // 기준: 가장 최근에 한도에 걸린 순간까지 그 구간에서 쓴 양, 없으면 지난 7일 중 가장 많이 쓴 (끝난) 구간
        var reference: Double?
        if let hit = limitHits.max(), let block = blocks.last(where: { $0.start <= hit && hit < $0.start.addingTimeInterval(Self.window) }) {
            let used = block.entries.filter { $0.date <= hit }.reduce(0) { $0 + $1.tally.weighted }
            if used > 0 { reference = used; result.reference = .limitHit }
        }
        if reference == nil {
            let past = blocks.filter { $0.start >= weekAgo && $0.start != current?.start }.map(\.tally.weighted).max() ?? 0
            if past > 0 { reference = past; result.reference = .personalPeak }
        }
        if let reference, let current { result.share = current.tally.weighted / reference }
        return result
    }

    // MARK: - 표시

    /// 12345678 → "12.3M"
    static func short(_ value: Int) -> String {
        let number = Double(value)
        switch number {
        case 1e9...: return String(format: "%.1fB", number / 1e9)
        case 1e6...: return String(format: "%.1fM", number / 1e6)
        case 1e3...: return String(format: "%.0fK", number / 1e3)
        default: return "\(value)"
        }
    }

    /// 좁은 칸용: 유효 숫자 2~3자리 (290M, 54M, 4.1M)
    static func compact(_ value: Int) -> String {
        let number = Double(value)
        let (scaled, unit): (Double, String) = number >= 1e9 ? (number / 1e9, "B") : number >= 1e6 ? (number / 1e6, "M") : number >= 1e3 ? (number / 1e3, "K") : (number, "")
        return (scaled < 10 && !unit.isEmpty ? String(format: "%.1f", scaled) : String(format: "%.0f", scaled)) + unit
    }

    /// "claude-opus-5-5" → "Opus 5.5"
    static func modelName(_ id: String) -> String {
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " " + version)
    }
}
