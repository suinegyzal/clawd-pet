import AppKit

/// 앱 아이콘: 둥근 어두운 바탕 위에 픽셀 Clawd. `./icon/make-icon.sh` 가 이 파일과 ClawdSprite.swift 를 같이 컴파일해 실행한다.
@main enum MakeIcon {
    static func main() {
        let out = CommandLine.arguments[1]
        for size in [16, 32, 64, 128, 256, 512, 1024] {
            let s = CGFloat(size)
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // macOS 아이콘 규격처럼 가장자리를 비우고 둥근 사각형 바탕
            let inset = s * 0.1
            let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: box.width * 0.225, cornerHeight: box.width * 0.225, transform: nil))
            ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
            ctx.fillPath()
            // 18×10 스프라이트를 바탕 폭의 70%로
            let px = (box.width * 0.7 / CGFloat(ClawdSprite.cols)).rounded(.down)
            let spriteH = px * CGFloat(ClawdSprite.rows)
            ClawdSprite.draw(ClawdSprite.Frame(), in: ctx, centerX: s / 2, bottom: box.midY - spriteH / 2, px: px, scale: 1)
            let image = ctx.makeImage()!
            let url = URL(fileURLWithPath: out).appendingPathComponent("icon_\(size).png")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
