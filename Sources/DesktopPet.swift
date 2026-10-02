import AppKit

/// Clawd 한 마리의 생애 기록. ~/.clawd-touchbar/pets.json 에 순번대로 남는다.
struct PetRecord: Codable {
    var name: String
    var born: Date
    var seconds: Double = 0
    var treats = 0
    var pats = 0
    var dones = 0
    /// 친밀도: 쓰다듬기 +1(하루 60번까지), 간식 +3, 완료 확인 +5, 함께한 30분마다 +1
    var affection = 0
    var patsToday = 0
    var patsDay = ""

    static let levels: [(need: Int, title: String)] = tr(
        [(0, "낯가림"), (30, "아는 사이"), (100, "친구"), (300, "단짝"), (800, "가족"), (2000, "영혼의 단짝")],
        [(0, "Shy"), (30, "Acquaintance"), (100, "Friend"), (300, "Best friend"), (800, "Family"), (2000, "Soulmate")]
    )
    var level: Int { Self.levels.lastIndex { affection >= $0.need } ?? 0 }
    var levelTitle: String { Self.levels[level].title }
    var nextNeed: Int? { level + 1 < Self.levels.count ? Self.levels[level + 1].need : nil }
    /// "♥♥♡♡♡ 친구 · 123/300"
    var affectionLine: String {
        let hearts = String(repeating: "♥", count: level) + String(repeating: "♡", count: Self.levels.count - 1 - level)
        return "\(hearts) \(levelTitle) · " + (nextNeed.map { "\(affection)/\($0)" } ?? "\(affection)")
    }

    static let names = tr(["뭉치", "콩이", "호두", "두부", "감자", "모찌", "구름", "보리", "자두", "땅콩"],
                           ["Mochi", "Bean", "Walnut", "Tofu", "Potato", "Nugget", "Cloud", "Barley", "Plum", "Peanut"])

    var together: String {
        let total = Int(seconds)
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return tr("\(days)일 \(hours)시간", "\(days)d \(hours)h") }
        if hours > 0 { return tr("\(hours)시간 \(minutes)분", "\(hours)h \(minutes)m") }
        return tr("\(minutes)분", "\(minutes)m")
    }
}

final class PetLedger {
    static let shared = PetLedger()
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clawd-touchbar/pets.json")
    private(set) var records: [PetRecord] = []
    private var dirty = false

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let list = try? JSONDecoder().decode([PetRecord].self, from: data) { records = list }
    }

    /// 그 순번의 Clawd 기록. 없으면 오늘 태어난 새 Clawd
    func record(at slot: Int) -> PetRecord {
        while records.count <= slot {
            records.append(PetRecord(name: PetRecord.names[records.count % PetRecord.names.count], born: Date()))
        }
        return records[slot]
    }

    func update(_ slot: Int, _ change: (inout PetRecord) -> Void) {
        _ = record(at: slot)
        change(&records[slot])
        dirty = true
    }

    func remove(at slot: Int) {
        guard records.indices.contains(slot) else { return }
        records.remove(at: slot)
        save()
    }

    func saveIfNeeded() { if dirty { save() } }

    func save() {
        dirty = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.file, options: .atomic)
    }
}

/// 화면 위를 떠다니는 Clawd 한 마리. Touch Bar가 없는 맥을 위한 모드.
///
/// 투명한 창 하나에 작은 놀이터(Playground)를 넣고, Clawd는 늘 창 가운데에 둔다.
/// Clawd가 걸으면 그만큼 창이 화면에서 움직이고, 창 자체는 천천히 위아래로 떠다닌다.
/// 빈 곳은 클릭이 아래 창으로 통과하고, Clawd나 말풍선 위에서만 잡힌다 (Playground.transparent, 메뉴 막대 Clawd와 같은 방식).
final class PetWindow: NSObject {
    static let worldWidth: CGFloat = 480

    let world = Playground()
    let view: PlaygroundView
    let window: NSPanel

    private var driftVX: CGFloat = 0
    private var targetY: CGFloat = 0
    private var retargetIn = 0.0
    private var bob = Double.random(in: 0...6)
    private var heldMouseY: CGFloat?
    private var cursorAwayFor = 10.0
    private var lastMouseX: CGFloat?
    private var shakeDir: CGFloat = 0
    private var shakeCount = 0
    private var shakeTimer = 0.0
    private var announceFor = 0.0
    private var arrivedAtCursor = false
    var lastGreet: CFTimeInterval = 0
    /// 장부 순번 (한 마리를 보내면 뒤 번호가 당겨진다)
    var slot: Int
    private var saveIn = 15.0
    private var counted = (treats: 0, pats: 0, dones: 0)
    /// 간식을 떨어뜨렸을 때 (다른 Clawd가 달려오게)
    var onTreat: ((Treat, PetWindow) -> Void)?
    private var race: (source: PetWindow, treat: Treat, timeLeft: Double)?

    /// 메뉴의 "한 마리 더" / "보내기"
    var onAddPet: (() -> Void)?
    var onRemovePet: ((PetWindow) -> Void)?

    init(px: CGFloat, link: ClaudeLink?, slot: Int) {
        self.slot = slot
        _ = PetLedger.shared.record(at: slot)
        world.transparent = true
        world.px = px
        world.height = 15 * px
        world.width = Self.worldWidth
        world.link = link
        world.sessionOffset = slot
        world.addPet(at: Self.worldWidth / 2)

        view = PlaygroundView(world: world)
        view.preferredWidth = Self.worldWidth

        let size = NSSize(width: Self.worldWidth, height: world.height)
        // 비활성 패널: 클릭해도 쓰던 앱의 포커스를 뺏지 않고, 첫 클릭부터 Clawd에게 간다
        window = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]

        let area = Self.screenArea()
        window.setFrameOrigin(NSPoint(x: .random(in: area.minX...max(area.minX, area.maxX - size.width)),
                                      y: .random(in: area.minY...max(area.minY, area.maxY - size.height))))
        targetY = window.frame.minY
        super.init()
        view.onTick = { [weak self] in self?.tick() }
        view.onContextMenu = { [weak self] _, event in self?.showMenu(event) }
        window.orderFrontRegardless()
    }

    var pet: Clawd { world.pets[0] }

    // MARK: - 오른쪽 클릭 메뉴

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let r = record
        for line in [tr("\(r.name) · 함께한 지 \(r.together)", "\(r.name) · together for \(r.together)"), r.affectionLine, tr("간식 \(r.treats)개 · 쓰다듬기 \(r.pats)번 · 완료 확인 \(r.dones)번", "\(r.treats) treats · \(r.pats) pats · \(r.dones) done checks")] {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(withTitle: tr("이름 바꾸기…", "Rename…"), action: #selector(rename), keyEquivalent: "").target = self
        menu.addItem(.separator())
        for (title, action) in [(tr("간식 주기 ✻", "Give a treat ✻"), #selector(giveTreat)), (tr("쓰다듬기 ♥", "Pat ♥"), #selector(patPet))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Clawd 한 마리 더", "Add a Clawd"), action: #selector(addPet), keyEquivalent: "").target = self
        let bye = menu.addItem(withTitle: tr("이 Clawd 보내기", "Send this Clawd home"), action: #selector(removePet), keyEquivalent: "")
        bye.target = self
        bye.isEnabled = onRemovePet != nil
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// 들고 좌우로 세게 흔들면(1초 안에 방향 전환 5번) 어지러워한다
    private func trackShake(_ mouseX: CGFloat, dt: Double) {
        defer { lastMouseX = mouseX }
        shakeTimer -= dt
        if shakeTimer <= 0 { shakeCount = 0; shakeDir = 0 }
        guard let last = lastMouseX else { return }
        let dx = mouseX - last
        guard abs(dx) > 5 else { return }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if shakeDir != 0 && dir != shakeDir {
            shakeCount += 1
            shakeTimer = 1.0
            if shakeCount >= 5 {
                pet.dizzy(in: world)
                shakeCount = 0
            }
        }
        shakeDir = dir
    }

    /// 함께한 시간과 횟수를 장부에 모은다 (15초마다 저장)
    private func tickLedger(_ dt: Double) {
        let now = (pet.treatsEaten, pet.patsReceived, pet.donesSeen)
        let delta = (now.0 - counted.treats, now.1 - counted.pats, now.2 - counted.dones)
        counted = now
        let before = record.level
        PetLedger.shared.update(slot) {
            let halfHoursBefore = Int($0.seconds / 1800)
            $0.seconds += dt
            $0.treats += delta.0
            $0.pats += delta.1
            $0.dones += delta.2
            // 친밀도
            let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
            if $0.patsDay != today { $0.patsDay = today; $0.patsToday = 0 }
            let countedPats = min(delta.1, max(0, 60 - $0.patsToday))
            $0.patsToday += delta.1
            $0.affection += countedPats + delta.0 * 3 + delta.2 * 5 + (Int($0.seconds / 1800) - halfHoursBefore)
        }
        let r = record
        pet.affectionLevel = r.level
        if r.level > before {
            pet.celebrate("♥ \(r.levelTitle)!", tr("\(r.name)와 \(r.levelTitle)이 됐어요", "You and \(r.name) are now: \(r.levelTitle)"), in: world)
            PetLedger.shared.save()
        }
        saveIn -= dt
        if saveIn <= 0 {
            saveIn = 15
            PetLedger.shared.saveIfNeeded()
        }
    }

    /// 화면에서 Clawd가 있는 자리
    var screenCenter: NSPoint { NSPoint(x: window.frame.midX, y: window.frame.minY + world.spriteHeight / 2) }

    /// 다른 Clawd가 옆에 오면 그쪽을 보며 손을 흔든다
    func greet(toward dx: CGFloat) {
        pet.look = dx > 0 ? 1 : -1
        pet.wave(in: world)
        lastGreet = CACurrentMediaTime()
    }

    @objc private func rename() {
        let alert = NSAlert()
        alert.messageText = tr("이 Clawd의 이름", "Name this Clawd")
        alert.informativeText = tr("\(record.born.formatted(date: .abbreviated, time: .omitted))에 태어나 함께한 지 \(record.together).", "Born \(record.born.formatted(date: .abbreviated, time: .omitted)) · together for \(record.together).")
        let field = NSTextField(string: record.name)
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: tr("저장", "Save"))
        alert.addButton(withTitle: tr("취소", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        PetLedger.shared.update(slot) { $0.name = name }
        PetLedger.shared.save()
    }

    /// 간식은 Clawd 옆 조금 떨어진 곳에 떨어뜨려서 달려가 먹게 한다. 근처의 다른 Clawd도 달려온다.
    @objc func giveTreat() {
        let side: CGFloat = Bool.random() ? 1 : -1
        let treat = world.dropTreat(at: pet.x + side * .random(in: 70...150))
        onTreat?(treat, self)
    }

    /// 다른 Clawd의 간식을 보고 달려간다 (놀고 있을 때만). 먼저 닿으면 뺏어 먹고, 늦으면 시무룩.
    func race(for treat: Treat, in source: PetWindow) {
        guard !pet.hasJob, [.idle, .rest, .walk, .run, .hop, .clock].contains(pet.activity), race == nil else { return }
        race = (source, treat, 7)
    }

    private func tickRace(_ frame: inout NSRect, dt: CGFloat) {
        guard var r = race else { return }
        r.timeLeft -= Double(dt)
        race = r
        if r.treat.eaten || r.timeLeft <= 0 || pet.hasJob {
            race = nil
            if r.treat.eaten { pet.sulk(in: world) }
            return
        }
        let goal = NSPoint(x: r.source.window.frame.minX + r.treat.x, y: r.source.window.frame.minY)
        let here = NSPoint(x: frame.minX + pet.x, y: frame.minY)
        let dx = goal.x - here.x, dy = goal.y - here.y
        if abs(dx) < 36 && abs(dy) < 40 {
            // 도착! 아직 남아 있으면 뺏어 온다
            r.source.world.eat(r.treat)
            world.dropTreat(at: pet.x + (dx > 0 ? 1 : -1) * 30)
            race = nil
            return
        }
        pet.facing = dx > 0 ? 1 : -1
        pet.start(.run, seconds: 0.4)
        frame.origin.x += max(-320 * dt, min(320 * dt, dx))
        frame.origin.y += max(-220 * dt, min(220 * dt, dy))
    }

    @objc private func patPet() { pet.pat(in: world) }
    @objc private func addPet() { onAddPet?() }
    @objc private func removePet() { onRemovePet?(self) }

    func close() {
        view.onTick = nil
        window.orderOut(nil)
        PetLedger.shared.saveIfNeeded()
    }

    var record: PetRecord { PetLedger.shared.record(at: slot) }

    func setPixel(_ px: CGFloat) {
        world.transparent = true
        world.px = px
        world.height = 15 * px
        var frame = window.frame
        frame.size.height = world.height
        window.setFrame(frame, display: true)
    }

    private static func screenArea() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 매 프레임: Clawd를 창 가운데로 되돌리고 그만큼 창을 옮긴 뒤, 떠다니기와 화면 끝 처리
    private func tick() {
        let dt: CGFloat = 1.0 / 60.0
        let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? Self.screenArea()
        var frame = window.frame

        let dx = pet.x - Self.worldWidth / 2
        if dx != 0 {
            world.shift(by: dx)
            frame.origin.x += dx
        }

        retargetIn -= Double(dt)
        if retargetIn <= 0 {
            retargetIn = .random(in: 4...9)
            targetY = .random(in: area.minY...max(area.minY, area.maxY - frame.height))
            driftVX = .random(in: -10...10)
        }
        // 자거나 일할 때는 거의 멈춰 있고, 놀 때만 떠다닌다
        let still: Bool
        switch pet.activity {
        case .sleep, .rest, .think, .study, .craft, .exercise, .call, .held: still = true
        default: still = false
        }
        let cursorNear = window.frame.insetBy(dx: -80, dy: -80).contains(NSEvent.mouseLocation)
        if !still && !cursorNear {
            frame.origin.x += driftVX * dt
            frame.origin.y += (targetY - frame.origin.y) * min(1, 0.6 * dt)
        }
        // 들어 올린 채 끌면 마우스를 따라 위아래로도 옮긴다 (좌우는 Clawd의 x를 되돌리며 창이 따라간다)
        if pet.activity == .held {
            let mouseY = NSEvent.mouseLocation.y
            if let last = heldMouseY { frame.origin.y += mouseY - last }
            heldMouseY = mouseY
            trackShake(NSEvent.mouseLocation.x, dt: Double(dt))
        } else {
            heldMouseY = nil
            lastMouseX = nil
            shakeCount = 0
        }
        tickRace(&frame, dt: dt)
        tickLedger(Double(dt))
        // 완료 알림을 한참 안 보면 커서 옆까지 찾아온다
        // 한 번 도착하면 더 따라가지 않고, 커서가 가까이 오면 그 자리에 멈춘다 (클릭하려는데 도망가지 않게)
        if pet.activity == .announce {
            announceFor += Double(dt)
        } else {
            announceFor = 0
            arrivedAtCursor = false
        }
        if announceFor > 45 && !arrivedAtCursor && !cursorNear {
            let mouse = NSEvent.mouseLocation
            let here = NSPoint(x: frame.minX + pet.x, y: frame.midY)
            if abs(mouse.x - here.x) < 260 && abs(mouse.y - here.y) < 160 {
                arrivedAtCursor = true
            } else {
                let side: CGFloat = mouse.x > here.x ? -1 : 1
                let wantX = mouse.x - frame.width / 2 + side * 170
                let wantY = mouse.y - frame.height / 2
                frame.origin.x += (wantX - frame.origin.x) * min(1, 1.2 * dt)
                frame.origin.y += (wantY - frame.origin.y) * min(1, 1.2 * dt)
                pet.look = side > 0 ? -1 : 1
            }
        }
        // 마우스가 다가오면 쳐다보고, 오랜만이면 손을 흔든다
        let mouse = NSEvent.mouseLocation
        if window.frame.insetBy(dx: -60, dy: -60).contains(mouse) {
            let local = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
            if abs(local.x - pet.x) < 160 {
                if cursorAwayFor > 4 && record.level >= 1 { pet.wave(in: world) }
                cursorAwayFor = 0
                pet.watch(cursorAt: local.x - pet.x)
            } else {
                cursorAwayFor += Double(dt)
            }
        } else {
            cursorAwayFor += Double(dt)
        }
        bob += Double(dt)
        frame.origin.y += CGFloat(sin(bob * 1.4)) * 0.08

        let maxX = max(area.minX, area.maxX - frame.width)
        if frame.origin.x <= area.minX { frame.origin.x = area.minX; pet.facing = 1; driftVX = abs(driftVX) }
        if frame.origin.x >= maxX { frame.origin.x = maxX; pet.facing = -1; driftVX = -abs(driftVX) }
        frame.origin.y = min(max(frame.origin.y, area.minY), max(area.minY, area.maxY - frame.height))
        if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin) }

    }
}
