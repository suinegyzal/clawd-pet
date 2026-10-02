import AppKit

/// 화면 맨 위 메뉴 막대 위를 돌아다니는 Clawd.
/// 메뉴 막대를 덮는 투명한 창을 띄우고, 클릭은 그대로 통과시킨다 (Clawd 위에서만 받는다).
final class MenuBarPet {
    let world = Playground()
    private var window: NSPanel?
    private var view: PlaygroundView?

    /// Touch Bar와 같은 수의 Clawd가 돌아다닌다
    var petCount = 1

    init(link: ClaudeLink?, ideas: IdeaBox?) {
        world.transparent = true
        world.link = link     // Touch Bar와 같은 Claude 상태를 같이 본다
        world.ideas = ideas   // 같은 아이디어를 같이 던진다
        world.px = 1.5
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    var isShowing: Bool { window?.isVisible == true }

    /// 메뉴 막대가 있는 화면과 메뉴 막대 높이 (자동 숨김이면 nil)
    private var barFrame: NSRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        // 메뉴 막대를 자동으로 숨기는 설정이면 화면 위쪽이 비어 있지 않다
        let gap = screen.frame.maxY - screen.visibleFrame.maxY
        guard gap >= 16 else { return nil }
        let height = Self.menuBarWindowHeight() ?? gap
        return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
    }

    /// 실제 메뉴 막대 창의 높이 (화면 맨 위, 메뉴 막대 층에 있는 창)
    private static func menuBarWindowHeight() -> CGFloat? {
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where window[kCGWindowLayer as String] as? Int == level {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  bounds["Y"] == 0, let height = bounds["Height"], height >= 16 else { continue }
            return height
        }
        return nil
    }

    func show() {
        guard let frame = barFrame else { return }
        if window == nil { makeWindow(frame) }
        window?.setFrame(frame, display: true)
        view?.preferredWidth = frame.width
        world.width = frame.width
        world.height = frame.height
        if world.pets.isEmpty { world.setPetCount(petCount) }
        window?.orderFrontRegardless()
        view?.start()
    }

    func hide() {
        view?.stop()
        window?.orderOut(nil)
    }

    private func makeWindow(_ frame: NSRect) {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)   // 메뉴 막대·상태 아이콘보다 위
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // 모든 데스크톱에 보이고, 전체 화면 앱 위에는 뜨지 않는다
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let playground = PlaygroundView(world: world)
        playground.preferredWidth = frame.width
        container.addSubview(playground)
        // 놀이터 기본 높이(30pt)가 창을 키우지 않게, 메뉴 막대 높이에 맞춘다
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

    @objc private func screensChanged() {
        guard isShowing else { return }
        if barFrame == nil { hide() } else { show() }
    }
}
