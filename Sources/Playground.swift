import AppKit

final class Treat {
    var x: CGFloat
    var y: CGFloat
    var vy: CGFloat = 0
    var age: Double = 0
    var eaten = false

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

struct Particle {
    enum Kind {
        case heart
        case dust
        case sweat
        case steam
        case text(String, NSColor, CGFloat)
    }

    var kind: Kind
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var life: Double
    var age: Double = 0

    var alpha: CGFloat { CGFloat(max(0, min(1, (life - age) / min(life, 0.35)))) }
}

/// Touch Bar 위의 작은 세계: Clawd들, 간식, 파티클.
final class Playground {
    var height: CGFloat = 30
    var width: CGFloat = 685 {
        didSet { if width != oldValue { clampEverything() } }
    }
    var px: CGFloat = 2 {
        didSet { clampEverything() }
    }
    let gravity: CGFloat = 700

    /// Mac이 얼마나 바쁜지 (0...1, 기준은 CPU·메모리·GPU 중 고른 것). RunCat처럼 바쁠수록 Clawd가 빨리 달린다.
    var busy = 0.0

    /// 메뉴 막대처럼 다른 화면 위에 겹쳐 그릴 때: 검은 바탕 없이, 글자엔 어두운 받침
    var transparent = false

    /// Claude Code 훅과의 연결. 없으면 그냥 자유롭게 논다.
    var link: ClaudeLink?
    /// 세계가 여럿일 때(화면 위 모드) 이 세계가 맡는 세션 순번의 시작
    var sessionOffset = 0
    private var pollIn = 0.0
    private let startedAt = Date()

    var idleSeconds: TimeInterval { link?.idleSeconds ?? Date().timeIntervalSince(startedAt) }

    /// 밝기·소리를 바꾸면 잠깐 뜨는 레벨 표시
    struct Gauge {
        enum Kind { case brightness, volume, muted }
        var kind: Kind
        var level: Float
        var age = 0.0
    }
    private(set) var gauge: Gauge?

    func showGauge(_ kind: Gauge.Kind, level: Float) {
        gauge = Gauge(kind: kind, level: level)
    }

    private(set) var pets: [Clawd] = []
    private(set) var treats: [Treat] = []
    var particles: [Particle] = []

    var spriteWidth: CGFloat { CGFloat(ClawdSprite.cols) * px }
    var spriteHeight: CGFloat { CGFloat(ClawdSprite.rows) * px }
    var headroom: CGFloat { height - spriteHeight }
    var minX: CGFloat { spriteWidth / 2 + 1 }
    var maxX: CGFloat { max(minX, width - spriteWidth / 2 - 1) }

    /// 머리가 천장에 닿기 직전까지 뛰는 초속
    func jumpVelocity(_ fraction: CGFloat = 1) -> CGFloat {
        sqrt(2 * gravity * max(2, (headroom - 1) * fraction))
    }

    // MARK: - 구성

    func setPetCount(_ count: Int) {
        while pets.count < count { addPet() }
        while pets.count > count { pets.removeLast() }
    }

    func addPet(at x: CGFloat? = nil) {
        let pet = Clawd(x: x ?? CGFloat.random(in: minX...maxX))
        pet.y = height
        pet.activity = .fall
        pets.append(pet)
    }

    @discardableResult
    func dropTreat(at x: CGFloat? = nil) -> Treat {
        if treats.count >= 8 { treats.removeFirst() }
        let tx = min(max(x ?? CGFloat.random(in: minX...maxX), 5), width - 5)
        let treat = Treat(x: tx, y: height - 4)
        treats.append(treat)
        for pet in pets { pet.noticeTreat(in: self) }
        return treat
    }

    func pet(at x: CGFloat) -> Clawd? {
        // 말풍선을 쳐도 그 Clawd를 친 것으로 본다
        pets.reversed().first { $0.bubbleFrame.map { ($0.minX...$0.maxX).contains(x) } ?? false }
            ?? pets.reversed().first { abs($0.x - x) <= spriteWidth / 2 + 6 }
    }

    /// 리서치 루틴이 남긴 아이디어 상자. 가끔 놀고 있는 Clawd가 하나씩 던진다.
    var ideas: IdeaBox?
    private var ideaIn = 2.0

    private func checkIdeas() {
        guard let ideas else { return }
        ideas.reload()
        guard !pets.contains(where: { $0.activity == .idea }) else { return }
        let free = pets.filter { !$0.hasJob && ![.held, .fall, .chase].contains($0.activity) }
        guard !free.isEmpty, let idea = ideas.due() else { return }
        // 그 주제를 다뤘던 Clawd가 먼저, 아니면 시계 담당이 아닌 아무나
        let pitcher = free.first { pet in pet.lastTopic.map { $0.contains(idea.topic) || idea.topic.contains($0) } ?? false }
            ?? free.first { $0.clockRole != .keeper } ?? free[0]
        pitcher.pitch(idea, in: self)
    }

    func pitchIdeaNow() {
        ideas?.pitchSoon()
        ideaIn = 0
    }

    func ideaTapped(_ idea: IdeaBox.Idea) {
        ideas?.markSeen(idea)
        IdeaBox.open(idea)
    }

    func ideaPassed(_ idea: IdeaBox.Idea) {
        ideas?.shown(idea)
    }

    private var lastHour: Int?
    private var clockIn = 0.0

    /// 놀고 있는 Clawd가 둘 이상이면 한 마리는 늘 시계를 들고, 혼자면 가끔 든다. 정각엔 "땡!"
    private func assignClockKeeper() {
        let free = pets.filter { !$0.hasJob }
        for pet in pets {
            if !free.contains(where: { $0 === pet }) {
                pet.clockRole = .none
            } else if free.count >= 2 {
                pet.clockRole = pet === free.first ? .keeper : .none
            } else {
                pet.clockRole = .sometimes
            }
        }

        let hour = Calendar.current.component(.hour, from: Date())
        if let lastHour, lastHour != hour {
            (pets.first { $0.showsClock } ?? pets.first { $0.clockRole == .keeper })?.chime(in: self)
        }
        lastHour = hour
    }

    /// 완료 알림 확인
    func acknowledge(_ pet: Clawd) {
        if let id = pet.sessionID {
            link?.focusApp(of: id)   // 작업하던 창으로 데려다 준다
            link?.acknowledge(id)
        }
        pollIn = 0
    }

    /// 앱 언어를 바꿨을 때 떠 있는 이름표·말풍선을 새 언어로
    func relocalize() {
        pets.forEach { $0.relocalize() }
    }

    func acknowledgeAll() {
        link?.acknowledgeAll()
        pollIn = 0
    }

    func nearestTreat(to x: CGFloat) -> Treat? {
        treats.filter { !$0.eaten }.min { abs($0.x - x) < abs($1.x - x) }
    }

    func eat(_ treat: Treat) {
        treat.eaten = true
        treats.removeAll { $0 === treat }
    }

    func emit(_ kind: Particle.Kind, x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0, life: Double) {
        particles.append(Particle(kind: kind, x: x, y: y, vx: vx, vy: vy, life: life))
    }

    func puffDust(at x: CGFloat) {
        for dir in [-1.0, 1.0] as [CGFloat] {
            for i in 0..<2 {
                emit(.dust, x: x + dir * (spriteWidth * 0.3 + CGFloat(i) * 2), y: 1,
                     vx: dir * CGFloat.random(in: 12...28), vy: CGFloat.random(in: 4...12), life: 0.35)
            }
        }
    }

    /// 세계 안의 모든 것을 옆으로 옮긴다 (화면 위 모드에서 Clawd를 창 가운데에 두기 위해)
    func shift(by dx: CGFloat) {
        for pet in pets { pet.x -= dx }
        for treat in treats { treat.x -= dx }
        for i in particles.indices { particles[i].x -= dx }
    }

    private func clampEverything() {
        for pet in pets { pet.x = min(max(pet.x, minX), maxX) }
        for treat in treats { treat.x = min(max(treat.x, 5), max(5, width - 5)) }
    }

    // MARK: - 시뮬레이션

    func update(_ dt: Double) {
        let t = CGFloat(dt)

        for treat in treats {
            treat.age += dt
            guard treat.y > 0 || treat.vy != 0 else { continue }
            treat.vy -= gravity * 0.55 * t
            treat.y += treat.vy * t
            if treat.y <= 0 {
                treat.y = 0
                treat.vy = abs(treat.vy) > 40 ? -treat.vy * 0.4 : 0
            }
        }

        pollIn -= dt
        if pollIn <= 0, let link {
            pollIn = 0.25
            link.poll()
            let sessions = link.active
            for (i, pet) in pets.enumerated() {
                pet.assign(i + sessionOffset < sessions.count ? sessions[i + sessionOffset] : nil, in: self)
            }
        }
        ideaIn -= dt
        if ideaIn <= 0 {
            ideaIn = 5
            checkIdeas()
        }
        clockIn -= dt
        if clockIn <= 0 {
            clockIn = 0.25
            assignClockKeeper()
        }

        for pet in pets { pet.update(dt, in: self) }

        gauge?.age += dt
        if let g = gauge, g.age > 1.6 { gauge = nil }

        for i in particles.indices {
            particles[i].age += dt
            particles[i].x += particles[i].vx * t
            particles[i].y += particles[i].vy * t
            switch particles[i].kind {
            case .dust, .sweat: particles[i].vy -= 60 * t
            case .steam: particles[i].vx *= 0.96
            default: break
            }
        }
        particles.removeAll { $0.age >= $0.life }
    }
}
