import AppKit

/// 앱이 앞에 없어도 Touch Bar를 차지하기 위한 macOS 비공개 API 래퍼.
/// MTMR, Pock 같은 Touch Bar 앱들이 쓰는 것과 같은 방식이며, 없는 API는 조용히 건너뛴다.
enum TouchBarPrivate {
    private static let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY)

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let dfr, let sym = dlsym(dfr, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static func classMethod(_ cls: AnyClass, _ name: String) -> (sel: Selector, imp: IMP)? {
        let sel = NSSelectorFromString(name)
        guard let meta = object_getClass(cls), class_respondsToSelector(meta, sel),
              let imp = class_getMethodImplementation(meta, sel) else { return nil }
        return (sel, imp)
    }

    /// Control Strip(오른쪽 시스템 버튼 영역)에 아이템을 보이거나 숨긴다.
    static func setControlStripPresence(_ id: NSTouchBarItem.Identifier, _ present: Bool) {
        typealias Fn = @convention(c) (NSString, Bool) -> Void
        function("DFRElementSetControlStripPresenceForIdentifier", as: Fn.self)?(id.rawValue as NSString, present)
    }

    static func showsCloseBoxWhenFrontmost(_ show: Bool) {
        typealias Fn = @convention(c) (Bool) -> Void
        function("DFRSystemModalShowsCloseBoxWhenFrontMost", as: Fn.self)?(show)
    }

    static func addSystemTrayItem(_ item: NSTouchBarItem) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        guard let m = classMethod(NSTouchBarItem.self, "addSystemTrayItem:") else { return }
        unsafeBitCast(m.imp, to: Fn.self)(NSTouchBarItem.self, m.sel, item)
    }

    static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBarItem) -> Void
        guard let m = classMethod(NSTouchBarItem.self, "removeSystemTrayItem:") else { return }
        unsafeBitCast(m.imp, to: Fn.self)(NSTouchBarItem.self, m.sel, item)
    }

    /// placement 0: Control Strip을 남겨 둔 채 표시, 1: Control Strip까지 덮고 넓게 표시.
    @discardableResult
    static func present(_ bar: NSTouchBar, placement: Int64, trayItem id: NSTouchBarItem.Identifier) -> Bool {
        typealias WithPlacement = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString) -> Void
        typealias Plain = @convention(c) (AnyObject, Selector, NSTouchBar, NSString) -> Void

        if let m = classMethod(NSTouchBar.self, "presentSystemModalTouchBar:placement:systemTrayItemIdentifier:") {
            unsafeBitCast(m.imp, to: WithPlacement.self)(NSTouchBar.self, m.sel, bar, placement, id.rawValue as NSString)
            return true
        }
        for name in ["presentSystemModalTouchBar:systemTrayItemIdentifier:",
                     "presentSystemModalFunctionBar:systemTrayItemIdentifier:"] {
            if let m = classMethod(NSTouchBar.self, name) {
                unsafeBitCast(m.imp, to: Plain.self)(NSTouchBar.self, m.sel, bar, id.rawValue as NSString)
                return true
            }
        }
        return false
    }

    static func minimize(_ bar: NSTouchBar) {
        callBarMethod(["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"], bar)
    }

    static func dismiss(_ bar: NSTouchBar) {
        callBarMethod(["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"], bar)
    }

    private static func callBarMethod(_ names: [String], _ bar: NSTouchBar) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar) -> Void
        for name in names {
            if let m = classMethod(NSTouchBar.self, name) {
                unsafeBitCast(m.imp, to: Fn.self)(NSTouchBar.self, m.sel, bar)
                return
            }
        }
    }
}
