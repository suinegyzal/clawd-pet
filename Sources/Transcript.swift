import Foundation

/// Claude Code 대화 기록(JSONL)에서 답변 글을 찾는다.
enum Transcript {
    struct Entry {
        let isAssistant: Bool
        let text: String?       // 답변 글 (도구 호출·결과면 nil)
        let date: Date?
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 파일 끝부분의 대화 항목(user/assistant)을 시간 순서대로
    static func recentEntries(_ path: String) -> [Entry] {
        guard let handle = FileHandle(forReadingAtPath: (path as NSString).expandingTildeInPath) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 600_000 ? size - 600_000 : 0)
        guard let data = try? handle.readToEnd() else { return [] }

        var entries: [Entry] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String, type == "assistant" || type == "user" else { continue }
            var answer: String?
            if type == "assistant", let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                // 생각 조각만 있는 항목은 답변 순서에 영향을 주지 않는다
                if content.allSatisfy({ $0["type"] as? String == "thinking" }) { continue }
                let texts = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty { answer = joined }
            }
            let date = (object["timestamp"] as? String).flatMap { iso.date(from: $0) }
            entries.append(Entry(isAssistant: type == "assistant", text: answer, date: date))
        }
        return entries
    }

    /// Claude 앱이 세션에 붙인 제목. 끝부분에 없으면 파일을 더 넓게 뒤진다.
    static func title(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: (path as NSString).expandingTildeInPath) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        for window: UInt64 in [600_000, 30_000_000] {
            try? handle.seek(toOffset: size > window ? size - window : 0)
            guard let data = try? handle.readToEnd() else { return nil }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed()
            where line.contains("\"custom-title\"") || line.contains("\"agent-name\"") || line.contains("\"summary\"") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                let title: Any?
                switch object["type"] as? String {
                case "custom-title": title = object["customTitle"]
                case "agent-name": title = object["agentName"]
                case "summary": title = object["summary"]
                default: title = nil
                }
                if let title = (title as? String)?.replacingOccurrences(of: " (fork)", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    return title
                }
            }
            if size <= window { break }
        }
        return nil
    }

    /// 기록의 마지막 항목이 답변 글이면 그 글 (턴이 글로 끝났고, 기록도 다 써졌다는 뜻)
    static func finalAnswer(_ entries: [Entry]) -> String? {
        guard let last = entries.last, last.isAssistant else { return nil }
        return last.text
    }

    /// 이번 요청 이후에 나온 마지막 답변 글
    static func lastAnswer(_ entries: [Entry], since: Date) -> String? {
        entries.last { $0.text != nil && ($0.date ?? .distantFuture) >= since }?.text
    }
}
