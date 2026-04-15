import AppKit
import ServiceManagement

private enum StatusDisplay {
    static let bytesPerGigabyte = 1_073_741_824.0
    static let refreshInterval: TimeInterval = 2.0
    static let refreshLeeway = DispatchTimeInterval.milliseconds(200)
}

/// Coordinates the menu bar item lifecycle and keeps the displayed stats up to date.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let samplingQueue = DispatchQueue(label: "com.stats.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.font = font
            button.alignment = .center
            button.title = "Stats"
            button.target = self
            button.action = #selector(showMenuFromStatusItem(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let timerSource = DispatchSource.makeTimerSource(queue: samplingQueue)
        timerSource.schedule(
            deadline: .now(),
            repeating: StatusDisplay.refreshInterval,
            leeway: StatusDisplay.refreshLeeway
        )
        timerSource.setEventHandler { [weak self] in
            self?.updateStatusItemTitle()
        }
        timerSource.resume()
        timer = timerSource
    }

    private func updateStatusItemTitle() {
        let cpuUsage = cpuMonitor.sample()
        let memorySnapshot = memoryMonitor.sample()

        let cpuPercentage = Int(round(cpuUsage * 100))
        let usedMemoryInGigabytes = Double(memorySnapshot.used) / StatusDisplay.bytesPerGigabyte
        let totalMemoryInGigabytes = Double(memorySnapshot.total) / StatusDisplay.bytesPerGigabyte
        let swapInGigabytes = Double(memorySnapshot.swapUsed) / StatusDisplay.bytesPerGigabyte

        let title = String(
            format: "CPU %3d%%  RAM %5.1f/%2.0fG  SWP %4.1fG",
            cpuPercentage, usedMemoryInGigabytes, totalMemoryInGigabytes, swapInGigabytes
        )

        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem.button, button.title != title else { return }
            button.title = title
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Stats",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showMenuFromStatusItem(_ sender: NSStatusBarButton) {
        let menu = buildMenu()
        menu.minimumWidth = sender.bounds.width
        menu.update()
        let menuWidth = max(menu.size.width, sender.bounds.width)
        let point = NSPoint(
            x: sender.bounds.midX - (menuWidth / 2),
            y: sender.bounds.minY - 6
        )
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp

        do {
            if isLaunchAtLoginEnabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            NSLog("Launch at Login toggle failed: \(error)")
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.cancel()
    }
}
