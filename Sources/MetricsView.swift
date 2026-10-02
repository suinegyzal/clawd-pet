import AppKit

/// 밝기·소리 버튼 옆의 작은 RunCat식 대시보드.
/// 왼쪽에선 Clawd가 바쁜 만큼 빨리 달리고, 오른쪽 수치는 5초마다 넘어간다. 톡 치면 바로 넘어간다.
final class MetricsView: NSView {
    enum Page { case system, gpuDisk, power, claude }

    static let width: CGFloat = 142

    let stats: SystemStats
    private(set) var page = Page.system
    private var pageAge = 0
    /// 달리기 박자 (RunnerClock이 넘겨준다)
    var runnerFrame = 0 {
        didSet { needsDisplay = true }
    }
    var busy = 0.0

    init(stats: SystemStats) {
        self.stats = stats
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 30))
        allowedTouchTypes = [.direct]
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.width).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: 30) }

    private var pages: [Page] {
        [.system, .gpuDisk, .power] + (stats.claude == nil ? [] : [.claude])
    }

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
        MetricsRenderer.draw(page, stats: stats, runnerFrame: runnerFrame, busy: busy, size: bounds.size, in: ctx)
    }
}

enum MetricsRenderer {
    private static let labelFont = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    private static let runnerWidth: CGFloat = 28

    private struct Row {
        let label: String
        let level: Double?
        let value: String
        /// 배터리처럼 적을수록 위험한 값
        var lowIsBad = false
    }

    static func draw(_ page: MetricsView.Page, stats: SystemStats, runnerFrame: Int, busy: Double,
                     size: CGSize, in ctx: CGContext) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let panel = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 1)
        ctx.addPath(CGPath(roundedRect: panel, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.11, alpha: 1))
        ctx.fillPath()

        drawRunner(frame: runnerFrame, busy: busy, in: ctx)

        let rows = self.rows(page, stats)
        for (i, row) in rows.prefix(2).enumerated() {
            let y: CGFloat = rows.count == 1 ? 9 : (i == 0 ? 16 : 3)
            drawRow(row, y: y, left: runnerWidth, width: size.width, in: ctx)
        }
    }

    /// 제자리에서 달리는 작은 Clawd. 빠를 땐 뒤로 속도선이 흐른다.
    private static func drawRunner(frame: Int, busy: Double, in ctx: CGContext) {
        let px: CGFloat = 1
        let pose = RunnerClock.pose(frame)
        let centerX = runnerWidth / 2 + 4
        ClawdSprite.draw(pose.frame, in: ctx, centerX: centerX, bottom: 9 + pose.lift * px, px: px)
        guard busy > 0.4 else { return }
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        let left = centerX - CGFloat(ClawdSprite.cols) * px / 2
        for (i, y) in [13.0, 16.0, 19.0].enumerated() where busy > 0.4 + Double(i) * 0.2 {
            let shift = CGFloat((frame + i) % 2) * 1.5
            ctx.fill(CGRect(x: left - 5 - shift, y: CGFloat(y), width: 3.5, height: 1))
        }
    }

    private static func rows(_ page: MetricsView.Page, _ stats: SystemStats) -> [Row] {
        switch page {
        case .system:
            return [Row(label: "CPU", level: stats.cpu, value: percent(stats.cpu)),
                    Row(label: "MEM", level: stats.memory, value: String(format: "%.1fG", stats.memoryUsedGB))]
        case .gpuDisk:
            return [Row(label: "GPU", level: stats.gpu, value: percent(stats.gpu)),
                    Row(label: "SSD", level: stats.disk, value: String(format: "%.0fG", stats.diskFreeGB))]
        case .power:
            let battery = stats.battery.map {
                Row(label: "BAT", level: $0.level, value: percent($0.level) + ($0.charging ? "⚡" : ""), lowIsBad: true)
            } ?? Row(label: "BAT", level: nil, value: "AC")
            return [battery, Row(label: "NET", level: nil, value: "↓" + rate(stats.download) + " ↑" + rate(stats.upload))]
        case .claude:
            guard let usage = stats.claude else { return [] }
            var rows: [Row] = []
            if let limit = usage.fiveHour { rows.append(Row(label: "✻5h", level: limit.used, value: percent(limit.used))) }
            if let limit = usage.sevenDay { rows.append(Row(label: "✻7d", level: limit.used, value: percent(limit.used))) }
            if rows.count < 2, let context = usage.context {
                rows.append(Row(label: "CTX", level: context, value: percent(context)))
            }
            if rows.isEmpty { rows.append(Row(label: "✻", level: nil, value: usage.model ?? "Claude")) }
            return rows
        }
    }

    private static func drawRow(_ row: Row, y: CGFloat, left: CGFloat, width: CGFloat, in ctx: CGContext) {
        let label = NSAttributedString(string: row.label, attributes: [.font: labelFont, .foregroundColor: Palette.text])
        label.draw(at: CGPoint(x: left + 2, y: y))

        let value = NSAttributedString(string: row.value, attributes: [.font: valueFont, .foregroundColor: Palette.bubbleText])
        let valueWidth = value.size().width
        value.draw(at: CGPoint(x: width - 6 - valueWidth, y: y - 0.5))

        guard let level = row.level else { return }
        let barLeft = left + 25
        let bar = CGRect(x: barLeft, y: y + 4, width: max(10, width - 6 - 34 - barLeft), height: 3)
        ctx.setFillColor(CGColor(gray: 0.28, alpha: 1))
        ctx.fill(bar)
        let danger = row.lowIsBad ? level < 0.2 : level > 0.85
        ctx.setFillColor(danger ? Palette.anger : Palette.clawd)
        ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(min(1, max(0, level))), height: bar.height))
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case ..<1_000: return "0K"
        case ..<1_000_000: return "\(Int(bytesPerSecond / 1_000))K"
        default: return String(format: "%.1fM", bytesPerSecond / 1_000_000)
        }
    }
}
