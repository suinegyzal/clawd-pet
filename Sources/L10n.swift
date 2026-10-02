import Foundation

/// 맥 언어가 한국어면 한국어, 아니면 영어로 보여 준다.
/// CLAWD_LANG=en 이나 ko 로 강제할 수 있다 (스크린샷·문서용).
enum L10n {
    static let korean: Bool = {
        if let forced = ProcessInfo.processInfo.environment["CLAWD_LANG"] { return forced.hasPrefix("ko") }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
    }()
}

/// 한국어와 영어 중 맥 언어에 맞는 쪽 (문자열, 배열 어느 것이든)
func tr<T>(_ korean: T, _ english: T) -> T {
    L10n.korean ? korean : english
}
