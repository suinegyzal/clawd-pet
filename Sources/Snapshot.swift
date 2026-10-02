import AppKit

/// `ClawdPet --snapshot out.png`: Touch Bar 없이도 그림을 확인할 수 있게
/// 여러 장면을 4배 확대한 PNG 한 장으로 렌더링한다.
enum Snapshot {
    @MainActor static func write(to path: String) {
        let width: CGFloat = 685
        var scenes: [(CGContext) -> Void] = []

        // 1행: 포즈 모음
        scenes.append { ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: 30))
            typealias F = ClawdSprite.Frame
            let poses: [F] = [
                F(), F(eyes: .blink), F(look: 1), F(look: -1),
                F(legs: .stepA, look: 1), F(legs: .stepB, look: 1),
                F(armsUp: true, legs: .tucked), F(eyes: .up), F(eyes: .happy),
                F(armsUp: true, legs: .stepA, eyes: .happy), F(sitting: true, eyes: .closed),
            ]
            for (i, pose) in poses.enumerated() {
                ClawdSprite.draw(pose, in: ctx, centerX: 30 + CGFloat(i) * 58, bottom: 0, px: 2)
            }
        }

        // 나머지 행: 실제 시뮬레이션
        let world = Playground()
        world.width = width
        world.px = 2
        world.addPet(at: 90)
        world.addPet(at: 330)
        world.addPet(at: 560)
        func run(_ seconds: Double) {
            for _ in 0..<Int(seconds * 60) { world.update(1.0 / 60.0) }
        }
        // world는 계속 변하므로 찍는 순간의 모습을 이미지로 굳혀 둔다
        func capture() { scenes.append(frozen(world, width: width)) }

        run(0.2)
        capture()                                   // 떨어지는 중
        run(1.2)
        world.pets[0].start(.think, seconds: 5)
        world.pets[1].start(.sleep, seconds: 8)
        world.pets[2].start(.walk, seconds: 5)
        run(1.0)
        capture()                                   // 생각 중 / 자는 중 / 걷는 중
        world.dropTreat(at: 220)
        run(0.35)
        capture()                                   // 간식 떨어짐, 모두 달려감
        run(1.5)
        capture()                                   // 누군가 먹고 하트
        world.pets[2].poke(in: world)
        run(0.12)
        capture()                                   // 찌르면 점프
        world.pets[1].grab(in: world)
        world.pets[1].drag(to: 450, in: world)
        run(0.2)
        capture()                                   // 들어 올림
        world.pets[1].release(in: world)
        run(0.2)
        capture()                                   // 떨어져서 먼지

        // Claude 연동: 세션 셋이 각각 공부·작업·운동, 그다음 완료 알림과 확인 요청
        let work = Playground()
        work.width = 1004
        work.px = 2
        let link = ClaudeLink(directory: URL(fileURLWithPath: "/nonexistent-clawd-snapshot"))
        work.link = link
        for x in [120, 300, 820] as [CGFloat] { work.addPet(at: x) }
        func event(_ session: String, _ name: String, _ extra: [String: Any] = [:]) {
            link.handle(extra.merging(["session_id": session, "hook_event_name": name]) { a, _ in a })
        }
        func runWork(_ seconds: Double) {
            for _ in 0..<Int(seconds * 60) { work.update(1.0 / 60.0) }
        }
        runWork(1.5)
        event("a", "PreToolUse", ["tool_name": "Read", "tool_input": ["file_path": "/x/README.md"]])
        event("b", "PreToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/x/Clawd.swift"]])
        event("c", "PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "./build.sh", "description": "Build the app"]])
        runWork(0.4)
        scenes.append(frozen(work, width: 1004))
        runWork(0.5)
        scenes.append(frozen(work, width: 1004))
        event("a", "Stop", ["last_assistant_message": "## 요약\n터치바에서 **Clawd**가 돌아다니는 앱을 만들었어요. 빌드도 확인했습니다."])
        event("b", "Notification", ["message": "Claude needs your permission to use Bash"])
        runWork(1.2)
        scenes.append(frozen(work, width: 1004))
        work.showGauge(.volume, level: 0.6875)
        runWork(0.1)
        scenes.append(frozen(work, width: 1004))

        // 기분: 30초 / 3분 / 7분 / 12분째 일하는 중
        let moody = Playground()
        moody.width = 1004
        moody.px = 2
        let moodLink = ClaudeLink(directory: URL(fileURLWithPath: "/nonexistent-clawd-snapshot"))
        moody.link = moodLink
        for x in [60, 310, 560, 810] as [CGFloat] { moody.addPet(at: x) }
        func runMoody(_ seconds: Double) {
            for _ in 0..<Int(seconds * 60) { moody.update(1.0 / 60.0) }
        }
        runMoody(1.5)
        for (i, minutes) in [12.0, 7, 3, 0.5].enumerated() {
            let id = "mood\(i)"
            moodLink.handle(["session_id": id, "hook_event_name": "UserPromptSubmit", "prompt": "\(Int(minutes))분 걸린 일"],
                            at: Date().addingTimeInterval(-minutes * 60))
            moodLink.handle(["session_id": id, "hook_event_name": "PreToolUse", "tool_name": ["Bash", "Edit", "Read", "Edit"][i],
                             "tool_input": [:]], at: Date().addingTimeInterval(Double(-i)))
        }
        for _ in 0..<3 {
            runMoody(1.3)
            scenes.append(frozen(moody, width: 1004))
        }

        // 메뉴 막대 (투명, 24pt): 밝은 메뉴 막대와 어두운 메뉴 막대 위에서
        let bar = Playground()
        bar.transparent = true
        bar.width = 1004
        bar.height = 24
        bar.px = 1.5
        let barLink = ClaudeLink(directory: URL(fileURLWithPath: "/nonexistent-clawd-snapshot"))
        bar.link = barLink
        for x in [60, 330, 640, 900] as [CGFloat] { bar.addPet(at: x) }
        for _ in 0..<90 { bar.update(1.0 / 60.0) }
        barLink.handle(["session_id": "w", "hook_event_name": "UserPromptSubmit", "prompt": "디놈들 카드뉴스"],
                       at: Date().addingTimeInterval(-7 * 60))
        barLink.handle(["session_id": "w", "hook_event_name": "PreToolUse", "tool_name": "Edit", "tool_input": [:]])
        barLink.handle(["session_id": "d", "hook_event_name": "Stop", "last_assistant_message": "릴스 아이디어 3개를 정리했어요."])
        for _ in 0..<90 { bar.update(1.0 / 60.0) }
        let barImage = frozen(bar, width: 1004)
        for shade in [0.92, 0.2] as [CGFloat] {
            scenes.append { ctx in
                ctx.setFillColor(CGColor(gray: shade, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: 1004, height: 30))
                barImage(ctx)
            }
        }

        render(scenes, width: 1004, to: path)
    }

    private static func frozen(_ world: Playground, width: CGFloat) -> (CGContext) -> Void {
        let scale: CGFloat = 4
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(world.height * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        Renderer.draw(world, in: ctx, size: CGSize(width: width, height: world.height), scale: 2)
        let image = ctx.makeImage()!
        return { target in target.draw(image, in: CGRect(x: 0, y: 0, width: width, height: world.height)) }
    }

    private static func render(_ scenes: [(CGContext) -> Void], width: CGFloat, to path: String) {
        let scale: CGFloat = 4
        let rowHeight: CGFloat = 30
        let gap: CGFloat = 4
        let height = CGFloat(scenes.count) * (rowHeight + gap) - gap
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.25, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width * scale, height: height * scale))
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .none
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        for (i, scene) in scenes.enumerated() {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: height - rowHeight - CGFloat(i) * (rowHeight + gap))
            ctx.clip(to: CGRect(x: 0, y: 0, width: width, height: rowHeight))
            scene(ctx)
            ctx.restoreGState()
        }

        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("snapshot → \(path)")
    }
}
