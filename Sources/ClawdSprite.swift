import AppKit

enum Palette {
    /// Claude Code 시작 화면의 Clawd 색 (rgb 215,119,87)
    static let clawd = CGColor(srgbRed: 215 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
    static let eye = CGColor(gray: 0, alpha: 1)
    static let treat = CGColor(srgbRed: 0.98, green: 0.78, blue: 0.42, alpha: 1)
    static let treatGlow = CGColor(srgbRed: 1.0, green: 0.93, blue: 0.72, alpha: 1)
    static let heart = CGColor(srgbRed: 1.0, green: 0.45, blue: 0.52, alpha: 1)
    static let anger = CGColor(srgbRed: 1.0, green: 0.3, blue: 0.25, alpha: 1)
    static let steam = CGColor(gray: 0.8, alpha: 1)
    static let sign = CGColor(srgbRed: 0.96, green: 0.92, blue: 0.85, alpha: 1)
    static let signInk = CGColor(gray: 0.16, alpha: 1)

    /// 짜증이 날수록 몸이 붉어진다 (0 = 평소, 1 = 새빨감)
    static func clawd(heat: CGFloat) -> CGColor {
        let t = min(max(heat, 0), 1)
        return CGColor(srgbRed: (215 + (235 - 215) * t) / 255, green: (119 + (60 - 119) * t) / 255,
                       blue: (87 + (55 - 87) * t) / 255, alpha: 1)
    }
    static let dust = CGColor(gray: 0.55, alpha: 1)
    static let text = NSColor(white: 0.65, alpha: 1)
    static let sweat = CGColor(srgbRed: 0.55, green: 0.8, blue: 1.0, alpha: 1)
    static let bubbleFill = CGColor(gray: 0.12, alpha: 1)
    static let bubbleText = NSColor(white: 0.93, alpha: 1)
    static let props: [Character: CGColor] = [
        "p": CGColor(srgbRed: 0.96, green: 0.92, blue: 0.83, alpha: 1),   // 책장
        "l": CGColor(gray: 0.5, alpha: 1),                                  // 글줄
        "c": CGColor(srgbRed: 0.36, green: 0.55, blue: 0.9, alpha: 1),     // 책 표지
        "s": CGColor(gray: 0.74, alpha: 1),                                 // 노트북 덮개
        "d": CGColor(gray: 0.5, alpha: 1),                                  // 노트북 받침
        "o": clawd,                                                         // 로고 / 손
        "g": CGColor(gray: 0.42, alpha: 1),                                 // 아령 원판
        "b": CGColor(gray: 0.78, alpha: 1),                                 // 아령 봉
    ]
    static let accent = NSColor(cgColor: clawd)!
}

/// 18×10 픽셀짜리 Clawd. Claude Code의 ` ▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝ ` 로고를 정사각 픽셀로 옮긴 것.
enum ClawdSprite {
    static let cols = 18
    static let rows = 10

    enum Legs { case stand, stepA, stepB, tucked }
    enum Eyes { case open, blink, up, happy, closed, tired, frustrated }
    enum Prop { case none, book(page: Int), laptop(typing: Int), dumbbell(up: Bool), holdSign }

    struct Frame {
        var armsUp = false
        var legs = Legs.stand
        var sitting = false
        var eyes = Eyes.open
        var look = 0            // -1 왼쪽, 0 정면, 1 오른쪽
        var prop = Prop.none
    }

    private static let body = cells([
        "...############...",
        "...############...",
        "...############...",
        "...############...",
        ".################.",
        ".################.",
        "...############...",
        "...############...",
    ])

    private static let bodyArmsUp = cells([
        "...############...",
        "...############...",
        ".#.############.#.",
        ".#.############.#.",
        "..##############..",
        "...############...",
        "...############...",
        "...############...",
    ])

    private static let legs: [Legs: [(Int, Int)]] = [
        .stand: cells(["....#.#....#.#....", "....#.#....#.#...."], firstRow: 8),
        .stepA: cells(["....#.#....#.#....", "....#......#......"], firstRow: 8),
        .stepB: cells(["....#.#....#.#....", "......#......#...."], firstRow: 8),
        .tucked: cells(["....#.#....#.#...."], firstRow: 8),
    ]

    static func cells(_ art: [String], firstRow: Int = 0) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (r, line) in art.enumerated() {
            for (c, ch) in line.enumerated() where ch == "#" {
                out.append((c, r + firstRow))
            }
        }
        return out
    }

    /// 왼쪽 눈 기준 좌표. 오른쪽 눈은 x를 뒤집어 쓴다.
    private static func eyeCells(_ eyes: Eyes) -> [(Int, Int)] {
        switch eyes {
        case .open: return [(0, 0), (0, 1)]
        case .blink: return [(0, 1)]
        case .up: return [(0, -1), (0, 0)]
        case .happy: return [(0, 0), (-1, 1), (1, 1)]
        case .closed: return [(-1, 1), (0, 1)]
        case .tired: return [(0, 1)]
        case .frustrated: return [(-1, -1), (0, 0), (-1, 1)]   // > <
        }
    }

    /// (centerX, bottom) 위치에 한 프레임을 그린다. px는 스프라이트 픽셀 한 칸의 크기(pt).
    static func draw(_ frame: Frame, in ctx: CGContext, centerX: CGFloat, bottom: CGFloat, px: CGFloat,
                     scale: CGFloat = 2, color: CGColor = Palette.clawd) {
        let left = snap(centerX - CGFloat(cols) * px / 2, scale)
        let base = snap(bottom, scale)
        let drop = frame.sitting ? 2 : 0

        func rect(_ c: Int, _ r: Int) -> CGRect {
            CGRect(x: left + CGFloat(c) * px, y: base + CGFloat(rows - 1 - r) * px, width: px, height: px)
        }

        var bodyRects = (frame.armsUp ? bodyArmsUp : body).map { rect($0.0, $0.1 + drop) }
        if !frame.sitting, let legCells = legs[frame.legs] {
            bodyRects += legCells.map { rect($0.0, $0.1) }
        }
        ctx.setFillColor(color)
        ctx.fill(bodyRects)

        let eyeRow = 2 + drop
        let leftEye = 5 + frame.look
        let rightEye = 12 + frame.look
        var eyeRects: [CGRect] = []
        for (dx, dy) in eyeCells(frame.eyes) {
            eyeRects.append(rect(leftEye + dx, eyeRow + dy))
            eyeRects.append(rect(rightEye - dx, eyeRow + dy))
        }
        ctx.setFillColor(Palette.eye)
        ctx.fill(eyeRects)

        drawProp(frame.prop, rect: rect, in: ctx)
    }

    // 소품은 스프라이트 격자 좌표로 그린다. 음수 행은 머리 위.
    private static let books = [
        ["pppp..pppp", "pllpppllpp", "pppllpplpp", "cccccccccc"],
        ["pppp..pppp", "ppllpppllp", "pllpppplpp", "cccccccccc"],
    ]
    private static let laptop = ["ssssssssssss", "sssssoosssss", "sssssoosssss", "dddddddddddd"]

    private static func drawProp(_ prop: Prop, rect: (Int, Int) -> CGRect, in ctx: CGContext) {
        func paint(_ art: [String], col: Int, row: Int) {
            for (r, line) in art.enumerated() {
                for (c, ch) in line.enumerated() {
                    guard let color = Palette.props[ch] else { continue }
                    ctx.setFillColor(color)
                    ctx.fill(rect(col + c, row + r))
                }
            }
        }

        switch prop {
        case .none:
            break
        case .book(let page):
            paint(books[page % 2], col: 4, row: 6)
        case .laptop(let typing):
            paint(laptop, col: 3, row: 6)
            // 양손을 번갈아 들어 타자 치는 느낌
            ctx.setFillColor(Palette.clawd)
            ctx.fill(rect(typing % 2 == 0 ? 2 : 15, 5))
        case .dumbbell(let up):
            let bar = up ? -3 : -1
            ctx.setFillColor(Palette.clawd)
            for r in (bar + 2)...1 {
                ctx.fill(rect(1, r))
                ctx.fill(rect(16, r))
            }
            paint(["gg" + String(repeating: ".", count: 14) + "gg",
                   "ggbbbbbbbbbbbbbbgg",
                   "gg" + String(repeating: ".", count: 14) + "gg"], col: 0, row: bar - 1)
        case .holdSign:
            // 머리 위 팻말(렌더러가 그림)을 양손으로 받친다
            ctx.setFillColor(Palette.clawd)
            for r in 0...1 {
                ctx.fill(rect(1, r))
                ctx.fill(rect(16, r))
            }
        }
    }

    /// 메뉴 막대·Control Strip 버튼용 아이콘
    static func icon(px: CGFloat, eyes: Eyes = .open) -> NSImage {
        let size = NSSize(width: CGFloat(cols) * px, height: CGFloat(rows) * px)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(Frame(eyes: eyes), in: ctx, centerX: size.width / 2, bottom: 0, px: px)
            return true
        }
        return image
    }

    static func snap(_ v: CGFloat, _ scale: CGFloat) -> CGFloat {
        (v * scale).rounded() / scale
    }
}

/// 작은 픽셀 그림들 (간식, 하트)
enum PixelArt {
    static let spark = ClawdSprite.cells([
        "...#...",
        ".#.#.#.",
        "..###..",
        "#######",
        "..###..",
        ".#.#.#.",
        "...#...",
    ])

    /// 화났을 때 머리 옆에 뜨는 💢
    static let anger = ClawdSprite.cells([
        "##.##",
        "#...#",
        ".....",
        "#...#",
        "##.##",
    ])

    static let heart = ClawdSprite.cells([
        "##.##",
        "#####",
        ".###.",
        "..#..",
    ])

    static func draw(_ cells: [(Int, Int)], size: (Int, Int), in ctx: CGContext, centerX: CGFloat, centerY: CGFloat,
                     px: CGFloat, color: CGColor, scale: CGFloat = 2) {
        let left = ClawdSprite.snap(centerX - CGFloat(size.0) * px / 2, scale)
        let top = ClawdSprite.snap(centerY + CGFloat(size.1) * px / 2, scale)
        let rects = cells.map { CGRect(x: left + CGFloat($0.0) * px, y: top - CGFloat($0.1 + 1) * px, width: px, height: px) }
        ctx.setFillColor(color)
        ctx.fill(rects)
    }
}

/// 시계 팻말용 3×5 픽셀 숫자
enum PixelFont {
    private static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", "###", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"],
        "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"],
        "7": ["###", "..#", "..#", "..#", "..#"],
        "8": ["###", "#.#", "###", "#.#", "###"],
        "9": ["###", "#.#", "###", "..#", "###"],
        ":": [".", "#", ".", "#", "."],
        " ": [".", ".", ".", ".", "."],
    ]

    /// 글자 사이 1칸 띄운 전체 폭 (픽셀 수)
    static func width(_ text: String) -> Int {
        text.compactMap { glyphs[$0]?.first?.count }.reduce(0) { $0 + $1 + 1 } - 1
    }

    /// (left, bottom)에서 시작해 글자를 찍는다
    static func draw(_ text: String, in ctx: CGContext, left: CGFloat, bottom: CGFloat, px: CGFloat, color: CGColor) {
        var x = left
        var rects: [CGRect] = []
        for character in text {
            guard let glyph = glyphs[character] else { continue }
            for (r, line) in glyph.enumerated() {
                for (c, ch) in line.enumerated() where ch == "#" {
                    rects.append(CGRect(x: x + CGFloat(c) * px, y: bottom + CGFloat(4 - r) * px, width: px, height: px))
                }
            }
            x += CGFloat(glyph[0].count + 1) * px
        }
        ctx.setFillColor(color)
        ctx.fill(rects)
    }
}
