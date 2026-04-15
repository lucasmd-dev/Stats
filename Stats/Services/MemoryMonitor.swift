import Darwin
import Foundation

/// Snapshot used to render RAM and swap values in the menu bar.
struct MemorySnapshot {
    let used: UInt64
    let total: UInt64
    let swapUsed: UInt64
}

/// Reads RAM and swap usage from macOS kernel statistics.
final class MemoryMonitor {
    private let hostPort: host_t = mach_host_self()
    private let totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    private let pageSize: UInt64 = UInt64(vm_kernel_page_size)

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    /// Returns the memory values currently shown by the app.
    func sample() -> MemorySnapshot {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { bound in
                host_statistics64(hostPort, HOST_VM_INFO64, bound, &count)
            }
        }

        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            let internalPages = UInt64(stats.internal_page_count)
            let purgeablePages = UInt64(stats.purgeable_count)
            let wiredPages = UInt64(stats.wire_count)
            let compressorPages = UInt64(stats.compressor_page_count)

            let appMemory = (internalPages > purgeablePages ? internalPages - purgeablePages : 0) * pageSize
            let wired = wiredPages * pageSize
            let compressed = compressorPages * pageSize
            used = min(appMemory + wired + compressed, totalMemory)
        }

        var swapUsed: UInt64 = 0
        var swapInfo = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapInfo, &swapSize, nil, 0) == 0 {
            swapUsed = swapInfo.xsu_used
        }

        return MemorySnapshot(used: used, total: totalMemory, swapUsed: swapUsed)
    }
}
