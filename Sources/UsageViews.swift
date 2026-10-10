import AppKit

/// 앱 언어에 맞춘 시각. withDay면 요일까지 ("목 오전 9:00" / "Thu 9:00 AM")
private func clockText(_ date: Date, withDay: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: tr("ko_KR", "en_US"))
    formatter.setLocalizedDateFormatFromTemplate("jmm")
    let time = formatter.string(from: date)
    guard withDay else { return time }
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter.string(from: date) + " " + time
}

/// "2일 19시간" / "3시간 26분" / "2d19h" …
private func remaining(until date: Date, short: Bool = false) -> String {
    let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
    let days = minutes / 1440, hours = minutes % 1440 / 60, rest = minutes % 60
    if short { return days > 0 ? "\(days)d\(hours)h" : hours > 0 ? "\(hours)h\(rest)m" : "\(rest)m" }
    if days > 0 { return tr("\(days)일 \(hours)시간", "\(days)d \(hours)h") }
    if hours > 0 { return tr("\(hours)시간 \(rest)분", "\(hours)h \(rest)m") }
    return tr("\(rest)분", "\(rest)m")
}

private func gaugeColor(_ level: Double) -> NSColor {
    level > 0.85 ? NSColor(cgColor: Palette.anger)! : Palette.accent
}

private func weekdayLabel(_ day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return tr("오늘", "Today") }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: tr("ko_KR", "en_US"))
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter.string(from: day)
}

/// 하루씩 막대 7개 (바닥이 rect.minY). 오늘은 Clawd 색, 지난날은 past 색
private func drawDays(_ days: [(day: Date, tally: TokenUsage.Tally)], in rect: NSRect, gap: CGFloat, past: NSColor) {
    guard !days.isEmpty else { return }
    let peak = max(1, days.map(\.tally.weighted).max() ?? 1)
    let width = (rect.width - gap * CGFloat(days.count - 1)) / CGFloat(days.count)
    for (i, day) in days.enumerated() {
        let height = max(1.5, rect.height * CGFloat(day.tally.weighted / peak))
        let bar = NSRect(x: rect.minX + CGFloat(i) * (width + gap), y: rect.minY, width: width, height: height)
        (i == days.count - 1 ? Palette.accent : past).setFill()
        NSBezierPath(roundedRect: bar, xRadius: min(2, width / 2), yRadius: min(2, width / 2)).fill()
    }
}

// MARK: - Touch Bar

/// Touch Bar의 Claude 사용량. 왼쪽에 ✻, 오른쪽이 5초마다(톡 치면 바로) 넘어간다.
/// 1) 5시간 한도 %와 남은 시간  2) 주간 한도 %와 남은 시간(기준이 있을 때)  3) 주간 토큰과 하루씩 막대
final class UsageView: NSView {
    enum Page { case window, week, days }

    static let width: CGFloat = 112
    private static let star = NSAttributedString(string: "✻", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: Palette.accent,
    ])
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)

    let stats: SystemStats
    private var page = Page.window
    private var pageAge = 0

    init(stats: SystemStats) {
        self.stats = stats
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 30))
        allowedTouchTypes = [.direct]
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: 30) }

    private var pages: [Page] { UsageLimits.weekly(stats).level == nil ? [.window, .days] : [.window, .week, .days] }

    /// 1초마다 불린다
    func tick() {
        pageAge += 1
        if pageAge >= 5 { nextPage() }
        needsDisplay = true
    }

    func nextPage() {
        let list = pages
        page = list[((list.firstIndex(of: page) ?? -1) + 1) % list.count]
        pageAge = 0
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) { nextPage() }
    override func mouseUp(with event: NSEvent) { nextPage() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        MetricsRenderer.drawPanel(bounds.size, in: ctx)
        let size = Self.star.size()
        Self.star.draw(at: CGPoint(x: 13 - size.width / 2, y: (bounds.height - size.height) / 2))
        typealias Row = MetricsRenderer.Row
        guard let tokens = stats.tokens.snapshot else {
            MetricsRenderer.drawRows([Row(label: "", level: nil, value: tr("읽는 중…", "reading…"))], left: 22, width: bounds.width, in: ctx)
            return
        }
        func gaugeRows(_ label: String, _ gauge: LimitGauge, fallback: String) -> [Row] {
            let top = gauge.percent.map { Row(label: label, level: min(1, gauge.level ?? 0), value: $0) }
                ?? Row(label: label, level: nil, value: fallback)
            return [top, Row(label: "↻", level: nil, value: gauge.resets.map { remaining(until: $0, short: true) } ?? "—")]
        }
        switch page {
        case .window:
            let fallback = tokens.block.map { TokenUsage.short($0.tally.total) } ?? tr("쉬는 중", "idle")
            MetricsRenderer.drawRows(gaugeRows("5h", UsageLimits.fiveHour(stats), fallback: fallback), left: 22, width: bounds.width, in: ctx)
        case .week:
            MetricsRenderer.drawRows(gaugeRows("7d", UsageLimits.weekly(stats), fallback: "—"), left: 22, width: bounds.width, in: ctx)
        case .days:
            NSAttributedString(string: "7d", attributes: [.font: Self.labelFont, .foregroundColor: Palette.text])
                .draw(at: CGPoint(x: 24, y: 16))
            let week = NSAttributedString(string: TokenUsage.short(tokens.week.total), attributes: [.font: Self.valueFont, .foregroundColor: Palette.bubbleText])
            week.draw(at: CGPoint(x: bounds.width - 6 - week.size().width, y: 15.5))
            drawDays(tokens.days, in: NSRect(x: 24, y: 4, width: bounds.width - 30, height: 9), gap: 3, past: NSColor(white: 0.45, alpha: 1))
        }
    }
}

// MARK: - 메뉴

/// 메뉴 맨 위의 탭 판: [Mac 상태 | Claude 사용량]. 고른 탭은 기억한다.
final class UsagePanel: NSView {
    private static let tabKey = "usageTab"
    private static let width: CGFloat = 300, contentHeight: CGFloat = 214

    private let tabs: NSSegmentedControl
    private let content: PanelContent

    /// onCalibrate: "한도 맞추기"를 눌렀을 때 (메뉴가 닫힌 뒤 불린다). tab을 주면 그 탭으로 연다 (문서용 그림)
    init(stats: SystemStats, tab: Int? = nil, onCalibrate: @escaping () -> Void) {
        tabs = NSSegmentedControl(labels: [tr("Mac 상태", "Mac"), tr("Claude 사용량", "Claude usage")],
                                  trackingMode: .selectOne, target: nil, action: nil)
        content = PanelContent(stats: stats, frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.contentHeight))
        content.onCalibrate = onCalibrate
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.contentHeight + 38))
        tabs.segmentDistribution = .fillEqually
        tabs.frame = NSRect(x: 14, y: Self.contentHeight + 6, width: Self.width - 28, height: 24)
        tabs.selectedSegment = tab ?? min(1, max(0, UserDefaults.standard.integer(forKey: Self.tabKey)))
        tabs.target = self
        tabs.action = #selector(switchTab)
        content.claude = tabs.selectedSegment == 1
        addSubview(tabs)
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func switchTab() {
        UserDefaults.standard.set(tabs.selectedSegment, forKey: Self.tabKey)
        content.claude = tabs.selectedSegment == 1
    }

    /// 메뉴가 열려 있는 동안 1초마다
    func refresh() { content.needsDisplay = true }
}

/// 탭 안쪽. 위에서부터 그린다.
private final class PanelContent: NSView {
    private static let labelFont = NSFont.menuFont(ofSize: 13)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let bigFont = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold)
    private static let noteFont = NSFont.systemFont(ofSize: 11)
    private static let usagePage = URL(string: "https://claude.ai/settings/usage")!

    let stats: SystemStats
    var onCalibrate: (() -> Void)?
    var claude = false { didSet { needsDisplay = true } }
    private var links: [(rect: NSRect, action: () -> Void)] = []
    private let left: CGFloat = 16
    private var right: CGFloat { bounds.width - 16 }

    init(stats: SystemStats, frame: NSRect) {
        self.stats = stats
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        links = []
        claude ? drawClaude() : drawMac()
    }

    // MARK: 그리기 도구

    private func text(_ string: String, _ font: NSFont, _ color: NSColor, at point: CGPoint) {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }

    private func value(_ string: String, _ font: NSFont, y: CGFloat) {
        let value = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        value.draw(at: CGPoint(x: right - value.size().width, y: y))
    }

    private func bar(_ rect: NSRect, level: Double, color: NSColor) {
        let radius = rect.height / 2
        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        guard level > 0 else { return }
        var filled = rect
        filled.size.width = max(rect.height, rect.width * CGFloat(min(1, level)))
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    /// 누를 수 있는 파란 글씨
    @discardableResult
    private func link(_ title: String, at point: CGPoint, action: @escaping () -> Void) -> CGFloat {
        let link = NSAttributedString(string: title, attributes: [.font: Self.labelFont, .foregroundColor: NSColor.linkColor])
        link.draw(at: point)
        let width = link.size().width
        links.append((NSRect(x: point.x - 4, y: point.y - 2, width: width + 8, height: 22), action))
        return width
    }

    // MARK: Mac 상태

    private func drawMac() {
        func percent(_ value: Double) -> String { MetricsRenderer.percent(value) }
        var rows: [(label: String, shown: String, level: Double?, lowIsBad: Bool)] = [
            ("CPU", percent(stats.cpu), stats.cpu, false),
            ("GPU", percent(stats.gpu), stats.gpu, false),
            (tr("메모리", "Memory"), String(format: "%.1fGB · %@", stats.memoryUsedGB, percent(stats.memory)), stats.memory, false),
            (tr("저장 공간", "Storage"), String(format: tr("%.0fGB 남음", "%.0f GB free"), stats.diskFreeGB), stats.disk, false),
        ]
        if let battery = stats.battery {
            rows.append((tr("배터리", "Battery"), percent(battery.level) + (battery.charging ? " ⚡" : ""), battery.level, true))
        } else {
            rows.append((tr("배터리", "Battery"), tr("전원 어댑터", "On power"), nil, false))
        }
        rows.append((tr("네트워크", "Network"), "↓" + MetricsRenderer.rate(stats.download) + "/s  ↑" + MetricsRenderer.rate(stats.upload) + "/s", nil, false))

        var y: CGFloat = 10
        for row in rows {
            text(row.label, Self.labelFont, .secondaryLabelColor, at: CGPoint(x: left, y: y))
            value(row.shown, Self.valueFont, y: y)
            if let level = row.level {
                let danger = row.lowIsBad ? level < 0.2 : level > 0.85
                // 막대 끝을 맞춘다 (값은 오른쪽 100pt 칸에)
                bar(NSRect(x: 100, y: y + 7, width: right - 104 - 100, height: 5), level: level,
                    color: danger ? NSColor(cgColor: Palette.anger)! : Palette.accent)
            }
            y += 33
        }
    }

    // MARK: Claude 사용량

    /// 이름(+무엇 대비인지) · 큰 % · 게이지 · 설명 한 줄
    private func drawGauge(_ title: String, _ gauge: LimitGauge, fallback: String, note: String, y: inout CGFloat) {
        let name = NSAttributedString(string: title, attributes: [.font: Self.labelFont, .foregroundColor: NSColor.secondaryLabelColor])
        name.draw(at: CGPoint(x: left, y: y + 3))
        if gauge.level != nil {
            text(gauge.basisText, Self.noteFont, .tertiaryLabelColor, at: CGPoint(x: left + name.size().width + 6, y: y + 5))
        }
        if let percent = gauge.percent {
            value(percent, Self.bigFont, y: y)
        } else {
            value(fallback, Self.valueFont, y: y + 3)
        }
        y += 25
        let level = gauge.level ?? 0
        bar(NSRect(x: left, y: y, width: right - left, height: 8), level: level, color: gaugeColor(level))
        y += 12
        text(note, Self.noteFont, .secondaryLabelColor, at: CGPoint(x: left, y: y))
        y += 15
    }

    private func drawClaude() {
        guard let tokens = stats.tokens.snapshot else {
            text(tr("기록을 읽는 중…", "Reading logs…"), Self.labelFont, .secondaryLabelColor, at: CGPoint(x: left, y: 8))
            return
        }
        let unit = tr(" 토큰", " tokens")
        var y: CGFloat = 4

        // 5시간 한도
        let five = UsageLimits.fiveHour(stats)
        let fiveNote = five.resets.map { tr("\(clockText($0))에 새로 시작 · \(remaining(until: $0)) 남음",
                                            "Resets \(clockText($0)) · \(remaining(until: $0)) left") }
            ?? tr("다음 요청부터 5시간을 셉니다", "Starts with your next request")
        drawGauge(tr("5시간 한도", "5-hour limit"), five,
                  fallback: tokens.block.map { TokenUsage.short($0.tally.total) + unit } ?? tr("쉬는 중", "Idle"), note: fiveNote, y: &y)
        y += 6

        // 주간 한도
        let weekly = UsageLimits.weekly(stats)
        let weekNote = weekly.resets.map { tr("\(clockText($0, withDay: true)) 초기화 · \(remaining(until: $0)) 남음",
                                              "Resets \(clockText($0, withDay: true)) · \(remaining(until: $0)) left") }
            ?? tr("claude.ai의 주간 %를 한 번 입력하면 계속 따라가요", "Enter your weekly % from claude.ai once to track it")
        drawGauge(tr("주간 한도", "Weekly limit"), weekly, fallback: TokenUsage.short(tokens.week.total) + unit, note: weekNote, y: &y)
        y += 6

        // 최근 7일: 합계와 하루씩 막대
        text(tr("최근 7일", "Last 7 days"), Self.noteFont, .secondaryLabelColor, at: CGPoint(x: left, y: y))
        let total = NSAttributedString(string: TokenUsage.short(tokens.week.total) + unit,
                                       attributes: [.font: Self.noteFont, .foregroundColor: NSColor.secondaryLabelColor])
        total.draw(at: CGPoint(x: right - total.size().width, y: y))
        y += 16
        // 이 뷰는 위가 0이라, 막대를 바닥에서 위로 그리도록 뒤집는다
        let chart = NSRect(x: left, y: y, width: right - left, height: 20)
        NSGraphicsContext.saveGraphicsState()
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: chart.maxY + chart.minY)
        flip.scaleX(by: 1, yBy: -1)
        flip.concat()
        drawDays(tokens.days, in: chart, gap: 6, past: NSColor.tertiaryLabelColor)
        NSGraphicsContext.restoreGraphicsState()
        y += 22
        let slot = (chart.width - 6 * CGFloat(tokens.days.count - 1)) / CGFloat(max(1, tokens.days.count))
        let small = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        for (i, day) in tokens.days.enumerated() {
            let color = i == tokens.days.count - 1 ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
            let x = chart.minX + CGFloat(i) * (slot + 6)
            for (row, caption) in [weekdayLabel(day.day), day.tally.total > 0 ? TokenUsage.compact(day.tally.total) : "–"].enumerated() {
                let label = NSAttributedString(string: caption, attributes: [.font: small, .foregroundColor: color])
                label.draw(at: CGPoint(x: x + (slot - label.size().width) / 2, y: y + CGFloat(row) * 11))
            }
        }
        y += 28

        // 한도 맞추기 · claude.ai
        let width = link(tr("한도 맞추기…", "Calibrate…"), at: CGPoint(x: left, y: y)) { [weak self] in self?.onCalibrate?() }
        link(tr("claude.ai 사용량 ↗", "claude.ai usage ↗"), at: CGPoint(x: left + width + 18, y: y)) {
            NSWorkspace.shared.open(Self.usagePage)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard claude, let hit = links.first(where: { $0.rect.contains(point) }) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        // 메뉴가 다 닫힌 다음에
        DispatchQueue.main.async { hit.action() }
    }
}

// MARK: - 한도 맞추기 대화상자

/// claude.ai 사용량 페이지에 보이는 주간 %·초기화 시각(·5시간 %)을 넣으면, 이 Mac의 기록과 비교해 한도를 추정한다
enum CalibrationDialog {
    /// 입력 칸들
    struct Form {
        let view: NSGridView
        let weekly: NSTextField
        let fiveHour: NSTextField
        let day: NSPopUpButton
        let time: NSDatePicker

        /// (주간 %, 다음 주간 초기화 시각, 5시간 %)
        var values: (weekly: Double?, reset: Date?, fiveHour: Double?) {
            func percent(_ field: NSTextField) -> Double? {
                Double(field.stringValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            }
            let calendar = Calendar.current
            let parts = calendar.dateComponents([.hour, .minute], from: time.dateValue)
            let reset = calendar.nextDate(after: Date(), matching: DateComponents(hour: parts.hour, minute: parts.minute, weekday: day.indexOfSelectedItem + 1),
                                          matchingPolicy: .nextTime)
            return (percent(weekly), reset, percent(fiveHour))
        }
    }

    static func makeForm() -> Form {
        func percentField(_ placeholder: String) -> NSTextField {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 64, height: 22))
            field.placeholderString = placeholder
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            return field
        }
        let weekly = percentField("23")
        let fiveHour = percentField(tr("선택", "optional"))
        let locale = Locale(identifier: tr("ko_KR", "en_US"))
        let formatter = DateFormatter()
        formatter.locale = locale
        let day = NSPopUpButton(frame: .zero, pullsDown: false)
        day.addItems(withTitles: formatter.weekdaySymbols)   // 일요일부터
        let time = NSDatePicker()
        time.datePickerElements = .hourMinute
        time.datePickerStyle = .textFieldAndStepper
        time.locale = locale
        let calendar = Calendar.current
        if let reset = UsageCalibration.current?.weeklyReset.map({ UsageLimits.weekWindow(anchor: $0).end }) {
            day.selectItem(at: calendar.component(.weekday, from: reset) - 1)
            time.dateValue = reset
        } else {
            day.selectItem(at: calendar.component(.weekday, from: Date()) - 1)
            time.dateValue = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        }
        func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }
        let grid = NSGridView(views: [
            [label(tr("주간 (모든 모델) 사용", "Weekly (all models) used")), weekly, label("%")],
            [label(tr("주간 초기화", "Weekly resets")), day, time],
            [label(tr("5시간 사용", "5-hour used")), fiveHour, label("%")],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        return Form(view: grid, weekly: weekly, fiveHour: fiveHour, day: day, time: time)
    }

    static func makeAlert(_ form: Form) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = tr("Claude 한도 맞추기", "Calibrate Claude limits")
        alert.informativeText = tr("claude.ai → 설정 → 사용량에 보이는 숫자를 그대로 넣어 주세요. 이 Mac의 Claude Code 기록과 비교해서, 그다음부터는 Clawd가 주간·5시간 %를 계속 따라갑니다. 터미널에서 claude를 쓰면 저절로 다시 맞춰져요.",
                                   "Type in the numbers from claude.ai → Settings → Usage. Clawd compares them with this Mac's Claude Code logs and keeps tracking your weekly and 5-hour % from then on. Using claude in a terminal re-syncs it automatically.")
        alert.accessoryView = form.view
        alert.addButton(withTitle: tr("저장", "Save"))
        alert.addButton(withTitle: tr("취소", "Cancel"))
        alert.addButton(withTitle: tr("사용량 페이지 열기", "Open usage page"))
        alert.window.initialFirstResponder = form.weekly
        return alert
    }

    static func run(stats: SystemStats) {
        let form = makeForm()
        while true {
            let alert = makeAlert(form)
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let values = form.values
                UsageLimits.calibrate(weeklyPercent: values.weekly, weeklyReset: values.reset, fiveHourPercent: values.fiveHour, stats: stats)
                return
            case .alertThirdButtonReturn:
                if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) }
                continue   // 페이지를 보고 와서 다시 입력
            default:
                return
            }
        }
    }
}
