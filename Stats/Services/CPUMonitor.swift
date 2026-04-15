import Darwin

/// Samples aggregate CPU usage across all cores using kernel tick counters.
final class CPUMonitor {
    private let hostPort: host_t = mach_host_self()
    private var previousTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    /// Returns total CPU utilization in the `0...1` range.
    func sample() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        defer {
            let size = vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var currentTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        currentTicks.reserveCapacity(Int(numCPUs))

        var totalUserDelta: UInt64 = 0
        var totalSystemDelta: UInt64 = 0
        var totalIdleDelta: UInt64 = 0
        var totalNiceDelta: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user   = UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)])
            let idle   = UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)])
            let nice   = UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)])

            currentTicks.append((user, system, idle, nice))

            if i < previousTicks.count {
                let prev = previousTicks[i]
                totalUserDelta   += UInt64(user   &- prev.user)
                totalSystemDelta += UInt64(system &- prev.system)
                totalIdleDelta   += UInt64(idle   &- prev.idle)
                totalNiceDelta   += UInt64(nice   &- prev.nice)
            }
        }

        previousTicks = currentTicks

        let totalAll = totalUserDelta + totalSystemDelta + totalIdleDelta + totalNiceDelta
        return totalAll > 0
            ? Double(totalUserDelta + totalSystemDelta + totalNiceDelta) / Double(totalAll)
            : 0
    }
}
