import AppKit
import ImageIO
import UniformTypeIdentifiers

/// `CLAWD_LANG=en ClawdPet --render-gifs docs/en` : README에 넣을 움직이는 GIF를 앱의 실제 그리기 코드로 만든다.
/// `--render-reddit dir` 는 같은 장면을 휴대폰 피드에서 크게 보이는 정사각형(1080×1080)으로, 저장소 주소를 붙여 만든다.
/// 시간표대로 가짜 Claude 이벤트를 넣으며 Clawd 세계를 돌리고, 프레임마다 그린다.
/// GIF는 색이 256개뿐이라 그라데이션·흐린 그림자 없이 단색 스티커 느낌으로 그린다.
enum DocsGif {
    private typealias Art = DocsArt
    /// 한 프레임 길이. GIF 지연 시간은 1/100초 단위라 딱 떨어지게.
    private static let step = 0.06
    /// 정사각형(Reddit 피드용)으로 그리는 중인지
    private static var square = false
    private static let repo = "github.com/suinegyzal/clawd-pet"

    static func write(to path: String, square: Bool = false) {
        self.square = square
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // 정사각형은 피드 미리보기(첫 프레임)가 눈에 띄도록 가장 볼만한 순간부터 시작한다 (초)
        let scenes: [(String, () -> [CGImage], Double)] = [("work", work, 4.5), ("grumpy", grumpy, 5.0), ("play", play, 0), ("menubar", menuBar, 2.0)]
        for (name, scene, highlight) in scenes {
            let url = folder.appendingPathComponent(name + ".gif")
            var frames = scene()
            if square, highlight > 0 {
                let start = Int(highlight / step)
                frames = Array(frames[start...] + frames[..<start])
            }
            save(frames, to: url)
            print("gif → \(url.path) (\(frames.count) frames)")
        }
    }

    private static func save(_ frames: [CGImage], to url: URL) {
        guard let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(file, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: step, kCGImagePropertyGIFUnclampedDelayTime: step]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(file, frame, delay) }
        CGImageDestinationFinalize(file)
    }

    // MARK: - 촬영

    /// 시간표(cues)대로 일을 일으키며 세계를 돌리고, 매 프레임 draw로 그린다
    private static func film(seconds: Double, size: CGSize, worlds: [Playground], cues: [(Double, () -> Void)],
                             everyFrame: (Double) -> Void = { _ in }, draw: (CGContext, Double) -> Void) -> [CGImage] {
        var pending = cues.sorted { $0.0 < $1.0 }
        var frames: [CGImage] = []
        var t = 0.0
        while t < seconds - 1e-6 {
            while let cue = pending.first, cue.0 <= t + 1e-6 {
                pending.removeFirst()
                cue.1()
            }
            everyFrame(t)
            frames.append(Art.canvas(size) { ctx in draw(ctx, t) })
            for _ in 0..<3 { worlds.forEach { $0.update(step / 3) } }
            t += step
        }
        return frames
    }

    // MARK: - 그리기 도구 (단색)

    private static func flat(_ ctx: CGContext, _ size: CGSize, _ color: CGColor, seed: UInt64, avoid: [CGRect]) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(origin: .zero, size: size))
        var random = Art.Seeded(state: seed)
        for i in 0..<22 {
            let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
            if avoid.contains(where: { $0.insetBy(dx: -10, dy: -10).contains(point) }) { continue }
            Art.sparkle(ctx, at: point, unit: [1.5, 2, 2.5][i % 3], color: i % 3 == 0 ? Palette.clawd : CGColor(gray: 1, alpha: 1))
        }
    }

    /// 스티커처럼 아래로 살짝 밀린 단색 그림자가 있는 카드
    private static func sticker(_ ctx: CGContext, _ rect: CGRect, fill: CGColor, shadow: CGColor, radius: CGFloat = 16) {
        ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(shadow)
        ctx.fillPath()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    private static func title(_ lines: [String], in size: CGSize) {
        if square {
            Art.text(lines.joined(separator: "\n"), Art.rounded(38, .heavy), Art.ink, in: CGRect(x: 28, y: size.height - 114, width: size.width - 56, height: 100))
        } else {
            Art.text(lines.joined(separator: " "), Art.rounded(29, .heavy), Art.ink, in: CGRect(x: 28, y: size.height - 56, width: size.width - 56, height: 40))
        }
    }

    /// 정사각형 아래에 붙는 저장소 주소
    private static func footer(in size: CGSize) {
        guard square else { return }
        Art.text("✻ " + repo, Art.rounded(15, .bold), Art.soft, in: CGRect(x: 0, y: 14, width: size.width, height: 22), align: .center)
    }

    private static func pillWidth(_ string: String) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: Art.rounded(17, .bold)]).size().width + 28
    }

    /// 손가락으로 톡: 점 하나와 퍼지는 고리
    private static func tap(_ ctx: CGContext, at point: CGPoint, age: Double) {
        guard age >= 0, age < 0.6 else { return }
        let ring = 8 + CGFloat(age) * 46
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1 - age / 0.6))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2))
        if age < 0.25 {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
        }
    }

    /// 화살표 마우스 포인터
    private static func pointer(_ ctx: CGContext, at tip: CGPoint, pressed: Bool) {
        let shape: [(CGFloat, CGFloat)] = [(0, 0), (0, -17), (4, -13), (7, -20), (10, -19), (7, -12), (12, -12)]
        let scale: CGFloat = pressed ? 0.9 : 1
        let path = CGMutablePath()
        path.addLines(between: shape.map { CGPoint(x: tip.x + $0.0 * scale, y: tip.y + $0.1 * scale) })
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(1.5)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
    }

    private static func lerp(_ keys: [(Double, Double)], at t: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(keys, keys.dropFirst()) where t <= b.0 {
            return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    /// 시간표에서 지금 해당하는 칸
    private static func phase<T>(_ list: [(Double, T)], at t: Double) -> T {
        list.last { $0.0 <= t + 1e-6 }?.1 ?? list[0].1
    }

    // MARK: - 장면 1: Claude가 일하면 Clawd도 일한다

    private static func work() -> [CGImage] {
        let size = square ? CGSize(width: 540, height: 540) : CGSize(width: 640, height: 330)
        let bg = Art.rgb(255, 226, 210), shade = Art.rgb(240, 196, 176)
        let (world, link) = Art.makeWorld(width: square ? 236 : 284)
        let pet = Art.place(world, at: square ? 30 : 46)
        Art.run(world, 1.0)
        // 정사각형은 띠가 좁아서, 이름표가 오른쪽에 들어가도록 왼쪽에 머문다 (대신 한 번 폴짝)
        if square { pet.start(.idle, seconds: 100) }

        let prompt = tr("로그인 버그 고쳐 줘", "fix the login bug")
        let session = "w"
        func event(_ name: String, _ extra: [String: Any] = [:]) {
            link.handle(["session_id": session, "hook_event_name": name].merging(extra) { $1 })
        }
        let lines: [(Double, String, NSColor)] = [
            (0.4, "> " + prompt, .white),
            (1.6, "✻ Thinking…", Art.orange),
            (2.8, "● Read(src/auth.ts)", .systemGreen),
            (4.2, "● Bash(npm test)", .systemGreen),
            (5.6, "● Update(src/auth.ts)", .systemGreen),
            (7.0, "✻ " + tr("완료: 버그 고치고 테스트 3개 추가", "Done: fixed it, added 3 tests"), Art.orange),
        ]
        let states: [(Double, String, String)] = [
            (0, tr("Claude가 쉬는 동안", "While Claude is idle"), tr("놀아요", "Clawd plays")),
            (1.6, tr("Claude가 요청을 받으면", "Claude gets your request"), tr("생각해요", "Clawd thinks")),
            (2.8, tr("Claude가 파일을 읽으면", "Claude reads files"), tr("공부해요", "Clawd studies")),
            (4.2, tr("Claude가 명령을 실행하면", "Claude runs commands"), tr("운동해요", "Clawd works out")),
            (5.6, tr("Claude가 코드를 고치면", "Claude edits code"), tr("타자를 쳐요", "Clawd types")),
            (7.0, tr("Claude가 일을 끝내면", "Claude finishes"), tr("완료! 하고 알려요", "Clawd: Done!")),
            (8.5, tr("말풍선을 톡 치면", "You tap the bubble"), tr("하트를 보내요 ♥", "Clawd sends ♥")),
        ]
        let tapAt = 8.5
        let stripOrigin = square ? CGPoint(x: 34, y: 62) : CGPoint(x: 36, y: 30)
        var tapPoint = CGPoint.zero

        return film(seconds: 10.2, size: size, worlds: [world], cues: [
            (0.4, { if square { pet.poke(in: world) } }),
            (1.6, { event("UserPromptSubmit", ["prompt": prompt]) }),
            (2.8, { event("PreToolUse", ["tool_name": "Read"]) }),
            (4.2, { event("PreToolUse", ["tool_name": "Bash"]) }),
            (5.6, { event("PreToolUse", ["tool_name": "Edit"]) }),
            (7.0, { event("Stop", ["last_assistant_message": tr("로그인 버그 고쳤어요!", "Fixed the login bug!")]) }),
            (tapAt, {
                tapPoint = CGPoint(x: stripOrigin.x + pet.x * 2, y: stripOrigin.y + 24)
                pet.poke(in: world)
            }),
        ]) { ctx, t in
            let terminal = square ? CGRect(x: 28, y: 236, width: 484, height: 172) : CGRect(x: 28, y: 118, width: 330, height: 150)
            flat(ctx, size, bg, seed: 3, avoid: [CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 30)])
            title([tr("Claude가 일하면,", "When Claude works,"), tr("Clawd도 일해요", "Clawd works")], in: size)
            footer(in: size)

            // 터미널 흉내
            sticker(ctx, terminal, fill: Art.rgb(38, 34, 32), shadow: shade, radius: 14)
            for (i, color) in [Art.rgb(255, 95, 87), Art.rgb(254, 188, 46), Art.rgb(40, 200, 64)].enumerated() {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: terminal.minX + 14 + CGFloat(i) * 16, y: terminal.maxY - 20, width: 9, height: 9))
            }
            let mono = NSFont.monospacedSystemFont(ofSize: square ? 15 : 12.5, weight: .medium)
            let lineHeight: CGFloat = square ? 21 : 18.5
            for (i, line) in lines.enumerated() where t >= line.0 {
                var string = line.1
                if i == 0 {   // 요청은 한 글자씩 친다
                    let typed = Int((t - line.0) / 0.05)
                    string = String(string.prefix(typed))
                }
                Art.text(string, mono, line.2, in: CGRect(x: terminal.minX + 16, y: terminal.maxY - 30 - lineHeight - CGFloat(i) * lineHeight,
                                                          width: terminal.width - 28, height: lineHeight))
            }

            // 오른쪽: 지금 무슨 일이 일어나는지
            let state = phase(states.map { ($0.0, ($0.1, $0.2)) }, at: t)
            if square {
                Art.text(state.0, Art.rounded(20, .bold), Art.soft, in: CGRect(x: 28, y: 194, width: 484, height: 28))
                Art.text("→", Art.rounded(30, .heavy), Art.orange, in: CGRect(x: 28, y: 146, width: 40, height: 42))
                Art.text(state.1, Art.rounded(30, .heavy), Art.ink, in: CGRect(x: 66, y: 146, width: 446, height: 42))
            } else {
                Art.text(state.0, Art.rounded(17, .bold), Art.soft, in: CGRect(x: 384, y: 200, width: 240, height: 24))
                Art.text("→", Art.rounded(24, .heavy), Art.orange, in: CGRect(x: 384, y: 156, width: 32, height: 34))
                Art.text(state.1, Art.rounded(24, .heavy), Art.ink, in: CGRect(x: 414, y: 156, width: 220, height: 34))
            }

            Art.draw(world, in: ctx, at: stripOrigin, zoom: 2)
            tap(ctx, at: tapPoint, age: t - tapAt)
        }
    }

    // MARK: - 장면 2: 오래 걸리면 짜증

    private static func grumpy() -> [CGImage] {
        let size = square ? CGSize(width: 540, height: 540) : CGSize(width: 640, height: 300)
        let bg = Art.rgb(255, 241, 199), shade = Art.rgb(236, 214, 150)
        let (world, link) = Art.makeWorld(width: square ? 236 : 284)
        _ = Art.place(world, at: 40)
        Art.run(world, 1.0)

        let prompt = tr("v2 배포", "ship v2")
        // 영상 시간(초) → 요청한 지 몇 분
        let clock: [(Double, Double)] = [(0, 0.2), (1.2, 1.0), (2.4, 3.2), (3.6, 6.4), (4.8, 10.6), (6.8, 12.8)]
        let doneAt = 7.2
        let stages: [(String, CGColor)] = [
            (tr("집중", "Focused"), Art.rgb(150, 220, 170)), (tr("지침", "Tired"), Art.rgb(250, 214, 110)),
            (tr("짜증", "Annoyed"), Art.rgb(250, 160, 100)), (tr("폭발 직전", "Furious"), Art.rgb(240, 90, 80)),
        ]
        var minutes = 0.0
        var finished = false

        return film(seconds: 9.0, size: size, worlds: [world], cues: [
            (doneAt, { finished = true; link.handle(["session_id": "g", "hook_event_name": "Stop", "last_assistant_message": tr("드디어 v2 배포 끝!", "Finally shipped v2!")]) }),
        ], everyFrame: { t in
            guard !finished else { return }
            minutes = lerp(clock, at: t)
            let start = Date().addingTimeInterval(-minutes * 60)
            link.handle(["session_id": "g", "hook_event_name": "UserPromptSubmit", "prompt": prompt], at: start)
            link.handle(["session_id": "g", "hook_event_name": "PreToolUse", "tool_name": "Bash"], at: start)
        }) { ctx, t in
            let timer = square ? CGRect(x: 120, y: 236, width: 300, height: 136) : CGRect(x: 440, y: 118, width: 172, height: 102)
            flat(ctx, size, bg, seed: 5, avoid: [CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 30)])
            title([tr("오래 걸리면", "Long task?"), tr("Clawd가 짜증 내요", "Clawd gets grumpy")], in: size)
            footer(in: size)
            if square {
                Art.text(tr("땀 → 김 → 빨개져서 발 구르기", "Sweat → steam → red-faced stomping"),
                         Art.rounded(19, .semibold), Art.soft, in: CGRect(x: 28, y: size.height - 148, width: 484, height: 28))
            } else {
                Art.text(tr("요청한 지 오래될수록 땀 → 김 → 빨개지고 발을 굴러요", "The longer Claude takes: sweat → steam → red, stomping fury"),
                         Art.rounded(15, .semibold), Art.soft, in: CGRect(x: 28, y: size.height - 82, width: 580, height: 22))
            }

            // 기분 단계와 게이지
            let done = finished
            let stage = minutes < 2 ? 0 : minutes < 5 ? 1 : minutes < 10 ? 2 : 3
            let label = done ? tr("드디어 끝! ♥", "Finally done! ♥") : stages[stage].0
            let pillAt = square ? CGPoint(x: (size.width - pillWidth(label)) / 2, y: 184) : CGPoint(x: 28, y: 172)
            _ = Art.pill(label, at: pillAt, fill: done ? Art.rgb(150, 220, 170) : stages[stage].1)
            let cellWidth: CGFloat = square ? 113.5 : 88, gap: CGFloat = square ? 10 : 8
            for (i, item) in stages.enumerated() {
                let cell = CGRect(x: 28 + CGFloat(i) * (cellWidth + gap), y: square ? 150 : 138, width: cellWidth, height: square ? 16 : 14)
                ctx.addPath(CGPath(roundedRect: cell, cornerWidth: 7, cornerHeight: 7, transform: nil))
                ctx.setFillColor(i <= stage && !done ? item.1 : shade)
                ctx.fillPath()
            }

            // 시계
            sticker(ctx, timer, fill: CGColor(gray: 1, alpha: 1), shadow: shade)
            let shown = Int(minutes * 60)
            let digits = NSFont.monospacedDigitSystemFont(ofSize: square ? 70 : 44, weight: .heavy)
            Art.text(String(format: "%d:%02d", shown / 60, shown % 60), digits, stage == 3 && !done ? .systemRed : Art.ink,
                     in: CGRect(x: timer.minX, y: timer.minY + (square ? 42 : 36), width: timer.width, height: square ? 84 : 54), align: .center)
            Art.text(tr("요청한 지", "since your request"), Art.rounded(square ? 16 : 13, .semibold), Art.soft,
                     in: CGRect(x: timer.minX, y: timer.minY + (square ? 18 : 14), width: timer.width, height: 22), align: .center)

            Art.draw(world, in: ctx, at: square ? CGPoint(x: 34, y: 62) : CGPoint(x: 36, y: 30), zoom: 2)
        }
    }

    // MARK: - 장면 3: 쉴 때 놀기

    private static func play() -> [CGImage] {
        let size = square ? CGSize(width: 540, height: 540) : CGSize(width: 640, height: 300)
        let bg = Art.rgb(214, 232, 255), shade = Art.rgb(176, 204, 240)
        let zoom: CGFloat = square ? 2.6 : 2
        let (world, _) = Art.makeWorld(width: square ? 182 : 284)
        let keeper = Art.place(world, at: square ? 26 : 34)
        let walker = Art.place(world, at: square ? 92 : 140, facing: -1)
        let sleeper = Art.place(world, at: square ? 158 : 250, facing: -1)
        Art.run(world, 1.2)
        sleeper.start(.sleep, seconds: 100)
        walker.start(square ? .idle : .walk, seconds: 2)

        let stripOrigin = square ? CGPoint(x: 33, y: 104) : CGPoint(x: 36, y: 30)
        let treatX: CGFloat = square ? 124 : 196
        let treatAt = 4.4
        let pats = 7.6
        var patPoint = CGPoint.zero
        let tips: [(Double, Int)] = [(0, 0), (2.4, 1), (treatAt, 2), (pats, 3)]
        let names = [tr("시계 당번", "Clock duty"), tr("낮잠", "Naps"), tr("간식 쟁탈전", "Treat race"), tr("쓰다듬기", "Pats")]

        return film(seconds: 10.0, size: size, worlds: [world], cues: [
            (1.0, { keeper.chime(in: world) }),
            (treatAt, { _ = world.dropTreat(at: treatX) }),
            (pats, {
                // 시계 든 Clawd와 겹치지 않게, 가장 멀리 있는 Clawd를 쓰다듬는다
                let keeperX = world.pets.first { $0.showsClock }?.x ?? 0
                let pet = world.pets.filter { !$0.showsClock }.max { abs($0.x - keeperX) < abs($1.x - keeperX) } ?? walker
                patPoint = CGPoint(x: stripOrigin.x + pet.x * zoom, y: stripOrigin.y + 12 * zoom)
                pet.poke(in: world)
            }),
        ]) { ctx, t in
            flat(ctx, size, bg, seed: 9, avoid: [CGRect(x: 20, y: 20, width: size.width - 40, height: size.height - 30)])
            title([tr("Claude가 쉬면,", "When Claude rests,"), tr("Clawd는 놀아요", "Clawd plays")], in: size)
            footer(in: size)
            let about = square
                ? tr("시계를 들고, 낮잠 자고, 간식을 쫓아요.\nTouch Bar 빈 곳을 톡 치면 간식이 떨어져요.", "It holds the clock, naps and races for treats.\nTap an empty spot to drop a treat.")
                : tr("시계를 들고, 낮잠 자고, 간식을 쫓아요. Touch Bar 빈 곳을 톡 치면 간식이 떨어져요.", "It holds the clock, naps and races for treats. Tap an empty spot to drop a treat.")
            Art.text(about, Art.rounded(square ? 18 : 15, .semibold), Art.soft,
                     in: square ? CGRect(x: 28, y: 340, width: 484, height: 56) : CGRect(x: 28, y: size.height - 82, width: 590, height: 22))

            let current = phase(tips, at: t)
            var x: CGFloat = square ? (size.width - names.map(pillWidth).reduce(0, +) - CGFloat(names.count - 1) * 10) / 2 : 28
            for (i, name) in names.enumerated() {
                x += Art.pill(name, at: CGPoint(x: x, y: square ? 264 : 150), fill: i == current ? CGColor(gray: 1, alpha: 1) : shade) + 10
            }

            Art.draw(world, in: ctx, at: stripOrigin, zoom: zoom)
            tap(ctx, at: CGPoint(x: stripOrigin.x + treatX * zoom, y: stripOrigin.y + 15 * zoom), age: t - treatAt)
            tap(ctx, at: patPoint, age: t - pats)
        }
    }

    // MARK: - 장면 4: 메뉴 막대

    private static func menuBar() -> [CGImage] {
        let size = square ? CGSize(width: 540, height: 540) : CGSize(width: 640, height: 260)
        let bg = Art.rgb(232, 224, 255), shade = Art.rgb(200, 186, 240)
        let k: CGFloat = square ? 1.6 : 1.3
        let screen = square ? CGRect(x: 24, y: 60, width: 492, height: 262) : CGRect(x: 28, y: 24, width: 584, height: 212)
        let bar = CGRect(x: screen.minX, y: screen.maxY - 24 * k, width: screen.width, height: 24 * k)
        let menuFont = NSFont.systemFont(ofSize: 13 * k, weight: .medium)
        let left = square ? "  Finder   File" : "  Finder   File   Edit"
        let leftWidth = NSAttributedString(string: left, attributes: [.font: menuFont]).size().width + 18
        let clockText = square ? "9:41" : "Tue 9:41"
        let rightWidth = NSAttributedString(string: clockText, attributes: [.font: menuFont]).size().width + 24
        let runners = RunnerClock.menuBarImages(px: 1.5 * k)
        // 정사각형은 자리가 좁아서 메뉴 막대 아이콘(달리는 Clawd)을 뺀다
        let free = CGRect(x: bar.minX + leftWidth + 10, y: bar.minY, width: bar.width - leftWidth - rightWidth - (square ? 24 : 70), height: bar.height)

        let (world, link) = Art.makeWorld(width: free.width / k, height: 24, px: 1.5, transparent: true)
        let pet = Art.place(world, at: square ? 12 : 30)
        Art.run(world, 1.0)
        // 좁은 정사각형에선 말풍선이 오른쪽에 들어가도록 일이 끝날 때까지 왼쪽에 서 있게 한다
        if square { pet.start(.idle, seconds: 100) }
        let prompt = tr("오타 고쳐 줘", "fix typo")
        let clickAt = 6.6
        let home = square ? CGPoint(x: screen.midX + 90, y: screen.minY + 90) : CGPoint(x: screen.midX + 120, y: screen.minY + 40)
        var cursor = home

        return film(seconds: 9.0, size: size, worlds: [world], cues: [
            (1.4, {
                link.handle(["session_id": "m", "hook_event_name": "UserPromptSubmit", "prompt": prompt])
                link.handle(["session_id": "m", "hook_event_name": "PreToolUse", "tool_name": "Edit"])
            }),
            (4.2, { link.handle(["session_id": "m", "hook_event_name": "Stop", "last_assistant_message": square ? tr("오타 고쳤어요!", "Typo fixed!") : tr("오타 고쳤어요.", "Fixed the typo.")]) }),
            (clickAt, { pet.poke(in: world) }),
        ], everyFrame: { t in
            // 완료 알림이 뜨면 포인터가 Clawd에게 다가가 누른다
            let target = CGPoint(x: free.minX + pet.x * k + 4, y: bar.midY - 4)
            let p = min(max((t - 5.2) / 1.3, 0), 1), back = min(max((t - 7.4) / 1.2, 0), 1)
            let ease = { (v: Double) in CGFloat(v * v * (3 - 2 * v)) }
            let go = ease(p) - ease(back)
            cursor = CGPoint(x: home.x + (target.x - home.x) * go, y: home.y + (target.y - home.y) * go)
        }) { ctx, t in
            flat(ctx, size, bg, seed: 13, avoid: [screen.insetBy(dx: 0, dy: -8)] + (square ? [CGRect(x: 20, y: 330, width: 500, height: 200)] : []))
            footer(in: size)
            sticker(ctx, screen, fill: Art.rgb(150, 120, 230), shadow: shade, radius: 18)

            // 메뉴 막대
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.clip()
            ctx.setFillColor(Art.rgb(243, 238, 255))
            ctx.fill(bar)
            ctx.restoreGState()
            let menus = NSMutableAttributedString(string: left, attributes: [.font: menuFont, .foregroundColor: NSColor.black])
            menus.addAttribute(.font, value: NSFont.systemFont(ofSize: 13 * k, weight: .bold), range: (left as NSString).range(of: "Finder"))
            menus.draw(with: CGRect(x: bar.minX + 8, y: bar.minY + 7, width: leftWidth, height: 30), options: [.usesLineFragmentOrigin])
            Art.text(clockText, menuFont, .black, in: CGRect(x: bar.maxX - rightWidth - 10, y: bar.minY + 7, width: rightWidth, height: 30), align: .right)
            let runner = runners[Int(t / 0.12) % runners.count]
            if !square { runner.draw(in: CGRect(x: bar.maxX - rightWidth - 46, y: bar.minY + (bar.height - runner.size.height) / 2,
                                   width: runner.size.width, height: runner.size.height)) }
            Art.draw(world, in: ctx, at: free.origin, zoom: k, frame: false)

            // 바탕화면 글씨
            if square {
                title([tr("Touch Bar가 없어도", "No Touch Bar?"), tr("괜찮아요", "No problem.")], in: size)
                Art.text(tr("Clawd가 메뉴 막대를 돌아다니며\nClaude를 똑같이 따라 해요.", "Clawd roams your menu bar\nand follows Claude just the same."),
                         Art.rounded(19, .semibold), Art.soft, in: CGRect(x: 28, y: 344, width: 484, height: 56))
            } else {
                Art.text(tr("Touch Bar가 없어도 괜찮아요", "No Touch Bar? No problem."), Art.rounded(30, .heavy), .white,
                         in: CGRect(x: screen.minX, y: screen.minY + 74, width: screen.width, height: 40), align: .center)
                Art.text(tr("메뉴 막대를 돌아다니며 Claude를 똑같이 따라 해요", "Clawd roams your menu bar and follows Claude just the same."),
                         Art.rounded(16, .semibold), CGColor(gray: 1, alpha: 0.85).nsColor,
                         in: CGRect(x: screen.minX, y: screen.minY + 46, width: screen.width, height: 24), align: .center)
            }

            pointer(ctx, at: cursor, pressed: abs(t - clickAt) < 0.15)
        }
    }
}

private extension CGColor {
    var nsColor: NSColor { NSColor(cgColor: self) ?? .white }
}
