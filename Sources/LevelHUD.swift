import AppKit

/// 소리·밝기를 바꾸면 화면 아래쪽에 큰 Clawd가 레벨 바를 들고 잠깐 나타난다.
/// 클릭은 그대로 통과하고, 모든 데스크톱(전체 화면 앱 위 포함)에 뜬다.
final class LevelHUD {
    private let world = Playground()
    private var window: NSPanel?
    private var view: PlaygroundView?
    private var hideTimer: Timer?
    private static let size = NSSize(width: 170, height: 72)

    init() {
        world.transparent = true
        world.px = 4
        world.width = Self.size.width
        world.height = Self.size.height
        world.addPet(at: Self.size.width / 2)
        if let pet = world.pets.first {
            pet.y = 0                         // 떨어지며 등장하지 않고 바로 땅에
            pet.start(.idle, seconds: 1e9)   // 돌아다니지 않고 제자리에서
        }
    }

    func show(_ kind: Playground.Gauge.Kind, level: Float) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        if window == nil { makeWindow() }
        // 화면 아래 가운데, Dock 바로 위
        let frame = NSRect(x: screen.frame.midX - Self.size.width / 2, y: screen.visibleFrame.minY + 48,
                           width: Self.size.width, height: Self.size.height)
        window?.setFrame(frame, display: false)
        world.showGauge(kind, level: level)
        if window?.isVisible != true {
            window?.alphaValue = 0
            window?.orderFrontRegardless()
            view?.start()
        }
        // 사라지던 중이어도 다시 또렷하게
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; window?.animator().alphaValue = 1 }
        // 마지막으로 바꾼 뒤 바가 사라질 때쯤 함께 사라진다
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: Playground.gaugeLife - 0.25, repeats: false) { [weak self] _ in self?.fadeOut() }
    }

    private func fadeOut() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; window.animator().alphaValue = 0 }) { [weak self] in
            guard let self, self.hideTimer?.isValid != true else { return }   // 그새 다시 바꿨으면 그대로 둔다
            window.orderOut(nil)
            self.view?.stop()
        }
    }

    private func makeWindow() {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        // 밝은 바탕화면에서도 보이도록 은은한 그림자
        container.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            return shadow
        }()
        let playground = PlaygroundView(world: world)
        playground.preferredWidth = Self.size.width
        container.addSubview(playground)
        playground.setContentHuggingPriority(.defaultLow, for: .vertical)
        playground.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            playground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            playground.topAnchor.constraint(equalTo: container.topAnchor),
            playground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        window = panel
        view = playground
    }
}

/// 키보드·Control Strip·다른 앱으로 소리나 밝기가 바뀌어도 알아챈다 (0.2초마다 확인)
final class LevelWatcher {
    var onChange: ((Playground.Gauge.Kind, Float) -> Void)?
    private var volume: Float?
    private var muted: Bool?
    private var brightness: Float?
    private var timer: Timer?

    func start() {
        remember()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 지금 값을 기억해 둔다 (앱 버튼으로 바꾼 직후 같은 변화를 두 번 알리지 않게)
    func remember() {
        volume = SystemControls.volume
        muted = SystemControls.isMuted
        brightness = SystemControls.brightness
    }

    private func check() {
        let newVolume = SystemControls.volume, newMuted = SystemControls.isMuted, newBrightness = SystemControls.brightness
        defer { volume = newVolume; muted = newMuted; brightness = newBrightness }
        if newMuted != muted || changed(newVolume, volume, by: 0.004) {
            onChange?(newMuted ? .muted : .volume, newMuted ? 0 : newVolume ?? 0)
        } else if changed(newBrightness, brightness, by: 0.02), let level = newBrightness {
            // 자동 밝기는 천천히 조금씩 바뀌므로, 키를 누른 것처럼 한 번에 크게 바뀔 때만
            onChange?(.brightness, level)
        }
    }

    private func changed(_ new: Float?, _ old: Float?, by threshold: Float) -> Bool {
        guard let new, let old else { return false }
        return abs(new - old) > threshold
    }
}
