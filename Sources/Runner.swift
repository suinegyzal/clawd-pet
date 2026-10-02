import AppKit

/// RunCat처럼 제자리에서 달리는 Clawd의 박자. 바쁠수록 걸음이 빨라진다.
/// 메뉴 막대 아이콘과 Touch Bar 대시보드가 같은 박자로 달린다.
final class RunnerClock {
    static let frameCount = 4

    private(set) var frame = 0
    /// 0...1, 클수록 빨리 달린다
    var busy: () -> Double = { 0 }
    var onFrame: ((Int) -> Void)?
    private var timer: Timer?

    /// 한 걸음 간격: 한가하면 0.5초, 꽉 차면 0.06초
    var interval: TimeInterval { 0.5 - 0.44 * min(1, max(0, busy())) }

    func start() {
        guard timer == nil else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.frame = (self.frame + 1) % Self.frameCount
            self.onFrame?(self.frame)
            self.scheduleNext()
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    /// 달리기 한 바퀴: 한 발 → 공중 → 다른 발 → 공중. lift는 몸이 뜨는 픽셀 수.
    static func pose(_ frame: Int) -> (frame: ClawdSprite.Frame, lift: CGFloat) {
        switch frame % frameCount {
        case 0: return (ClawdSprite.Frame(legs: .stepA, look: 1), 0)
        case 2: return (ClawdSprite.Frame(legs: .stepB, look: 1), 0)
        default: return (ClawdSprite.Frame(legs: .tucked, look: 1), 1)
        }
    }

    /// 메뉴 막대용 달리기 그림들
    static func menuBarImages(px: CGFloat) -> [NSImage] {
        (0..<frameCount).map { index in
            let pose = pose(index)
            let size = NSSize(width: CGFloat(ClawdSprite.cols) * px, height: CGFloat(ClawdSprite.rows + 1) * px)
            return NSImage(size: size, flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                ClawdSprite.draw(pose.frame, in: ctx, centerX: size.width / 2, bottom: pose.lift * px, px: px)
                return true
            }
        }
    }
}
