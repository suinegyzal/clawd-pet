import AppKit

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.write(to: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--render-docs"), i + 1 < args.count {
            DocsArt.write(to: args[i + 1])
            return
        }
        let app = NSApplication.shared
        if args.contains("--desktop") { UserDefaults.standard.set(true, forKey: "desktopMode") }
        let delegate = AppDelegate(preview: args.contains("--preview"))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate, NSMenuDelegate {
    private enum Key {
        static let count = "petCount"
        static let big = "bigPixels"
        static let wide = "wideMode"
        static let controls = "showControls"
        static let metrics = "showMetrics"
        static let source = "runnerSource"
        static let menuBarPet = "menuBarPet"
        static let desktop = "desktopMode"
        static let declined = "declinedClaudeConnect"
    }
    private static let barID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.playground")
    private static let trayID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.tray")
    private static let brightnessID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.brightness")
    private static let volumeID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.volume")
    private static let metricsID = NSTouchBarItem.Identifier("com.local.ClaudeTouchBar.metrics")
    private static let controlWidth: CGFloat = 46
    private static let maxPets = 6

    private let previewMode: Bool
    private let defaults = UserDefaults.standard
    private let world = Playground()
    private let stats = SystemStats()
    private lazy var metricsView = MetricsView(stats: stats)
    private var statsTimer: Timer?
    private let runner = RunnerClock()
    private lazy var runnerImages = RunnerClock.menuBarImages(px: 1.5)
    private lazy var playground = PlaygroundView(world: world)
    private lazy var touchBar: NSTouchBar = {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.barID]
        return bar
    }()
    private var trayItem: NSCustomTouchBarItem?
    private var statusItem: NSStatusItem?
    private var previewWindow: NSWindow?
    /// 화면 위 모드(Touch Bar 없는 맥): 떠다니는 Clawd 창들
    private var petWindows: [PetWindow] = []
    private var desktopItem: NSMenuItem!
    private var connectItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var isShowing = false
    private var muteButton: NSButton?

    private var countItem: NSMenuItem!
    private var linkItem: NSMenuItem!
    private var showItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var removeItem: NSMenuItem!
    private var bigItem: NSMenuItem!
    private var wideItem: NSMenuItem!
    private var controlsItem: NSMenuItem!
    private var metricsItem: NSMenuItem!
    private var statsLines: [NSMenuItem] = []
    private let ideasMenu = NSMenu()
    private var menuBarPet: MenuBarPet?
    private var menuBarPetItem: NSMenuItem!
    private var sourceItems: [NSMenuItem] = []

    init(preview: Bool) {
        previewMode = preview
        super.init()
        defaults.register(defaults: [Key.count: 1, Key.big: true, Key.wide: false, Key.controls: true, Key.metrics: true, Key.menuBarPet: true])
    }

    private var petCount: Int {
        get { min(max(defaults.integer(forKey: Key.count), 1), Self.maxPets) }
        set { defaults.set(newValue, forKey: Key.count) }
    }
    private var desktopMode: Bool {
        get { defaults.bool(forKey: Key.desktop) }
        set { defaults.set(newValue, forKey: Key.desktop) }
    }
    private var desktopPixel: CGFloat { big ? 4 : 3 }
    private var big: Bool {
        get { defaults.bool(forKey: Key.big) }
        set { defaults.set(newValue, forKey: Key.big) }
    }
    private var wide: Bool {
        get { defaults.bool(forKey: Key.wide) }
        set { defaults.set(newValue, forKey: Key.wide) }
    }
    /// Touch Bar가 "확장된 Control Strip"·"기능 키" 모드면 앱 영역이 없어서 넓게 덮는 방식만 보인다.
    private var controlStripOnly: Bool {
        let mode = UserDefaults(suiteName: "com.apple.touchbar.agent")?.string(forKey: "PresentationModeGlobal") ?? "appWithControlStrip"
        return mode != "app" && mode != "appWithControlStrip"
    }
    private var useWide: Bool { wide || controlStripOnly }
    private var showControls: Bool {
        get { defaults.bool(forKey: Key.controls) }
        set { defaults.set(newValue, forKey: Key.controls) }
    }
    /// Control Strip까지 덮을 때는 밝기·소리 버튼을 직접 단다
    private var hasControls: Bool { useWide && showControls && !previewMode }
    private var runnerSource: RunnerSource {
        get { RunnerSource(rawValue: defaults.string(forKey: Key.source) ?? "") ?? .cpu }
        set { defaults.set(newValue.rawValue, forKey: Key.source) }
    }
    private var showMetrics: Bool {
        get { defaults.bool(forKey: Key.metrics) }
        set { defaults.set(newValue, forKey: Key.metrics) }
    }
    private var hasMetrics: Bool { showMetrics && !previewMode }
    /// Control Strip을 남겨 둘 때는 앱 영역(실제 폭에 맞춰 줄어듦), 덮을 때는 esc 자리만 빼고 전체.
    /// 옆에 붙는 아이템들 사이에는 8pt씩 간격이 생긴다.
    private var barWidth: CGFloat {
        var width: CGFloat = useWide ? 1004 : 685
        if hasControls { width -= (Self.controlWidth + 8) * 5 }
        if hasMetrics { width -= MetricsView.width + 8 }
        return width - 6
    }

    // MARK: - 시작/종료

    func applicationDidFinishLaunching(_ notification: Notification) {
        ClaudeSetup.installScripts()
        // 처음 켤 때: Touch Bar 없는 맥이면 화면 위 모드를 기본으로
        if defaults.object(forKey: Key.desktop) == nil { defaults.set(!ClaudeSetup.hasTouchBar, forKey: Key.desktop) }
        world.px = big ? 2 : 1.5
        world.width = barWidth
        world.setPetCount(petCount)
        try? FileManager.default.createDirectory(at: ClaudeLink.directory, withIntermediateDirectories: true)
        world.link = ClaudeLink(pendingFile: ClaudeLink.pendingFile)
        world.ideas = IdeaBox()
        if !previewMode {
            menuBarPet = MenuBarPet(link: world.link, ideas: world.ideas)
            menuBarPet?.petCount = petCount
            if defaults.bool(forKey: Key.menuBarPet) { menuBarPet?.show() }
        }
        startStats()
        playground.preferredWidth = barWidth
        playground.onVisibilityChange = { [weak self] visible in
            guard let self, !self.previewMode else { return }
            self.isShowing = visible
        }
        setupStatusItem()

        if previewMode {
            showPreviewWindow()
        } else if desktopMode {
            showDesktop()
        } else {
            installTrayItem()
            showOnTouchBar()
        }
        if !previewMode && !ClaudeSetup.isConnected && !defaults.bool(forKey: Key.declined) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.offerConnection() }
        }
    }

    // MARK: - Claude Code 연결 (터미널 없이)

    private func offerConnection() {
        let alert = NSAlert()
        alert.messageText = tr("Clawd를 Claude Code와 연결할까요?", "Connect Clawd to Claude Code?")
        alert.informativeText = tr("Claude Code 설정(~/.claude/settings.json)에 훅을 추가해서, Claude가 일하면 Clawd도 따라 움직이게 해요. 쓰던 다른 설정은 건드리지 않고, 바꾸기 전 원본은 settings.json.bak-clawd 로 남겨요. 메뉴 막대의 Clawd 메뉴에서 언제든 끊을 수 있어요.", "This adds hooks to your Claude Code settings (~/.claude/settings.json) so Clawd moves along when Claude works. Your other settings stay untouched, and the original is backed up as settings.json.bak-clawd. You can disconnect anytime from the Clawd menu in the menu bar.")
        alert.addButton(withTitle: tr("연결", "Connect"))
        alert.addButton(withTitle: tr("나중에", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            connectClaude()
        } else {
            defaults.set(true, forKey: Key.declined)
        }
    }

    private func connectClaude() {
        let alert = NSAlert()
        do {
            alert.messageText = tr("연결 완료", "Connected")
            alert.informativeText = try ClaudeSetup.connect()
            defaults.removeObject(forKey: Key.declined)
        } catch {
            alert.alertStyle = .warning
            alert.messageText = tr("연결하지 못했어요", "Couldn't connect")
            alert.informativeText = "\(error.localizedDescription)\n\n" + tr("~/.claude/settings.json 이 올바른 JSON인지 확인해 주세요.", "Please check that ~/.claude/settings.json is valid JSON.")
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleConnect() {
        if ClaudeSetup.isConnected {
            try? ClaudeSetup.disconnect()
            defaults.set(true, forKey: Key.declined)
        } else {
            connectClaude()
        }
    }

    @objc private func toggleLogin() {
        ClaudeSetup.launchesAtLogin.toggle()
    }

    // MARK: - 화면 위 모드

    /// 두 마리가 가까이 지나치면 서로 인사한다 (한 쌍당 25초에 한 번)
    private func greetNeighbors() {
        let now = CACurrentMediaTime()
        for i in petWindows.indices {
            for j in petWindows.indices where j > i {
                let a = petWindows[i], b = petWindows[j]
                guard now - a.lastGreet > 25, now - b.lastGreet > 25 else { continue }
                let dx = b.screenCenter.x - a.screenCenter.x
                guard abs(dx) < 150, abs(b.screenCenter.y - a.screenCenter.y) < 90 else { continue }
                a.greet(toward: dx)
                b.greet(toward: -dx)
            }
        }
    }

    private func showDesktop() {
        while petWindows.count < petCount { addPetWindow() }
    }

    private func hideDesktop() {
        for w in petWindows { w.close() }
        petWindows = []
    }

    private func addPetWindow() {
        let w = PetWindow(px: desktopPixel, link: world.link, slot: petWindows.count)
        w.onAddPet = { [weak self] in self?.addPet() }
        w.onTreat = { [weak self] treat, source in
            guard let self else { return }
            for other in self.petWindows where other !== source && abs(other.screenCenter.x - source.screenCenter.x) < 700 {
                other.race(for: treat, in: source)
            }
        }
        w.onRemovePet = { [weak self] w in
            guard let self, self.petWindows.count > 1, let i = self.petWindows.firstIndex(where: { $0 === w }) else { return }
            self.petWindows.remove(at: i).close()
            PetLedger.shared.remove(at: i)
            for (slot, rest) in self.petWindows.enumerated() { rest.world.sessionOffset = slot; rest.slot = slot }
            self.petCount = self.petWindows.count
        }
        w.world.busy = world.busy
        if petWindows.isEmpty { w.world.ideas = world.ideas }   // 아이디어는 한 마리만 던진다
        petWindows.append(w)
    }

    @objc private func toggleDesktop() {
        desktopMode.toggle()
        if desktopMode {
            if isShowing { hideFromTouchBar() }
            showDesktop()
        } else {
            hideDesktop()
            if trayItem == nil { installTrayItem() }
            showOnTouchBar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PetLedger.shared.saveIfNeeded()
        guard !previewMode else { return }
        TouchBarPrivate.dismiss(touchBar)
        TouchBarPrivate.setControlStripPresence(Self.trayID, false)
        if let trayItem { TouchBarPrivate.removeSystemTrayItem(trayItem) }
    }

    /// 1초마다 Mac 상태를 재서 대시보드와 Clawd(바쁠수록 빨리 달림)에 알려 준다
    private func startStats() {
        stats.sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.stats.sample()
            let busy = self.stats.value(for: self.runnerSource)
            self.world.busy = busy
            for w in self.petWindows { w.world.busy = busy }
            self.greetNeighbors()
            self.metricsView.busy = busy
            self.menuBarPet?.world.busy = busy
            self.metricsView.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer

        // RunCat처럼 메뉴 막대와 대시보드의 Clawd가 바쁜 만큼 빨리 달린다
        runner.busy = { [weak self] in self.map { $0.stats.value(for: $0.runnerSource) } ?? 0 }
        runner.onFrame = { [weak self] frame in
            guard let self else { return }
            self.statusItem?.button?.image = self.runnerImages[frame]
            if self.metricsView.window != nil { self.metricsView.runnerFrame = frame }
        }
        runner.start()
    }

    // MARK: - Touch Bar

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.barID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = playground
            return item
        case Self.metricsID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = metricsView
            return item
        case Self.brightnessID:
            return NSGroupTouchBarItem(identifier: identifier, items: [
                controlButton("brightness-down", "sun.min.fill", #selector(brightnessDown)),
                controlButton("brightness-up", "sun.max.fill", #selector(brightnessUp)),
            ])
        case Self.volumeID:
            let mute = controlButton("mute", "speaker.slash.fill", #selector(toggleMute), repeats: false)
            muteButton = mute.view as? NSButton
            syncMuteButton()
            return NSGroupTouchBarItem(identifier: identifier, items: [
                mute,
                controlButton("volume-down", "speaker.wave.1.fill", #selector(volumeDown)),
                controlButton("volume-up", "speaker.wave.3.fill", #selector(volumeUp)),
            ])
        default:
            return nil
        }
    }

    /// 누르고 있으면 계속 조절되는 밝기·소리 버튼
    private func controlButton(_ name: String, _ symbol: String, _ action: Selector, repeats: Bool = true) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.local.ClaudeTouchBar." + name))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        if repeats {
            button.isContinuous = true
            button.setPeriodicDelay(0.35, interval: 0.08)
        }
        button.widthAnchor.constraint(equalToConstant: Self.controlWidth).isActive = true
        item.view = button
        return item
    }

    private func syncMuteButton() {
        muteButton?.bezelColor = SystemControls.isMuted ? Palette.accent : nil
    }

    @objc private func brightnessDown() { changeBrightness(-1) }
    @objc private func brightnessUp() { changeBrightness(1) }
    @objc private func volumeDown() { changeVolume(-1) }
    @objc private func volumeUp() { changeVolume(1) }

    private func changeBrightness(_ direction: Float) {
        guard let level = SystemControls.stepBrightness(direction) else { return }
        world.showGauge(.brightness, level: level)
    }

    private func changeVolume(_ direction: Float) {
        guard let level = SystemControls.stepVolume(direction) else { return }
        world.showGauge(SystemControls.isMuted ? .muted : .volume, level: level)
        syncMuteButton()
    }

    @objc private func toggleMute() {
        let muted = SystemControls.toggleMute()
        world.showGauge(muted ? .muted : .volume, level: muted ? 0 : SystemControls.volume ?? 0)
        syncMuteButton()
    }

    /// Control Strip에 작은 Clawd 버튼을 달아서, 눌러서 놀이터를 열고 닫을 수 있게 한다.
    private func installTrayItem() {
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        item.view = NSButton(image: ClawdSprite.icon(px: 1.5), target: self, action: #selector(toggleTouchBar))
        TouchBarPrivate.addSystemTrayItem(item)
        TouchBarPrivate.setControlStripPresence(Self.trayID, true)
        trayItem = item
    }

    private func showOnTouchBar() {
        touchBar.defaultItemIdentifiers = [Self.barID] + (hasMetrics ? [Self.metricsID] : [])
            + (hasControls ? [Self.brightnessID, Self.volumeID] : [])
        playground.preferredWidth = barWidth
        TouchBarPrivate.showsCloseBoxWhenFrontmost(true)
        TouchBarPrivate.present(touchBar, placement: useWide ? 1 : 0, trayItem: Self.trayID)
        playground.start()
        isShowing = true
    }

    private func hideFromTouchBar() {
        TouchBarPrivate.minimize(touchBar)
        playground.stop()
        isShowing = false
    }

    @objc private func toggleTouchBar() {
        if previewMode {
            previewWindow?.makeKeyAndOrderFront(nil)
            return
        }
        isShowing ? hideFromTouchBar() : showOnTouchBar()
    }

    private func showPreviewWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: barWidth, height: 30),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("Clawd Pet 미리보기", "Clawd Pet Preview")
        window.isReleasedWhenClosed = false
        window.contentView = playground
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }

    // MARK: - 메뉴 막대

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = runnerImages[0]
        item.button?.toolTip = "Clawd Pet"

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        countItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        linkItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        linkItem.isEnabled = false
        menu.addItem(.separator())
        // RunCat처럼 Mac 상태를 한눈에
        statsLines = (0..<6).map { _ in
            let line = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
            line.isEnabled = false
            return line
        }
        let sourceMenu = NSMenu()
        sourceItems = RunnerSource.allCases.map { source in
            let choice = sourceMenu.addItem(withTitle: source.title, action: #selector(chooseSource(_:)), keyEquivalent: "")
            choice.representedObject = source.rawValue
            choice.target = self
            return choice
        }
        let sourceItem = menu.addItem(withTitle: tr("달리기 기준", "Run speed follows"), action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceMenu
        menu.addItem(.separator())
        showItem = menu.addItem(withTitle: tr("Touch Bar에 보이기", "Show on Touch Bar"), action: #selector(toggleTouchBar), keyEquivalent: "")
        desktopItem = menu.addItem(withTitle: tr("화면 위에 띄우기 (Touch Bar 없이)", "Float on screen (no Touch Bar)"), action: #selector(toggleDesktop), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("완료 알림 모두 확인", "Mark all done notices read"), action: #selector(acknowledgeAll), keyEquivalent: "")
        menu.addItem(withTitle: tr("💡 아이디어", "💡 Ideas"), action: nil, keyEquivalent: "").submenu = ideasMenu
        menu.addItem(withTitle: tr("간식 떨어뜨리기 ✻", "Drop a treat ✻"), action: #selector(dropTreat), keyEquivalent: "")
        addItem = menu.addItem(withTitle: tr("Clawd 한 마리 더", "Add a Clawd"), action: #selector(addPet), keyEquivalent: "")
        removeItem = menu.addItem(withTitle: tr("Clawd 한 마리 보내기", "Send a Clawd home"), action: #selector(removePet), keyEquivalent: "")
        menu.addItem(.separator())
        bigItem = menu.addItem(withTitle: tr("크게 보기", "Bigger Clawds"), action: #selector(toggleBig), keyEquivalent: "")
        wideItem = menu.addItem(withTitle: tr("넓게 쓰기 (Control Strip 가리기)", "Full width (cover Control Strip)"), action: #selector(toggleWide), keyEquivalent: "")
        controlsItem = menu.addItem(withTitle: tr("밝기·소리 버튼", "Brightness & volume buttons"), action: #selector(toggleControls), keyEquivalent: "")
        metricsItem = menu.addItem(withTitle: tr("Touch Bar에 Mac 상태 보기", "Mac stats on Touch Bar"), action: #selector(toggleMetrics), keyEquivalent: "")
        menuBarPetItem = menu.addItem(withTitle: tr("메뉴 막대에서 돌아다니기", "Roam the menu bar"), action: #selector(toggleMenuBarPet), keyEquivalent: "")
        menu.addItem(.separator())
        connectItem = menu.addItem(withTitle: tr("Claude Code 연결", "Connect Claude Code"), action: #selector(toggleConnect), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: tr("로그인할 때 자동 실행", "Open at login"), action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("종료", "Quit"), action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu !== ideasMenu else { return }
        rebuildIdeasMenu()
        countItem.title = "Clawd × \(desktopMode ? petWindows.count : world.pets.count)"
        linkItem.title = world.link?.summaryLine ?? ""
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
        var lines = [
            "CPU \(percent(stats.cpu))% · GPU \(percent(stats.gpu))%",
            String(format: tr("메모리 %.1fGB 사용 (%d%%)", "Memory %.1f GB used (%d%%)"), stats.memoryUsedGB, percent(stats.memory)),
            String(format: tr("저장 공간 %.0fGB 남음 (%d%% 사용)", "Storage %.0f GB free (%d%% used)"), stats.diskFreeGB, percent(stats.disk)),
            stats.battery.map { tr("배터리", "Battery") + " \(percent($0.level))%" + ($0.charging ? tr(" (충전 중)", " (charging)") : "") } ?? tr("전원 어댑터 사용 중", "On power adapter"),
            tr("네트워크", "Network") + " ↓\(MetricsRenderer.rate(stats.download))/s ↑\(MetricsRenderer.rate(stats.upload))/s",
        ]
        if let usage = stats.claude {
            let parts = [usage.fiveHour.map { tr("5시간", "5h") + " \(percent($0.used))%" }, usage.sevenDay.map { tr("7일", "7d") + " \(percent($0.used))%" },
                         usage.context.map { tr("컨텍스트", "Context") + " \(percent($0))%" }].compactMap { $0 }
            lines.append(tr("Claude 사용량 ", "Claude usage ") + (parts.isEmpty ? (usage.model ?? "") : parts.joined(separator: " · ")))
        }
        for (i, line) in statsLines.enumerated() {
            line.title = i < lines.count ? lines[i] : ""
            line.isHidden = i >= lines.count
        }
        for choice in sourceItems {
            choice.state = choice.representedObject as? String == runnerSource.rawValue ? .on : .off
        }
        showItem.state = isShowing || previewMode ? .on : .off
        showItem.isEnabled = !desktopMode
        desktopItem.state = desktopMode ? .on : .off
        desktopItem.isEnabled = !previewMode
        let count = desktopMode ? petWindows.count : world.pets.count
        addItem.isEnabled = count < Self.maxPets
        removeItem.isEnabled = count > 1
        bigItem.state = big ? .on : .off
        wideItem.state = useWide ? .on : .off
        wideItem.isEnabled = !previewMode && !controlStripOnly
        wideItem.toolTip = controlStripOnly ? tr("Touch Bar가 확장된 Control Strip 모드라서 항상 넓게 표시돼요", "Your Touch Bar uses the Expanded Control Strip, so Clawd always uses the full width") : nil
        controlsItem.state = showControls ? .on : .off
        controlsItem.isEnabled = useWide && !previewMode
        metricsItem.state = showMetrics ? .on : .off
        menuBarPetItem.state = menuBarPet?.isShowing == true ? .on : .off
        menuBarPetItem.isEnabled = menuBarPet != nil
        metricsItem.isEnabled = !previewMode
        connectItem.title = ClaudeSetup.isConnected ? tr("Claude Code 연결 끊기", "Disconnect Claude Code") : tr("Claude Code 연결", "Connect Claude Code")
        loginItem.state = ClaudeSetup.launchesAtLogin ? .on : .off
        loginItem.isEnabled = ClaudeSetup.canAutoLaunch
    }

    /// 💡 아이디어 메뉴: 최근 아이디어(● = 아직 안 봄), 하나 던지기, 보고서 폴더
    private func rebuildIdeasMenu() {
        ideasMenu.removeAllItems()
        ideasMenu.autoenablesItems = false
        guard let box = world.ideas else { return }
        box.reload()
        if box.ideas.isEmpty {
            ideasMenu.addItem(withTitle: tr("아직 아이디어가 없어요 (리서치 루틴이 3시간마다 채워요)", "No ideas yet (an idea routine fills this up)"), action: nil, keyEquivalent: "").isEnabled = false
        }
        for idea in box.ideas.prefix(12) {
            let item = ideasMenu.addItem(withTitle: (box.isSeen(idea) ? "" : "● ") + idea.topic + " · " + idea.title,
                                         action: #selector(openIdea(_:)), keyEquivalent: "")
            item.representedObject = idea.id
            item.toolTip = idea.detail
            item.target = self
        }
        ideasMenu.addItem(.separator())
        let pitch = ideasMenu.addItem(withTitle: tr("지금 하나 던져 줘", "Pitch one now"), action: #selector(pitchIdea), keyEquivalent: "")
        pitch.target = self
        pitch.isEnabled = !box.unseen.isEmpty
        ideasMenu.addItem(withTitle: tr("리서치 보고서 폴더 열기", "Open research reports folder"), action: #selector(openReports), keyEquivalent: "").target = self
    }

    @objc private func openIdea(_ sender: NSMenuItem) {
        guard let box = world.ideas, let idea = box.ideas.first(where: { $0.id == sender.representedObject as? String }) else { return }
        box.markSeen(idea)
        IdeaBox.open(idea)
    }

    @objc private func pitchIdea() {
        if desktopMode { petWindows.first?.world.pitchIdeaNow(); return }
        if !isShowing && !previewMode { showOnTouchBar() }
        world.pitchIdeaNow()
        menuBarPet?.world.pitchIdeaNow()
    }

    @objc private func openReports() {
        let folder = world.ideas?.ideas.first?.report.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        NSWorkspace.shared.open(folder ?? IdeaBox.file.deletingLastPathComponent())
    }

    @objc private func acknowledgeAll() {
        world.acknowledgeAll()
    }

    @objc private func dropTreat() {
        if desktopMode { petWindows.randomElement()?.giveTreat(); return }
        if !isShowing && !previewMode { showOnTouchBar() }
        world.dropTreat()
        menuBarPet?.world.dropTreat()
    }

    @objc private func addPet() {
        if desktopMode {
            guard petWindows.count < Self.maxPets else { return }
            addPetWindow()
            petCount = petWindows.count
            return
        }
        guard world.pets.count < Self.maxPets else { return }
        world.addPet()
        petCount = world.pets.count
        menuBarPet?.world.addPet()
        menuBarPet?.petCount = petCount
    }

    @objc private func removePet() {
        if desktopMode {
            guard petWindows.count > 1 else { return }
            petWindows.removeLast().close()
            PetLedger.shared.remove(at: petWindows.count)
            petCount = petWindows.count
            return
        }
        guard world.pets.count > 1 else { return }
        world.setPetCount(world.pets.count - 1)
        petCount = world.pets.count
        menuBarPet?.world.setPetCount(petCount)
        menuBarPet?.petCount = petCount
    }

    @objc private func toggleBig() {
        big.toggle()
        world.px = big ? 2 : 1.5
        for w in petWindows { w.setPixel(desktopPixel) }
    }

    @objc private func chooseSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let source = RunnerSource(rawValue: raw) else { return }
        runnerSource = source
        world.busy = stats.value(for: source)
        metricsView.busy = world.busy
    }

    @objc private func toggleMenuBarPet() {
        guard let menuBarPet else { return }
        let show = !menuBarPet.isShowing
        defaults.set(show, forKey: Key.menuBarPet)
        show ? menuBarPet.show() : menuBarPet.hide()
    }

    @objc private func toggleMetrics() {
        showMetrics.toggle()
        representIfShowing()
    }

    @objc private func toggleControls() {
        showControls.toggle()
        representIfShowing()
    }

    @objc private func toggleWide() {
        wide.toggle()
        representIfShowing()
    }

    private func representIfShowing() {
        guard isShowing else { return }
        TouchBarPrivate.dismiss(touchBar)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.showOnTouchBar() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
