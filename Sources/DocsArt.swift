import AppKit

/// `CLAWD_LANG=en ClawdPet --render-docs docs/en` : README에 넣을 귀여운 소개 이미지를 앱의 실제 그리기 코드로 만든다.
/// 장면은 Clawd 세계를 직접 꾸며서(가짜 Claude 이벤트, 간식, 시계…) 렌더링하고, 파스텔 카드로 감싼다.
enum DocsArt {
    // MARK: - 색과 글꼴

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
    static let peach = rgb(255, 226, 210), lavender = rgb(232, 224, 255), mint = rgb(214, 243, 230)
    static let sky = rgb(214, 232, 255), butter = rgb(255, 241, 199), blush = rgb(255, 214, 224)
    static let ink = NSColor(srgbRed: 0.24, green: 0.17, blue: 0.15, alpha: 1)
    static let soft = NSColor(srgbRed: 0.47, green: 0.39, blue: 0.36, alpha: 1)
    static let orange = NSColor(cgColor: Palette.clawd)!

    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    }

    // MARK: - 시작

    static func write(to path: String) {
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let images: [(String, CGImage)] = [
            ("hero", hero()), ("work", work()), ("mood", mood()),
            ("done", done()), ("play", play()), ("places", places()),
        ]
        for (name, image) in images {
            let url = folder.appendingPathComponent(name + ".png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            print("docs → \(url.path)")
        }
    }

    // MARK: - 그리기 도구

    /// 포인트 단위로 그리고 2배 해상도로 내보낸다. 좌표는 왼쪽 아래가 원점.
    static func canvas(_ size: CGSize, scale: CGFloat = 2, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .none
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(ctx)
        return ctx.makeImage()!
    }

    /// 매번 같은 그림이 나오게 하는 작은 난수
    struct Seeded {
        var state: UInt64
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
        }
    }

    static func background(_ ctx: CGContext, _ size: CGSize, _ colors: [CGColor], seed: UInt64, avoid: [CGRect] = []) {
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        var random = Seeded(state: seed)
        for i in 0..<34 {
            let point = CGPoint(x: random.next() * size.width, y: random.next() * size.height)
            if avoid.contains(where: { $0.insetBy(dx: -12, dy: -12).contains(point) }) { continue }
            let color = i % 4 == 0 ? Palette.clawd.copy(alpha: 0.35)! : CGColor(gray: 1, alpha: 0.85)
            sparkle(ctx, at: point, unit: [1.5, 2, 2.5][i % 3], color: color)
        }
    }

    /// 픽셀 반짝이 ✦
    static func sparkle(_ ctx: CGContext, at center: CGPoint, unit: CGFloat, color: CGColor) {
        let cells = [(2, 0), (2, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (2, 3), (2, 4)]
        ctx.setFillColor(color)
        ctx.fill(cells.map { CGRect(x: center.x + CGFloat($0.0 - 2) * unit, y: center.y + CGFloat($0.1 - 2) * unit, width: unit, height: unit) })
    }

    static func card(_ ctx: CGContext, _ rect: CGRect, fill: CGColor = CGColor(gray: 1, alpha: 0.92), radius: CGFloat = 26) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: rgb(120, 80, 60, 0.18))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func text(_ string: String, _ font: NSFont, _ color: NSColor, in rect: CGRect, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineSpacing = font.pointSize * 0.15
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            .draw(with: rect, options: [.usesLineFragmentOrigin])
    }

    /// 제목 + 한 줄 설명 (카드 위쪽)
    static func heading(_ title: String, _ subtitle: String, in size: CGSize) {
        text(title, rounded(40, .heavy), ink, in: CGRect(x: 60, y: size.height - 92, width: size.width - 120, height: 54))
        text(subtitle, rounded(20, .medium), soft, in: CGRect(x: 60, y: size.height - 128, width: size.width - 120, height: 30))
    }

    /// 알약 모양 이름표
    static func pill(_ string: String, at origin: CGPoint, fill: CGColor) -> CGFloat {
        let font = rounded(17, .bold)
        let width = NSAttributedString(string: string, attributes: [.font: font]).size().width + 28
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.addPath(CGPath(roundedRect: CGRect(x: origin.x, y: origin.y, width: width, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
        ctx.setFillColor(fill)
        ctx.fillPath()
        text(string, font, ink, in: CGRect(x: origin.x, y: origin.y + 6, width: width, height: 24), align: .center)
        return width
    }

    // MARK: - Clawd 세계 꾸미기

    static func makeWorld(width: CGFloat, height: CGFloat = 30, px: CGFloat = 2, transparent: Bool = false) -> (Playground, ClaudeLink) {
        let world = Playground()
        world.width = width
        world.height = height
        world.px = px
        world.transparent = transparent
        let link = ClaudeLink(directory: URL(fileURLWithPath: "/nonexistent-clawd-docs"))
        world.link = link
        return (world, link)
    }

    static func run(_ world: Playground, _ seconds: Double) {
        for _ in 0..<Int(seconds * 60) { world.update(1.0 / 60.0) }
    }

    /// 놀고 있는 Clawd 하나를 그 자리에 세워 둔다
    static func place(_ world: Playground, at x: CGFloat, facing: CGFloat = 1) -> Clawd {
        world.addPet(at: x)
        let pet = world.pets[world.pets.count - 1]
        pet.facing = facing
        return pet
    }

    /// Claude 세션 하나가 일하는 중인 것처럼 꾸민다
    static func work(_ link: ClaudeLink, _ id: String, _ prompt: String, tool: String, minutesAgo: Double = 0.3) {
        link.handle(["session_id": id, "hook_event_name": "UserPromptSubmit", "prompt": prompt],
                    at: Date().addingTimeInterval(-minutesAgo * 60))
        link.handle(["session_id": id, "hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": [:]])
    }

    /// 세계를 k배로 키워서 (x, y)에 그린다. 투명하지 않으면 Touch Bar처럼 검은 띠가 깔린다.
    static func draw(_ world: Playground, in ctx: CGContext, at origin: CGPoint, zoom k: CGFloat, frame: Bool = true) {
        let size = CGSize(width: world.width, height: world.height)
        let rect = CGRect(origin: origin, size: CGSize(width: size.width * k, height: size.height * k))
        if frame && !world.transparent {
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -8, dy: -8), cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
        }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.scaleBy(x: k, y: k)
        ctx.clip(to: CGRect(origin: .zero, size: size))
        Renderer.draw(world, in: ctx, size: size, scale: 2)
        ctx.restoreGState()
    }

    // MARK: - 장면들

    /// 대표 이미지: 큰 Clawd, 이름, 한 줄 소개, Touch Bar 띠
    private static func hero() -> CGImage {
        let size = CGSize(width: 1200, height: 620)
        return canvas(size) { ctx in
            background(ctx, size, [peach, lavender, sky], seed: 7, avoid: [CGRect(x: 60, y: 250, width: 720, height: 310), CGRect(x: 100, y: 30, width: 1000, height: 160)])

            text("Clawd Pet", rounded(88, .heavy), ink, in: CGRect(x: 70, y: 440, width: 700, height: 110))
            text("A tiny pixel buddy for Claude Code.\nIt lives in your Mac's menu bar & Touch Bar,\nplays when Claude rests, and works when Claude works.",
                 rounded(25, .medium), soft, in: CGRect(x: 72, y: 318, width: 700, height: 120))
            var x: CGFloat = 72
            for (label, color) in [("macOS 12+", butter), ("Claude Code", blush), ("Free & open source", mint)] {
                x += pill(label, at: CGPoint(x: x, y: 262), fill: color) + 10
            }

            // 큰 Clawd: 두 팔 번쩍, 웃는 눈
            var big = ClawdSprite.Frame()
            big.armsUp = true
            big.eyes = .happy
            ClawdSprite.draw(big, in: ctx, centerX: 965, bottom: 300, px: 13)
            PixelArt.draw(PixelArt.heart, size: (5, 4), in: ctx, centerX: 1100, centerY: 470, px: 7, color: Palette.heart)
            PixelArt.draw(PixelArt.heart, size: (5, 4), in: ctx, centerX: 845, centerY: 505, px: 5, color: Palette.heart)
            PixelArt.draw(PixelArt.spark, size: (7, 7), in: ctx, centerX: 1080, centerY: 560, px: 5, color: Palette.treat)

            // Touch Bar 띠: 일하는 Clawd, 시계 담당, 완료 알림
            let (world, link) = makeWorld(width: 640)
            _ = place(world, at: 36)                     // 완료 알림
            _ = place(world, at: 300)                    // 일하는 중
            let keeper = place(world, at: 600, facing: -1)
            run(world, 1.5)
            link.handle(["session_id": "d", "hook_event_name": "Stop", "last_assistant_message": "Added dark mode to settings."])
            work(link, "w", "Fix the login bug", tool: "Edit", minutesAgo: 1.5)
            run(world, 0.6)
            keeper.start(.clock, seconds: 100)
            run(world, 1.2)
            draw(world, in: ctx, at: CGPoint(x: 120, y: 90), zoom: 1.5)
            text("↑ your Touch Bar (or menu bar) on a normal day", rounded(17, .semibold), soft,
                 in: CGRect(x: 120, y: 40, width: 960, height: 24), align: .center)
        }
    }

    /// Claude가 일하면 Clawd도 일한다: 공부·운동·작업
    private static func work() -> CGImage {
        let size = CGSize(width: 1200, height: 640)
        return canvas(size) { ctx in
            background(ctx, size, [mint, sky], seed: 11)
            card(ctx, CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
            heading("When Claude works, Clawd works ✻", "Clawd mirrors what Claude Code is doing, with the task's topic and how long it's been.", in: size)

            let rows: [(String, String, String)] = [
                ("📖  Reading & searching  →  studying", "Read", "Read the API docs"),
                ("🏋️  Running commands  →  working out", "Bash", "Run the test suite"),
                ("💻  Editing code  →  typing away", "Edit", "Fix the login bug"),
            ]
            for (i, row) in rows.enumerated() {
                let y = size.height - 262 - CGFloat(i) * 128
                text(row.0, rounded(21, .bold), ink, in: CGRect(x: 80, y: y + 74, width: 900, height: 30))
                let (world, link) = makeWorld(width: 500)
                _ = place(world, at: 40)
                run(world, 1.5)
                work(link, "s\(i)", row.2, tool: row.1, minutesAgo: 1.2)
                run(world, 0.9 + Double(i) * 0.2)
                draw(world, in: ctx, at: CGPoint(x: 90, y: y), zoom: 2)
            }
        }
    }

    /// 오래 걸릴수록 표정이 나빠진다
    private static func mood() -> CGImage {
        let size = CGSize(width: 1200, height: 560)
        return canvas(size) { ctx in
            background(ctx, size, [butter, peach], seed: 23)
            card(ctx, CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
            heading("Long task? Clawd gets grumpy 😤", "The longer Claude takes, the sweatier, redder and grumpier Clawd gets.", in: size)

            let stages: [(String, Double)] = [("0–2 min · focused", 0.5), ("2–5 min · tired", 3), ("5–10 min · annoyed", 7), ("10+ min · furious", 12)]
            for (i, stage) in stages.enumerated() {
                let column = CGFloat(i % 2), row = CGFloat(i / 2)
                let origin = CGPoint(x: 90 + column * 540, y: 270 - row * 160)
                text(stage.0, rounded(20, .bold), ink, in: CGRect(x: origin.x, y: origin.y + 74, width: 480, height: 28))
                let (world, link) = makeWorld(width: 230)
                _ = place(world, at: 26)
                run(world, 1.5)
                work(link, "m\(i)", "Ship v2", tool: i % 2 == 0 ? "Edit" : "Bash", minutesAgo: stage.1)
                run(world, 1.0 + Double(i) * 0.35)
                draw(world, in: ctx, at: origin, zoom: 2)
            }
        }
    }

    /// 완료·확인 말풍선, 그리고 💡 아이디어
    private static func done() -> CGImage {
        let size = CGSize(width: 1200, height: 560)
        return canvas(size) { ctx in
            background(ctx, size, [blush, lavender], seed: 31)
            card(ctx, CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
            heading("Done! …and it waits until you check", "Clawd holds up what Claude finished (until you click it), asks before risky commands, and pitches ideas.", in: size)

            text("✅  When a task finishes — click Clawd to jump back to that session", rounded(19, .bold), ink, in: CGRect(x: 80, y: 380, width: 1040, height: 28))
            let (world, link) = makeWorld(width: 500)
            _ = place(world, at: 40)
            run(world, 1.5)
            link.handle(["session_id": "d", "hook_event_name": "Stop", "last_assistant_message": "Fixed the login bug and added 3 tests."])
            run(world, 1.2)
            draw(world, in: ctx, at: CGPoint(x: 90, y: 302), zoom: 2)

            text("✋  Before a command that needs your OK", rounded(19, .bold), ink, in: CGRect(x: 80, y: 240, width: 520, height: 28))
            let (ask, askLink) = makeWorld(width: 245)
            _ = place(ask, at: 26)
            run(ask, 1.5)
            askLink.handle(["session_id": "a", "hook_event_name": "Notification", "message": "Claude needs your permission to use Bash"])
            run(ask, 1.0)
            draw(ask, in: ctx, at: CGPoint(x: 90, y: 162), zoom: 2)

            text("💡  Ideas from your own research routine", rounded(19, .bold), ink, in: CGRect(x: 620, y: 240, width: 520, height: 28))
            let (idea, _) = makeWorld(width: 245)
            let pitcher = place(idea, at: 26)
            run(idea, 1.5)
            pitcher.pitch(IdeaBox.Idea(id: "docs", topic: "Blog", title: "‘Remote day’ vlog",
                                       detail: "", report: nil, created: nil), in: idea)
            run(idea, 1.4)
            draw(idea, in: ctx, at: CGPoint(x: 630, y: 162), zoom: 2)

            text("Click Clawd (or tap it on the Touch Bar) to mark it read — notices survive restarts.",
                 rounded(16, .medium), soft, in: CGRect(x: 80, y: 70, width: 1040, height: 24))
        }
    }

    /// 쉴 때: 시계, 간식, 낮잠, RunCat처럼 달리기
    private static func play() -> CGImage {
        let size = CGSize(width: 1200, height: 560)
        return canvas(size) { ctx in
            background(ctx, size, [sky, lavender, blush], seed: 47)
            card(ctx, CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
            heading("Playtime when Claude rests", "Pet it, feed it, let it nap — and watch it sprint when your Mac gets busy.", in: size)

            let scenes: [(String, (Playground) -> Void)] = [
                ("🕐  One Clawd always holds the clock", { world in
                    let keeper = place(world, at: 40)
                    _ = place(world, at: 180, facing: -1)
                    run(world, 1.5)
                    keeper.start(.clock, seconds: 100)
                    world.pets[1].start(.idle, seconds: 100)
                    run(world, 0.8)
                }),
                ("✻  Drop a treat and it runs to eat it", { world in
                    _ = place(world, at: 40)
                    run(world, 1.5)
                    world.dropTreat(at: 170)
                    for _ in 0..<240 where !world.particles.contains(where: { if case .heart = $0.kind { return true }; return false }) {
                        world.update(1.0 / 60.0)
                    }
                    run(world, 0.25)
                }),
                ("💤  Naps (more at night)", { world in
                    let sleeper = place(world, at: 60)
                    run(world, 1.5)
                    sleeper.start(.sleep, seconds: 100)
                    run(world, 2.2)
                }),
                ("🏃  Busy Mac? It sprints, like RunCat", { world in
                    let runner = place(world, at: 60)
                    run(world, 1.5)
                    world.busy = 1
                    runner.start(.run, seconds: 100)
                    run(world, 0.7)
                }),
            ]
            for (i, scene) in scenes.enumerated() {
                let column = CGFloat(i % 2), row = CGFloat(i / 2)
                let origin = CGPoint(x: 90 + column * 540, y: 270 - row * 160)
                text(scene.0, rounded(20, .bold), ink, in: CGRect(x: origin.x, y: origin.y + 74, width: 480, height: 28))
                let (world, _) = makeWorld(width: 230)
                scene.1(world)
                draw(world, in: ctx, at: origin, zoom: 2)
            }
        }
    }

    /// 사는 곳: 메뉴 막대와 Touch Bar
    private static func places() -> CGImage {
        let size = CGSize(width: 1200, height: 560)
        return canvas(size) { ctx in
            background(ctx, size, [lavender, mint], seed: 59)
            card(ctx, CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
            heading("Lives in your menu bar — and your Touch Bar", "No Touch Bar? Clawds roam the menu bar (clicks pass right through). Got one? They move in there too.", in: size)

            // 메뉴 막대 흉내: 배경 화면 + 반투명 메뉴 막대 + 그 위를 걷는 Clawd들
            let k: CGFloat = 2
            let bar = CGRect(x: 90, y: 340, width: 1020, height: 24 * k)
            let wallpaper = CGGradient(colorsSpace: space, colors: [rgb(255, 196, 170), rgb(196, 170, 255)] as CFArray, locations: nil)!
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: CGRect(x: bar.minX, y: bar.minY - 70, width: bar.width, height: bar.height + 70),
                               cornerWidth: 16, cornerHeight: 16, transform: nil))
            ctx.clip()
            ctx.drawLinearGradient(wallpaper, start: CGPoint(x: bar.minX, y: bar.maxY), end: CGPoint(x: bar.maxX, y: bar.minY - 70), options: [])
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.78))
            ctx.fill(bar)
            ctx.restoreGState()
            text("  Finder   File   Edit   View", NSFont.systemFont(ofSize: 13 * k, weight: .medium), .black,
                 in: CGRect(x: bar.minX + 10, y: bar.minY + 8, width: 700, height: 36))
            text("Tue 9:41 AM", NSFont.systemFont(ofSize: 13 * k, weight: .medium), .black,
                 in: CGRect(x: bar.maxX - 190, y: bar.minY + 8, width: 180, height: 36), align: .right)
            if let runner = RunnerClock.menuBarImages(px: 1.5 * k).first {
                runner.draw(in: CGRect(x: bar.maxX - 260, y: bar.minY + (bar.height - runner.size.height) / 2,
                                       width: runner.size.width, height: runner.size.height))
            }

            let free = CGRect(x: bar.minX + 360, y: bar.minY, width: bar.width - 360 - 250, height: bar.height)
            let (menu, menuLink) = makeWorld(width: free.width / k, height: 24, px: 1.5, transparent: true)
            _ = place(menu, at: 14)
            run(menu, 1.5)
            work(menuLink, "m", "Write the README", tool: "Edit", minutesAgo: 0.8)
            run(menu, 1.2)
            draw(menu, in: ctx, at: free.origin, zoom: k, frame: false)

            // Touch Bar 흉내: 맥북 키보드 윗부분
            let deck = CGRect(x: 90, y: 70, width: 1020, height: 150)
            ctx.addPath(CGPath(roundedRect: deck, cornerWidth: 18, cornerHeight: 18, transform: nil))
            ctx.setFillColor(rgb(58, 58, 64))
            ctx.fillPath()
            let (touch, touchLink) = makeWorld(width: 560)
            _ = place(touch, at: 50)
            let toucher = place(touch, at: 330, facing: -1)
            _ = place(touch, at: 450)
            run(touch, 1.5)
            work(touchLink, "t", "Refactor the API", tool: "Bash", minutesAgo: 0.6)
            run(touch, 0.5)
            toucher.start(.clock, seconds: 100)
            run(touch, 0.8)
            draw(touch, in: ctx, at: CGPoint(x: 120, y: 122), zoom: 1.45)

            // 밝기·소리 버튼
            let symbols = ["sun.min.fill", "sun.max.fill", "speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.3.fill"]
            for (i, name) in symbols.enumerated() {
                let button = CGRect(x: 950 + CGFloat(i % 3) * 52, y: i < 3 ? 162 : 112, width: 46, height: 40)
                ctx.addPath(CGPath(roundedRect: button, cornerWidth: 8, cornerHeight: 8, transform: nil))
                ctx.setFillColor(rgb(90, 90, 96))
                ctx.fillPath()
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold).applying(.init(paletteColors: [.white]))
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                    image.draw(in: CGRect(x: button.midX - image.size.width / 2, y: button.midY - image.size.height / 2,
                                          width: image.size.width, height: image.size.height))
                }
            }
            text("Touch Bar: Clawds + brightness & volume keys + a tiny Mac dashboard", rounded(16, .semibold), .white,
                 in: CGRect(x: 120, y: 80, width: 800, height: 24))
        }
    }
}
