import Foundation
import IOKit
import IOKit.ps

/// 무엇이 바쁠수록 빨리 달릴지 (RunCat의 "달리기 기준")
enum RunnerSource: String, CaseIterable {
    case cpu, memory, gpu

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return tr("메모리", "Memory")
        case .gpu: return "GPU"
        }
    }
}

/// RunCat처럼 Mac 상태를 잰다: CPU, GPU, 메모리, 저장 공간, 배터리, 네트워크, 그리고 Claude Code 사용량.
final class SystemStats {
    struct Limit {
        let used: Double        // 0...1
        let resets: Date?
    }

    struct ClaudeUsage {
        var model: String?
        var context: Double?    // 0...1
        var fiveHour: Limit?
        var sevenDay: Limit?
        var updated: Date
    }

    private(set) var cpu = 0.0              // 0...1
    private(set) var gpu = 0.0
    private(set) var disk = 0.0             // 사용 중인 비율
    private(set) var diskFreeGB = 0.0
    private(set) var memory = 0.0           // 0...1
    private(set) var memoryUsedGB = 0.0
    private(set) var battery: (level: Double, charging: Bool)?
    private(set) var download = 0.0         // 초당 바이트
    private(set) var upload = 0.0
    private(set) var claude: ClaudeUsage?

    static let statusLineFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".clawd-touchbar/statusline.json")

    private var lastTicks: [UInt32]?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var statusLineDate: Date?
    private var samples = 0

    func value(for source: RunnerSource) -> Double {
        switch source {
        case .cpu: return cpu
        case .memory: return memory
        case .gpu: return gpu
        }
    }

    func sample() {
        sampleCPU()
        sampleGPU()
        sampleMemory()
        if samples % 30 == 0 { sampleDisk() }   // 저장 공간은 천천히 변한다
        samples += 1
        sampleBattery()
        sampleNetwork()
        loadClaudeUsage()
    }

    // MARK: - CPU

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // 순서: user, system, idle, nice
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        if let last = lastTicks {
            let delta = zip(ticks, last).map { Double($0 &- $1) }
            let total = delta.reduce(0, +)
            if total > 0 { cpu = (delta[0] + delta[1] + delta[3]) / total }
        }
        lastTicks = ticks
    }

    // MARK: - GPU (IOAccelerator의 사용률, 권한 필요 없음)

    private func sampleGPU() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let statistics = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            IOObjectRelease(service)
            if let utilization = statistics?["Device Utilization %"] as? NSNumber {
                gpu = min(1, max(0, utilization.doubleValue / 100))
                return
            }
        }
    }

    // MARK: - 저장 공간

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return }
        diskFreeGB = Double(free) / 1_000_000_000
        disk = min(1, max(0, 1 - Double(free) / Double(total)))
    }

    // MARK: - 메모리 (활성 상태 보기의 "사용된 메모리"와 같은 계산)

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Double(sysconf(_SC_PAGESIZE))
        let appMemory = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let used = (appMemory + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        memoryUsedGB = used / 1_073_741_824
        memory = min(1, max(0, used / Double(ProcessInfo.processInfo.physicalMemory)))
    }

    // MARK: - 배터리

    private func sampleBattery() {
        battery = nil
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            battery = (Double(current) / Double(maximum), charging)
            return
        }
    }

    // MARK: - 네트워크 (en* 인터페이스의 초당 주고받은 양)

    private func sampleNetwork() {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.ifa_name).hasPrefix("en"),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            rx += UInt64(data.pointee.ifi_ibytes)
            tx += UInt64(data.pointee.ifi_obytes)
        }
        let now = Date()
        if let last = lastNet, rx >= last.rx, tx >= last.tx {
            let seconds = now.timeIntervalSince(last.at)
            if seconds > 0 {
                download = Double(rx - last.rx) / seconds
                upload = Double(tx - last.tx) / seconds
            }
        }
        lastNet = (rx, tx, now)
    }

    // MARK: - Claude Code 사용량 (hooks/clawd-statusline.sh 가 남긴 statusLine 입력)

    private func loadClaudeUsage() {
        let url = Self.statusLineFile
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified != statusLineDate else { return }
        statusLineDate = modified
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        func percent(_ value: Any?) -> Double? {
            (value as? NSNumber).map { min(1, max(0, $0.doubleValue / 100)) }
        }
        func limit(_ key: String) -> Limit? {
            guard let window = (json["rate_limits"] as? [String: Any])?[key] as? [String: Any],
                  let used = percent(window["used_percentage"]) else { return nil }
            let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Limit(used: used, resets: resets)
        }

        claude = ClaudeUsage(
            model: (json["model"] as? [String: Any])?["display_name"] as? String,
            context: percent((json["context_window"] as? [String: Any])?["used_percentage"]),
            fiveHour: limit("five_hour"),
            sevenDay: limit("seven_day"),
            updated: modified)
    }
}
