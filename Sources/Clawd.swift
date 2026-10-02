import AppKit

/// Touch Bar 위를 돌아다니는 Clawd 한 마리.
/// Claude가 쉬면 놀고·쉬고·자고, 일하면 공부·운동·작업을 하고, 끝나면 말풍선으로 알려 준다.
final class Clawd {
    enum Activity {
        // 자유 시간
        case idle, rest, walk, run, hop, sleep, chase, cheer, clock, idea
        // 손에 들렸을 때
        case held, fall
        // Claude가 일할 때
        case think, study, craft, exercise, call, announce

        /// Claude가 실제로 일하는 동안의 행동 (오래 걸리면 기분이 나빠진다)
        var isWorking: Bool {
            switch self {
            case .think, .study, .craft, .exercise: return true
            default: return false
            }
        }

        var isJob: Bool {
            switch self {
            case .think, .study, .craft, .exercise, .call, .announce: return true
            default: return false
            }
        }
    }

    struct Speech {
        let title: String
        let text: String
    }

    struct Thought {
        let glyph: String
        let text: String
        let grumpy: Bool
    }

    /// 일이 길어질수록: 집중 → 지침(2분) → 짜증(5분) → 폭발(10분)
    enum Mood: Int { case calm, tired, annoyed, furious }
    static let moodMinutes: [Double] = [2, 5, 10]

    static let spinner = ["·", "✢", "✳\u{FE0E}", "✶", "✻", "✽", "✻", "✶", "✳\u{FE0E}", "✢"]

    var x: CGFloat
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var facing: CGFloat
    var look = 0
    var activity = Activity.idle

    /// 시계 담당: keeper는 놀 때 늘 시계를 들고, sometimes는 혼자 놀다가 가끔 든다
    enum ClockRole { case none, keeper, sometimes }
    var clockRole = ClockRole.none {
        didSet {
            guard clockRole != oldValue, job == nil else { return }
            // 새로 시계 담당이 되면 하던 놀이를 곧 멈추고, 담당이 끝나면 팻말을 내려놓는다
            if clockRole == .keeper, [.idle, .rest, .walk, .run, .hop].contains(activity) { timeLeft = min(timeLeft, 0.3) }
            if clockRole == .none, activity == .clock { timeLeft = 0 }
        }
    }

    /// 머리 위에 시계 팻말을 들고 있는지
    var showsClock: Bool {
        activity == .clock || (activity == .walk && clockRole == .keeper)
    }

    private var timeLeft = 1.0
    private var clock = Double.random(in: 0...1)
    private var activityClock = 0.0
    private var blinkIn = Double.random(in: 1.5...4)
    private var blinkFor = 0.0
    private var happyFor = 0.0
    private var lookIn = 1.0
    private var zIn = 0.0
    private var sweatIn = 0.0
    private var moodIn = 0.0
    private var attentionIn = 0.0
    private var grumble: String?
    private var dizzyFor = 0.0
    /// 함께한 기록 (화면 위 모드의 장부가 모아 간다)
    private(set) var treatsEaten = 0
    private(set) var patsReceived = 0
    private(set) var donesSeen = 0
    /// 친밀도 단계 (장부가 넣어 준다). 높을수록 더 반갑게 군다
    var affectionLevel = 0
    private var dizzyStarIn = 0.0
    private var yawnFor = 0.0
    private var grumbleFor = 0.0
    private var moving = false
    private var legPeriod = 0.08
    private weak var target: Treat?

    private var job: ClaudeLink.Status?
    private(set) var sessionID: String?
    private var workStart: Date?
    /// 렌더러가 그린 말풍선 자리 (말풍선을 톡 쳐도 확인되게)
    var bubbleFrame: CGRect?
    private var jobKey = ""
    private var label: String?
    private var speech: Speech?

    var isAirborne: Bool { y > 0 || vy != 0 }
    var hasJob: Bool { job != nil }
    /// 마지막으로 맡았던 Claude 세션의 주제 (그 주제 아이디어는 이 Clawd가 던진다)
    private(set) var lastTopic: String?
    private(set) var pitchedIdea: IdeaBox.Idea?
    /// 깜빡이는 효과용 시계
    var time: Double { clock }

    init(x: CGFloat) {
        self.x = x
        facing = Bool.random() ? 1 : -1
    }

    // MARK: - 매 프레임

    func update(_ dt: Double, in world: Playground) {
        clock += dt
        activityClock += dt
        timeLeft -= dt
        happyFor = max(0, happyFor - dt)
        grumbleFor = max(0, grumbleFor - dt)
        tickBlink(dt)
        yawnFor = max(0, yawnFor - dt)
        if dizzyFor > 0 {
            dizzyFor -= dt
            dizzyStarIn -= dt
            if dizzyStarIn <= 0 {
                dizzyStarIn = 0.35
                let side: CGFloat = Bool.random() ? 1 : -1
                world.emit(.text("✦", NSColor(cgColor: Palette.treat)!, 8), x: x + side * world.px * 5, y: world.spriteHeight + world.px,
                           vx: -side * 14, vy: 10, life: 0.9)
            }
        }

        if activity == .held { return }

        if isAirborne {
            vy -= world.gravity * CGFloat(dt)
            y += vy * CGFloat(dt)
            if y <= 0 { land(in: world) }
        }

        switch activity {
        case .idle, .rest:
            lookIn -= dt
            if lookIn <= 0 {
                lookIn = activity == .rest ? .random(in: 1.5...3.5) : .random(in: 0.8...2.2)
                look = [-1, 0, 0, 1].randomElement()!
                if look != 0 { facing = CGFloat(look) }
            }
            if timeLeft <= 0 { decide(world) }
        case .walk:
            stroll(speed: clockRole == .keeper ? 12 : 20, dt, world)
        case .clock:
            // 가끔 팻말을 올려다보며 시간을 확인한다
            lookIn -= dt
            if lookIn <= 0 { lookIn = .random(in: 2...4) }
            if timeLeft <= 0 { decide(world) }
        case .run:
            // CPU가 높을수록 빨라진다 (45 → 165pt/초)
            legPeriod = max(0.035, 0.09 - 0.055 * world.busy)
            stroll(speed: 45 + 120 * CGFloat(world.busy), dt, world)
            if world.busy > 0.8 {
                sweatIn -= dt
                if sweatIn <= 0 {
                    sweatIn = .random(in: 0.4...0.8)
                    world.emit(.sweat, x: x - facing * world.px * 8, y: world.spriteHeight - world.px * 2,
                               vx: -facing * 12, vy: 12, life: 0.5)
                }
            }
        case .hop:
            stroll(speed: 30, dt, world)
            if activity == .hop && !isAirborne { vy = world.jumpVelocity(0.45) }
        case .cheer:
            if timeLeft <= 0 && !isAirborne {
                speech = nil   // 축하 말풍선은 여기까지
                decide(world)
            }
        case .sleep:
            zIn -= dt
            if zIn <= 0 {
                zIn = 0.9
                world.emit(.text("z", Palette.text, CGFloat.random(in: 7...9)),
                           x: x + facing * world.px * 6, y: world.px * 7,
                           vx: facing * 5, vy: 6, life: 1.6)
            }
            if timeLeft <= 0 {
                begin(.idle, for: 1...2)
                look = 0
            }
        case .chase:
            chase(dt, world)
        case .exercise:
            sweatIn -= dt
            if sweatIn <= 0 {
                sweatIn = .random(in: 0.6...1.2)
                let side: CGFloat = Bool.random() ? 1 : -1
                world.emit(.sweat, x: x + side * world.px * 7, y: world.spriteHeight - world.px * 2,
                           vx: side * 10, vy: 14, life: 0.6)
            }
        case .announce:
            // 확인할 때까지 가끔 폴짝 뛰며 봐 달라고 한다
            attentionIn -= dt
            if attentionIn <= 0 {
                attentionIn = .random(in: 5...8)
                if !isAirborne { vy = world.jumpVelocity(0.5) }
            }
        case .idea:
            // 다른 곳(Touch Bar나 메뉴 막대)에서 이미 확인했으면 같이 내린다
            if let idea = pitchedIdea, world.ideas?.isSeen(idea) == true {
                pitchedIdea = nil
                speech = nil
                happyFor = 1
                begin(.cheer, for: 0.6...0.9)
                return
            }
            // 아이디어 말풍선을 들고 가끔 폴짝. 시간이 지나면 말풍선을 내린다.
            attentionIn -= dt
            if attentionIn <= 0 {
                attentionIn = .random(in: 6...9)
                if !isAirborne { vy = world.jumpVelocity(0.5) }
            }
            if timeLeft <= 0 && !isAirborne {
                if let idea = pitchedIdea { world.ideaPassed(idea) }
                pitchedIdea = nil
                speech = nil
                decide(world)
            }
        case .think, .study, .craft, .call, .held, .fall:
            break
        }

        if activity.isWorking { tickMood(dt, world) }
    }

    // MARK: - 기분 (일이 오래 걸릴수록 나빠진다)

    var mood: Mood {
        guard activity.isWorking, let workStart else { return .calm }
        let minutes = Date().timeIntervalSince(workStart) / 60
        return Mood(rawValue: Self.moodMinutes.filter { minutes >= $0 }.count) ?? .calm
    }

    /// 짜증 날수록 붉어지는 정도
    var heat: CGFloat {
        switch mood {
        case .calm, .tired: return 0
        case .annoyed: return 0.15
        case .furious: return 0.3 + 0.08 * CGFloat(sin(clock * 6))
        }
    }

    /// 폭발 직전엔 가끔 부들부들 떤다
    var shake: CGFloat {
        if dizzyFor > 0 { return CGFloat(sin(clock * 18)) * 1.5 }
        guard mood == .furious, clock.truncatingRemainder(dividingBy: 2.5) < 0.6 else { return 0 }
        return Int(clock / 0.05) % 2 == 0 ? 0.5 : -0.5
    }

    private func tickMood(_ dt: Double, _ world: Playground) {
        moodIn -= dt
        guard moodIn <= 0 else { return }
        let top = frame.sitting ? world.px * 8 : world.spriteHeight
        switch mood {
        case .calm:
            moodIn = 2
        case .tired:
            moodIn = .random(in: 3...5)
            let side: CGFloat = Bool.random() ? 1 : -1
            world.emit(.sweat, x: x + side * world.px * 7, y: top - world.px * 2, vx: side * 10, vy: 14, life: 0.6)
            if Double.random(in: 0..<1) < 0.3 { say(tr(["휴…", "하아…", "좀 걸리네…"], ["Phew…", "Sigh…", "Taking a while…"])) }
        case .annoyed:
            moodIn = .random(in: 1.2...2)
            steam(world, top: top)
            if Double.random(in: 0..<1) < 0.2 { say(tr(["으으…", "아직이야?", "왜 이렇게 오래 걸려…"], ["Ugh…", "Still going?", "Why so long…"])) }
        case .furious:
            moodIn = .random(in: 0.5...0.9)
            steam(world, top: top)
            if Double.random(in: 0..<1) < 0.12 { say(tr(["언제 끝나!", "으아악!", "너무 오래 걸려!", "빨리빨리!"], ["When will it end?!", "Argh!", "Way too long!", "Hurry up!"])) }
            // 서 있을 땐 발을 구른다
            if !frame.sitting && !isAirborne && Double.random(in: 0..<1) < 0.15 { vy = world.jumpVelocity(0.25) }
        }
    }

    private func steam(_ world: Playground, top: CGFloat) {
        for side in [-1.0, 1.0] as [CGFloat] {
            world.emit(.steam, x: x + side * world.px * 3, y: top, vx: side * 5, vy: 12, life: 0.8)
        }
    }

    private func say(_ lines: [String]) {
        grumble = lines.randomElement()
        grumbleFor = 2.2
    }

    private func tickBlink(_ dt: Double) {
        if blinkFor > 0 {
            blinkFor -= dt
            return
        }
        blinkIn -= dt
        if blinkIn <= 0 {
            blinkFor = 0.12
            blinkIn = .random(in: 2...5)
        }
    }

    private func begin(_ activity: Activity, for seconds: ClosedRange<Double>) {
        self.activity = activity
        timeLeft = .random(in: seconds)
        activityClock = 0
    }

    /// 스냅샷 확인용: 특정 행동을 바로 시작시킨다
    func start(_ activity: Activity, seconds: Double) {
        begin(activity, for: seconds...seconds)
        if activity == .sleep { zIn = 0 }
        look = [.walk, .run, .hop].contains(activity) ? Int(facing) : 0
    }

    /// 자유 시간에 다음에 할 일 고르기. Claude가 오래 쉴수록 잠이 많아진다.
    private func decide(_ world: Playground) {
        if job != nil {
            applyJob(world)
            return
        }
        if world.nearestTreat(to: x) != nil {
            startChase(world)
            return
        }
        // 시계 담당은 팻말을 들고 서 있거나 천천히 걸어 다닌다
        if clockRole == .keeper {
            if Double.random(in: 0..<1) < 0.75 {
                begin(.clock, for: 6...14)
                look = 0
            } else {
                begin(.walk, for: 2...4)
                pickDirection(world)
            }
            return
        }
        // 혼자 놀 때는 가끔 시계를 들어 보여 준다
        if clockRole == .sometimes && Double.random(in: 0..<1) < 0.15 {
            begin(.clock, for: 5...9)
            look = 0
            return
        }
        // RunCat처럼: Mac이 바쁠수록 자주, 오래 달린다
        if world.busy > 0.3 && Double.random(in: 0..<1) < world.busy * 1.3 {
            begin(.run, for: 2...4)
            pickDirection(world)
            return
        }
        if dizzyFor > 0 {
            begin(.idle, for: 0.5...1)
            return
        }
        var sleepy = min(0.55, 0.06 + world.idleSeconds / 1500) * (1 - world.busy)
        if Self.isNight { sleepy = max(sleepy, 0.45) }   // 밤 11시 넘으면 금방 졸린다
        if Double.random(in: 0..<1) < sleepy {
            begin(.sleep, for: 8...16)
            zIn = 0.4
            return
        }
        let choices: [(Activity, Double)] = [(.idle, 2), (.rest, 2), (.walk, 3), (.run, 1), (.hop, 1.2)]
        var roll = Double.random(in: 0..<choices.reduce(0) { $0 + $1.1 })
        let next = choices.first { roll -= $0.1; return roll < 0 }?.0 ?? .idle
        switch next {
        case .idle: begin(.idle, for: 1.5...4)
        case .rest: begin(.rest, for: 3...7)
        case .walk: begin(.walk, for: 2...5)
        case .run: begin(.run, for: 1...2.2)
        default: begin(.hop, for: 1.2...2.5)
        }
        if [.walk, .run, .hop].contains(next) { pickDirection(world) } else { look = 0 }
        if Self.isNight && (next == .idle || next == .rest) && Double.random(in: 0..<1) < 0.5 { yawn(world) }
    }

    /// 밤 11시 ~ 아침 6시
    static var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 6
    }

    private func yawn(_ world: Playground) {
        yawnFor = 1.3
        world.emit(.text(tr("하암…", "Yawn…"), Palette.text, 8), x: x + facing * world.px * 7, y: world.spriteHeight - world.px * 3,
                   vx: facing * 4, vy: 7, life: 1.4)
    }

    private func pickDirection(_ world: Playground) {
        if Bool.random() { facing = -facing }
        if x <= world.minX + 4 { facing = 1 }
        if x >= world.maxX - 4 { facing = -1 }
        look = Int(facing)
    }

    private func stroll(speed: CGFloat, _ dt: Double, _ world: Playground) {
        x += facing * speed * CGFloat(dt)
        if x <= world.minX { x = world.minX; facing = 1 }
        if x >= world.maxX { x = world.maxX; facing = -1 }
        look = Int(facing)
        if timeLeft <= 0 && !isAirborne { decide(world) }
    }

    private func land(in world: Playground) {
        y = 0
        vy = 0
        if activity == .fall {
            world.puffDust(at: x)
            if job != nil {
                applyJob(world)
            } else if dizzyFor > 0 {
                begin(.idle, for: dizzyFor...dizzyFor)
                look = 0
            } else {
                begin(.idle, for: 0.5...0.9)
                look = 0
            }
        }
    }

    // MARK: - Claude 연동

    /// 이 Clawd가 맡은 Claude 세션의 상태가 바뀌면 하던 일을 바꾼다.
    func assign(_ session: ClaudeLink.Session?, in world: Playground) {
        sessionID = session?.id
        if let topic = session?.topic { lastTopic = topic }
        workStart = session?.workStart
        let status = session?.status
        let key = status.map { "\($0)" } ?? ""
        guard key != jobKey else { return }
        jobKey = key
        job = status
        if activity == .held || activity == .fall { return }   // 내려놓으면 그때 적용
        applyJob(world)
    }

    private func applyJob(_ world: Playground) {
        // 아이디어를 던지는 중엔 쉬러 가라는 신호는 무시하고, 일이 생기면 내려놓는다 (나중에 다시 던진다)
        if activity == .idea && job == nil { return }
        if let idea = pitchedIdea, job != nil {
            world.ideaPassed(idea)
            pitchedIdea = nil
        }
        target = nil
        moving = false
        label = nil
        speech = nil

        guard let job else {
            // Claude가 쉬러 갔다 → 자유 시간
            if activity.isJob {
                begin(.idle, for: 1...2)
                look = 0
            }
            return
        }

        if activity == .sleep { exclaim("!", in: world) }
        look = 0
        let forever = 1e9...1e9

        (label, speech) = Self.captions(for: job)
        switch job {
        case .working(let work, _):
            switch work {
            case .think: begin(.think, for: forever)
            case .study: begin(.study, for: forever)
            case .exercise:
                begin(.exercise, for: forever)
                sweatIn = 0.5
            case .craft: begin(.craft, for: forever)
            }
        case .waiting:
            begin(.call, for: forever)
            exclaim("!", in: world)
        case .done:
            begin(.announce, for: forever)
            happyFor = 2
            if !isAirborne { vy = world.jumpVelocity(0.9) }
            heart(in: world)
        }
    }

    /// 맡은 일의 이름표("공부 중 · 주제")와 말풍선("완료!")
    private static func captions(for job: ClaudeLink.Status) -> (label: String?, speech: Speech?) {
        switch job {
        case .working(let work, let detail):
            let suffix = detail.isEmpty ? "" : " · " + detail
            switch work {
            case .think: return (tr("생각 중", "Thinking") + (detail.isEmpty ? "…" : suffix), nil)
            case .study: return (tr("공부 중", "Studying") + suffix, nil)
            case .exercise: return (tr("운동 중", "Working out") + suffix, nil)
            case .craft: return (tr("작업 중", "Working") + suffix, nil)
            }
        case .waiting(let message): return (nil, Speech(title: tr("잠깐!", "Wait!"), text: message))
        case .done(let summary): return (nil, Speech(title: tr("완료!", "Done!"), text: summary))
        }
    }

    /// 앱 언어를 바꾸면 지금 떠 있는 이름표·말풍선도 새 언어로
    func relocalize() {
        if activity == .idea, let idea = pitchedIdea {
            speech = Self.ideaSpeech(idea)
        } else if let job, activity.isJob {
            (label, speech) = Self.captions(for: job)
        }
    }

    private static func ideaSpeech(_ idea: IdeaBox.Idea) -> Speech {
        Speech(title: tr("💡 아이디어!", "💡 Idea!"), text: idea.topic + " · " + idea.title)
    }

    // MARK: - 간식

    func noticeTreat(in world: Playground) {
        if job != nil { return }   // 일하는 중에는 한눈팔지 않는다
        switch activity {
        case .held, .fall, .chase:
            return
        case .sleep:
            exclaim("!", in: world)
        default:
            break
        }
        startChase(world)
    }

    private func startChase(_ world: Playground) {
        target = world.nearestTreat(to: x)
        if target != nil { activity = .chase }
    }

    private func chase(_ dt: Double, _ world: Playground) {
        guard let treat = target, !treat.eaten else {
            if let next = world.nearestTreat(to: x) {
                target = next
            } else {
                // 다른 Clawd가 먼저 먹어버렸다
                exclaim("?", in: world)
                begin(.idle, for: 0.8...1.5)
                look = 0
                moving = false
            }
            return
        }

        let goal = min(max(treat.x, world.minX), world.maxX)
        let dx = goal - x
        if abs(dx) > 0.5 { facing = dx > 0 ? 1 : -1 }
        look = Int(facing)

        let step = min(abs(dx), 65 * CGFloat(dt))
        x += dx > 0 ? step : -step
        moving = step > 0.01

        let closeEnough = abs(treat.x - x) <= world.spriteWidth / 2 + 2 && abs(dx) < 1
        if closeEnough && treat.y <= y + world.spriteHeight + 2 {
            eat(treat, world)
        } else if closeEnough {
            look = 0   // 떨어지는 간식을 올려다보며 기다린다
        }
    }

    private func eat(_ treat: Treat, _ world: Playground) {
        world.eat(treat)
        treatsEaten += 1
        target = nil
        moving = false
        happyFor = 1.4
        if !isAirborne { vy = world.jumpVelocity(0.8) }
        begin(.cheer, for: 1.0...1.3)
        heart(in: world)
    }

    // MARK: - 터치

    func poke(in world: Playground) {
        switch activity {
        case .held, .fall:
            return
        case .sleep:
            exclaim("!", in: world)
            if !isAirborne { vy = world.jumpVelocity(0.6) }
            begin(.idle, for: 1...1.8)
            look = 0
        case .think, .study, .craft, .exercise, .clock:
            // 일하거나 시계를 들고 있으면 좋아하기만 하고 하던 일은 계속
            happyFor = 1
            heart(in: world)
        case .idea:
            // 아이디어 확인! 보고서를 연다
            if let idea = pitchedIdea { world.ideaTapped(idea) }
            pitchedIdea = nil
            speech = nil
            happyFor = 1.2
            heart(in: world)
            begin(.cheer, for: 0.9...1.2)
        case .announce:
            // 완료 알림 확인!
            world.acknowledge(self)
            donesSeen += 1
            job = nil
            jobKey = ""
            speech = nil
            label = nil
            happyFor = 1.2
            if !isAirborne { vy = world.jumpVelocity(0.95) }
            heart(in: world)
            begin(.cheer, for: 0.9...1.2)
        default:
            happyFor = 1.2
            if !isAirborne { vy = world.jumpVelocity(0.95) }
            heart(in: world)
            if job == nil { begin(.cheer, for: 0.9...1.2) }
        }
    }

    // MARK: - 화면 위 모드에서 사람과 놀기

    private var freeToPlay: Bool { job == nil && [.idle, .rest, .walk, .clock].contains(activity) }
    /// 일하는 중에도 잠깐 고개를 들 수 있는 상태 (자거나, 들려 있거나, 말풍선을 든 중은 제외)
    private var canGreet: Bool { freeToPlay || [.think, .study, .craft, .exercise].contains(activity) }

    /// 가까이 온 마우스를 쳐다본다 (놀고 있을 때만, 걷는 중엔 방향을 바꾸지 않는다)
    func watch(cursorAt dx: CGFloat) {
        guard canGreet, activity != .walk, abs(dx) > 4 else { return }
        look = dx > 0 ? 1 : -1
    }

    /// 오랜만에 마우스가 다가오면 손을 흔든다
    func wave(in world: Playground? = nil) {
        guard canGreet else { return }
        happyFor = 1
        begin(.cheer, for: 0.8...1.1)
        if affectionLevel >= 3, let world, !isAirborne { vy = world.jumpVelocity(0.5) }
    }

    /// 친밀도가 올랐을 때: 말풍선 들고 폴짝폴짝, 하트 뿌리기
    func celebrate(_ title: String, _ text: String, in world: Playground) {
        guard activity != .held, activity != .fall else { return }
        speech = Speech(title: title, text: text)
        happyFor = 3.2
        begin(.cheer, for: 3.0...3.2)
        if !isAirborne { vy = world.jumpVelocity(0.9) }
        for _ in 0..<4 { heart(in: world) }
    }

    /// 들고 세게 흔들면 어지러워한다 (내려놓은 뒤에도 잠깐 비틀거린다)
    func dizzy(in world: Playground) {
        guard dizzyFor <= 0 else { return }
        dizzyFor = 2.8
        dizzyStarIn = 0
        happyFor = 0
        exclaim("@", in: world)
    }

    /// 쓰다듬기: 뛰지 않고 좋아하기만 한다 (자고 있어도 깨우지 않는다)
    func pat(in world: Playground) {
        guard activity != .held, activity != .fall else { return }
        patsReceived += 1
        happyFor = 1.2
        for _ in 0..<(1 + affectionLevel / 2) { heart(in: world) }
    }

    /// 간식을 뺏겼거나 늦었을 때
    func sulk(in world: Playground) {
        guard job == nil, activity != .held, activity != .fall else { return }
        exclaim("…", in: world)
        begin(.rest, for: 2...3)
        look = 0
    }

    func grab(in world: Playground) {
        activity = .held
        target = nil
        vy = 0
        y = world.headroom * 0.6
        look = 0
    }

    func drag(to newX: CGFloat, in world: Playground) {
        x = min(max(newX, world.minX), world.maxX)
    }

    func release(in world: Playground) {
        activity = .fall
        vy = 0
        if y <= 0 { y = 0.1 }
    }

    /// "아이디어 떴다!" 하며 하나 던진다
    func pitch(_ idea: IdeaBox.Idea, in world: Playground) {
        pitchedIdea = idea
        target = nil
        speech = Self.ideaSpeech(idea)
        begin(.idea, for: 45...45)
        attentionIn = 6
        look = 0
        if !isAirborne { vy = world.jumpVelocity(0.9) }
        exclaim("!", in: world)
    }

    /// 정각이 되면 "땡!" 하고 좋아한다
    func chime(in world: Playground) {
        happyFor = 1.5
        world.emit(.text(tr("땡!", "Ding!"), .systemYellow, 10), x: x + facing * (world.spriteWidth / 2 + 8),
                   y: world.spriteHeight - 10, vy: 4, life: 1.6)
        heart(in: world)
    }

    private func exclaim(_ mark: String, in world: Playground) {
        let top = activity == .sleep || activity == .rest ? world.px * 8 : world.spriteHeight
        world.emit(.text(mark, mark == "!" ? .systemYellow : Palette.text, 10),
                   x: x + facing * (world.spriteWidth / 2 + 2), y: top - 6, vy: 5, life: 0.9)
    }

    private func heart(in world: Playground) {
        world.emit(.heart, x: x + facing * (world.spriteWidth / 2 + 4), y: world.spriteHeight - 4,
                   vx: facing * 4, vy: 9, life: 1.1)
    }

    // MARK: - 그리기용 상태

    var frame: ClawdSprite.Frame {
        var f = ClawdSprite.Frame()
        f.look = look
        switch activity {
        case .idle, .hop:
            break
        case .clock:
            // 팻말을 올려다보는 순간
            if lookIn < 0.6 { f.eyes = .up }
        case .rest:
            f.sitting = true
        case .walk:
            f.legs = step(0.16)
        case .run:
            f.legs = step(legPeriod)
        case .chase:
            f.legs = moving ? step(0.08) : .stand
            if !moving { f.eyes = .up }
        case .sleep:
            f.sitting = true
            f.eyes = .closed
        case .cheer, .fall, .announce:
            f.armsUp = true
        case .held:
            f.armsUp = true
            f.legs = step(0.07)
            f.eyes = .happy
        case .think:
            f.eyes = .up
        case .study:
            f.sitting = true
            f.prop = .book(page: Int(activityClock / 1.6))
        case .craft:
            f.sitting = true
            f.prop = .laptop(typing: Int(clock / 0.13))
        case .exercise:
            let up = Int(activityClock / 0.5) % 2 == 1
            f.armsUp = true
            f.prop = .dumbbell(up: up)
            if up { f.eyes = .closed }
        case .call:
            f.armsUp = Int(clock / 0.3) % 2 == 0
        case .idea:
            // 신나서 팔을 번쩍번쩍
            f.armsUp = Int(clock / 0.4) % 2 == 0
            f.eyes = .up
        }
        if isAirborne && activity != .held {
            f.armsUp = true
            if !f.sitting { f.legs = activity == .fall ? .stand : .tucked }
        }
        if showsClock {
            f.armsUp = true
            f.prop = .holdSign
        }
        if dizzyFor > 0 {
            // 빙글빙글: > < 와 감은 눈을 번갈아, 고개도 좌우로
            f.eyes = Int(clock / 0.14) % 2 == 0 ? .frustrated : .closed
            f.look = Int(clock / 0.28) % 2 == 0 ? -1 : 1
            return f
        }
        if yawnFor > 0 {
            f.eyes = .closed
            return f
        }
        if happyFor > 0 || activity == .announce {
            f.eyes = .happy
            return f
        }
        if Self.isNight && (f.eyes == .open || f.eyes == .up) && [.idle, .rest, .walk].contains(activity) { f.eyes = .tired }
        switch mood {
        case .calm:
            break
        case .tired:
            if f.eyes == .open || f.eyes == .up { f.eyes = .tired }
        case .annoyed:
            // 지친 눈이다가 가끔 > < 로 찡그린다
            if f.eyes != .closed { f.eyes = Int(clock / 1.4) % 3 == 0 ? .frustrated : .tired }
        case .furious:
            f.eyes = .frustrated
        }
        if blinkFor > 0 && f.eyes == .open { f.eyes = .blink }
        return f
    }

    /// 일하는 동안 옆에 띄우는 "✻ 작업 중 · 주제 · 3분". 투덜거릴 땐 그 말을 대신 띄운다.
    var thought: Thought? {
        guard let label, activity.isWorking else { return nil }
        let glyph = Self.spinner[Int(clock / 0.12) % Self.spinner.count]
        if grumbleFor > 0, let grumble { return Thought(glyph: glyph, text: grumble, grumpy: true) }
        let minutes = workStart.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
        return Thought(glyph: glyph, text: label + (minutes >= 1 ? tr(" · \(minutes)분", " · \(minutes)m") : ""), grumpy: mood.rawValue >= Mood.annoyed.rawValue)
    }

    /// 확인 요청이나 완료 알림 말풍선, 그리고 말풍선이 떠 있던 시간
    var bubble: (speech: Speech, age: Double)? {
        guard let speech, [.call, .announce, .idea, .cheer].contains(activity) else { return nil }
        return (speech, activityClock)
    }

    private func step(_ period: Double) -> ClawdSprite.Legs {
        Int(clock / period) % 2 == 0 ? .stepA : .stepB
    }
}
