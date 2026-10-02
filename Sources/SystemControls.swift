import AppKit
import AudioToolbox
import CoreAudio

/// 볼륨(CoreAudio)과 내장 디스플레이 밝기(DisplayServices, 비공개) 조절.
/// 키 입력을 흉내 내지 않아서 손쉬운 사용 권한이 필요 없다.
enum SystemControls {
    static let step: Float = 1.0 / 16.0

    // MARK: - 소리

    private static func outputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readProperty<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        guard let device = outputDevice() else { return nil }
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    private static func writeProperty<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ newValue: T) -> Bool {
        guard let device = outputDevice() else { return false }
        var address = address(selector)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = newValue
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    static var volume: Float? {
        readProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0))
    }

    static var isMuted: Bool {
        (readProperty(kAudioDevicePropertyMute, UInt32(0)) ?? 0) != 0
    }

    /// 볼륨을 한 칸 올리거나 내린다. 바뀐 볼륨(음소거면 0)을 돌려준다.
    static func stepVolume(_ direction: Float) -> Float? {
        guard let current = volume else { return nil }
        let next = min(1, max(0, (current / step).rounded() * step + direction * step))
        writeProperty(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(next))
        if isMuted && direction > 0 { writeProperty(kAudioDevicePropertyMute, UInt32(0)) }
        return isMuted ? 0 : next
    }

    /// 음소거를 켜고 끈다. 바뀐 뒤 음소거 상태를 돌려준다.
    static func toggleMute() -> Bool {
        writeProperty(kAudioDevicePropertyMute, UInt32(isMuted ? 0 : 1))
        return isMuted
    }

    // MARK: - 밝기

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let displayServices, let sym = dlsym(displayServices, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static var builtInDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var brightness: Float? {
        typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        guard let display = builtInDisplay, let getter = function("DisplayServicesGetBrightness", as: Get.self) else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? value : nil
    }

    /// 밝기를 한 칸 올리거나 내린다. 바뀐 밝기를 돌려준다.
    static func stepBrightness(_ direction: Float) -> Float? {
        typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
        typealias Changed = @convention(c) (CGDirectDisplayID, Double) -> Void
        guard let display = builtInDisplay, let current = brightness,
              let setter = function("DisplayServicesSetBrightness", as: Set.self) else { return nil }
        let next = min(1, max(0, (current / step).rounded() * step + direction * step))
        guard setter(display, next) == 0 else { return nil }
        // 시스템 설정의 밝기 슬라이더 등에 바뀐 값을 알린다
        function("DisplayServicesBrightnessChanged", as: Changed.self)?(display, Double(next))
        return next
    }
}
