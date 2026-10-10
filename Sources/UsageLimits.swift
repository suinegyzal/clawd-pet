import Foundation

/// 한도 대비 몇 % 썼는지.
/// 1) 터미널 claude의 상태줄이 공식 %를 알려 주면 그 숫자
/// 2) 아니면 한 번 맞춰 둔 기준(claude.ai에서 본 %를 입력했거나, 상태줄이 왔을 때 저절로)으로 이 Mac의 기록을 나눠 추정
/// 3) 5시간은 그것도 없으면 내 기록(한도에 걸렸던 때, 지난 7일 최고)과 비교
struct UsageCalibration: Codable {
    /// 주간 한도 100%에 해당하는 환산량
    var weeklyLimit: Double?
    /// 주간 한도가 초기화되는 어느 한 시각. 7일마다 되풀이된다
    var weeklyReset: Date?
    /// 5시간 한도 100%에 해당하는 환산량
    var fiveHourLimit: Double?
    var fromStatusLine = false
    var updated = Date()
    /// 같은 상태줄 숫자로 여러 번 다시 맞추지 않도록
    var statusLineStamp: Date?

    private static let key = "usageCalibration"
    /// 문서용 그림을 그릴 때 저장된 값 대신 쓴다
    static var override: UsageCalibration?
    /// 지금 쓰는 기준
    static var current: UsageCalibration? { override ?? load() }

    static func load() -> UsageCalibration? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageCalibration.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

struct LimitGauge {
    enum Basis {
        case official           // 상태줄의 공식 %
        case calibrated(Date, fromStatusLine: Bool)
        case limitHit           // 한도에 걸렸던 때
        case personalPeak       // 지난 7일 최고 5시간
        case none               // 비교할 기준이 없다
    }

    var level: Double?          // 0...1, 넘을 수도 있다
    var resets: Date?
    var basis: Basis = .none

    var percent: String? { level.map { "\(Int(($0 * 100).rounded()))%" } }

    /// 제목 옆에 붙는 짧은 꼬리표: 무엇 대비 %인지
    var basisText: String {
        switch basis {
        case .official: return tr("공식", "official")
        case let .calibrated(date, fromStatusLine):
            let day = date.formatted(.dateTime.month(.defaultDigits).day().locale(Locale(identifier: tr("ko_KR", "en_US"))))
            return fromStatusLine ? tr("추정 · \(day) 상태줄로 맞춤", "est. · synced \(day)") : tr("추정 · \(day) 맞춤", "est. · set \(day)")
        case .limitHit: return tr("한도 걸린 때 대비", "vs. last limit hit")
        case .personalPeak: return tr("내 최고 기록 대비", "vs. your busiest 5h")
        case .none: return ""
        }
    }
}

enum UsageLimits {
    static let week: TimeInterval = 7 * 86400

    /// 주간 한도 구간: 알고 있는 초기화 시각에서 7일씩 더해 지금을 품는 구간
    static func weekWindow(anchor: Date, now: Date = Date()) -> (start: Date, end: Date) {
        let steps = ((now.timeIntervalSince(anchor)) / week).rounded(.down) + 1
        let end = anchor.addingTimeInterval(steps * week)
        return (end.addingTimeInterval(-week), end)
    }

    private static func freshStatusLine(_ stats: SystemStats) -> SystemStats.ClaudeUsage? {
        guard let usage = stats.claude, usage.isFresh else { return nil }
        return usage
    }

    static func weekly(_ stats: SystemStats) -> LimitGauge {
        if let limit = freshStatusLine(stats)?.sevenDay {
            return LimitGauge(level: limit.used, resets: limit.resets, basis: .official)
        }
        guard let calibration = UsageCalibration.current, let limit = calibration.weeklyLimit, limit > 0,
              let anchor = calibration.weeklyReset, let tokens = stats.tokens.snapshot else { return LimitGauge() }
        let window = weekWindow(anchor: anchor)
        return LimitGauge(level: tokens.weighted(since: window.start) / limit, resets: window.end,
                          basis: .calibrated(calibration.updated, fromStatusLine: calibration.fromStatusLine))
    }

    static func fiveHour(_ stats: SystemStats) -> LimitGauge {
        let tokens = stats.tokens.snapshot
        if let limit = freshStatusLine(stats)?.fiveHour {
            return LimitGauge(level: limit.used, resets: limit.resets ?? tokens?.block?.end, basis: .official)
        }
        guard let tokens else { return LimitGauge() }
        guard let block = tokens.block else { return LimitGauge(level: 0, basis: .none) }
        if let calibration = UsageCalibration.current, let limit = calibration.fiveHourLimit, limit > 0 {
            return LimitGauge(level: block.tally.weighted / limit, resets: block.end,
                              basis: .calibrated(calibration.updated, fromStatusLine: calibration.fromStatusLine))
        }
        switch tokens.reference {
        case .limitHit: return LimitGauge(level: tokens.share, resets: block.end, basis: .limitHit)
        case .personalPeak: return LimitGauge(level: tokens.share, resets: block.end, basis: .personalPeak)
        case nil: return LimitGauge(resets: block.end)
        }
    }

    /// claude.ai 사용량 페이지에서 본 숫자로 기준을 맞춘다. 퍼센트는 0...100
    static func calibrate(weeklyPercent: Double?, weeklyReset: Date?, fiveHourPercent: Double?, stats: SystemStats) {
        guard let tokens = stats.tokens.snapshot else { return }
        var calibration = UsageCalibration.load() ?? UsageCalibration()
        if let percent = weeklyPercent, percent > 0, let reset = weeklyReset {
            let used = tokens.weighted(since: weekWindow(anchor: reset).start)
            if used > 0 {
                calibration.weeklyLimit = used / (percent / 100)
                calibration.weeklyReset = reset
            }
        }
        if let percent = fiveHourPercent, percent > 0, let block = tokens.block, block.tally.weighted > 0 {
            calibration.fiveHourLimit = block.tally.weighted / (percent / 100)
        }
        calibration.fromStatusLine = false
        calibration.updated = Date()
        calibration.save()
    }

    /// 터미널 상태줄이 공식 %를 새로 알려 주면 그걸로 기준을 저절로 다시 맞춘다 (데스크톱 앱만 쓸 때를 위해)
    static func autoCalibrate(_ stats: SystemStats) {
        guard let usage = freshStatusLine(stats), let tokens = stats.tokens.snapshot else { return }
        var calibration = UsageCalibration.load() ?? UsageCalibration()
        guard calibration.statusLineStamp != usage.updated else { return }
        var changed = false
        // 너무 작은 %로 나누면 오차가 커서, 어느 정도 쓴 뒤에만
        if let seven = usage.sevenDay, seven.used >= 0.03, let resets = seven.resets {
            let used = tokens.weighted(since: resets.addingTimeInterval(-week))
            if used > 0 { calibration.weeklyLimit = used / seven.used; calibration.weeklyReset = resets; changed = true }
        }
        if let five = usage.fiveHour, five.used >= 0.05, let resets = five.resets {
            let used = tokens.weighted(since: resets.addingTimeInterval(-TokenUsage.window))
            if used > 0 { calibration.fiveHourLimit = used / five.used; changed = true }
        }
        calibration.statusLineStamp = usage.updated
        if changed {
            calibration.fromStatusLine = true
            calibration.updated = Date()
        }
        calibration.save()
    }
}
