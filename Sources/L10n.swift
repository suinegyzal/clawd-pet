import Foundation

/// 메뉴에서 고른 언어로 보여 준다. "자동"이면 맥 언어가 한국어일 때 한국어, 아니면 영어.
/// CLAWD_LANG=en 이나 ko 로 실행하면 처음엔 그걸 따른다 (스크린샷·문서용). 메뉴에서 고르면 그쪽이 이긴다.
enum L10n {
    enum Choice: String, CaseIterable {
        case auto, korean = "ko", english = "en"
    }

    private static let key = "language"
    private static var launchOverride = ProcessInfo.processInfo.environment["CLAWD_LANG"]

    static var choice: Choice {
        get { Choice(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            launchOverride = nil
            korean = resolve()
        }
    }

    private(set) static var korean = resolve()

    private static func resolve() -> Bool {
        if let forced = launchOverride { return forced.hasPrefix("ko") }
        switch choice {
        case .korean: return true
        case .english: return false
        case .auto: return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko")
        }
    }
}

/// 한국어와 영어 중 지금 언어에 맞는 쪽 (문자열, 배열 어느 것이든)
func tr<T>(_ korean: T, _ english: T) -> T {
    L10n.korean ? korean : english
}
