import AppKit

/// 리서치 루틴(예약 작업)이 ~/.clawd-touchbar/ideas.json 에 남긴 아이디어를 가끔 하나씩 꺼내 준다.
final class IdeaBox {
    struct Idea: Equatable {
        let id: String
        let topic: String
        let title: String
        let detail: String
        let report: String?
        let created: Date?
    }

    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clawd-touchbar/ideas.json")
    private static let seenKey = "seenIdeas"

    /// 최신 순
    private(set) var ideas: [Idea] = []
    private var fileDate: Date?
    private var seen: Set<String>
    private var shownCount: [String: Int] = [:]
    private var nextPitch = Date().addingTimeInterval(60)

    init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    var unseen: [Idea] { ideas.filter { !seen.contains($0.id) } }

    func reload() {
        guard let modified = (try? Self.file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            ideas = []   // 파일이 지워졌다
            fileDate = nil
            return
        }
        guard modified != fileDate else { return }
        let hadUnseen = Set(unseen.map(\.id))
        fileDate = modified
        guard let data = try? Data(contentsOf: Self.file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["ideas"] as? [[String: Any]] else { return }
        let iso = ISO8601DateFormatter()
        ideas = list.compactMap { item in
            guard let id = item["id"] as? String, let title = item["title"] as? String, !title.isEmpty else { return nil }
            return Idea(id: id, topic: item["topic"] as? String ?? tr("아이디어", "Idea"), title: title,
                        detail: item["detail"] as? String ?? "", report: item["report"] as? String,
                        created: (item["created"] as? String).flatMap { iso.date(from: $0) })
        }
        // 새 아이디어가 도착하면 곧 하나 던진다
        if !Set(unseen.map(\.id)).subtracting(hadUnseen).isEmpty {
            nextPitch = min(nextPitch, Date().addingTimeInterval(15))
        }
    }

    /// 지금 던지고 있는 아이디어. Touch Bar와 메뉴 막대가 같은 걸 같이 던진다.
    private(set) var current: Idea?
    private var currentUntil = Date.distantPast
    private var pitchSerial = 0
    private var countedSerial = -1

    /// 던질 때가 됐으면 아직 안 본 아이디어 하나 (다른 곳에서 막 던졌으면 그것)
    func due(now: Date = Date()) -> Idea? {
        if let current, now < currentUntil, !seen.contains(current.id) { return current }
        current = nil
        guard now >= nextPitch, let idea = unseen.first(where: { (shownCount[$0.id] ?? 0) < 3 }) else { return nil }
        nextPitch = now.addingTimeInterval(.random(in: 25 * 60...45 * 60))
        current = idea
        currentUntil = now.addingTimeInterval(40)
        pitchSerial += 1
        return idea
    }

    /// 메뉴에서 "하나 더"를 누르면 바로
    func pitchSoon() {
        nextPitch = Date()
    }

    /// 말풍선이 그냥 지나갔다. 세 번 지나가면 본 것으로 친다.
    func shown(_ idea: Idea) {
        // 양쪽에서 같이 던졌어도 한 번으로 센다
        guard countedSerial != pitchSerial else { return }
        countedSerial = pitchSerial
        shownCount[idea.id, default: 0] += 1
        if shownCount[idea.id, default: 0] >= 3 { markSeen(idea) }
    }

    func markSeen(_ idea: Idea) {
        if current?.id == idea.id { current = nil }
        seen.insert(idea.id)
        UserDefaults.standard.set(Array(seen.suffix(300)), forKey: Self.seenKey)
    }

    func isSeen(_ idea: Idea) -> Bool { seen.contains(idea.id) }

    /// 보고서를 연다 (없으면 아이디어 파일이 있는 폴더)
    static func open(_ idea: Idea?) {
        if let path = idea?.report, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.open(file.deletingLastPathComponent())
        }
    }
}
