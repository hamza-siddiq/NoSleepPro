import AppKit
import ServiceManagement

/// Options for the "Keep Awake For" submenu.
enum TimerOption: Int, CaseIterable {
    case fifteen = 15
    case thirty = 30
    case oneHour = 60
    case twoHours = 120
    case fiveHours = 300
    case indefinite = 0

    var title: String {
        switch self {
        case .fifteen:    return "15 minutes"
        case .thirty:     return "30 minutes"
        case .oneHour:    return "1 hour"
        case .twoHours:   return "2 hours"
        case .fiveHours:  return "5 hours"
        case .indefinite: return "Until I turn it off"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let engine = SleepGuard.shared

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            runSelfTest()   // exits the process
            return
        }

        NSApp.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        engine.onChange = { [weak self] in self?.refresh() }
        refresh()

        // Refresh the icon/tooltip once a minute so a running timer's countdown stays current.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Mac unable to sleep after we quit.
        if engine.isActive { engine.deactivate() }
    }

    // MARK: - Click handling

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        let isSecondary = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isSecondary {
            showMenu()
        } else {
            engine.toggle()
            pulseIcon()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)   // pops the menu under the item
        statusItem.menu = nil                   // detach so left-click keeps toggling
    }

    // MARK: - Icon

    private func refresh() {
        guard let button = statusItem.button else { return }
        if engine.isActive {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [NSColor.systemYellow]))
            let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Awake")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false           // keep the amber colour — the bolt "pops"
            button.image = image
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = NSImage(systemSymbolName: "bolt", accessibilityDescription: "Sleep allowed")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true            // adapts to light/dark menu bar
            button.image = image
        }
        button.toolTip = engine.tooltip
    }

    /// A quick pop when toggled, so the change feels tactile.
    private func pulseIcon() {
        guard let button = statusItem.button else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            button.animator().alphaValue = 0.35
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                button.animator().alphaValue = 1.0
            }
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: engine.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = item(engine.isActive ? "Turn Off" : "Keep Awake", #selector(toggleFromMenu))
        menu.addItem(toggle)

        let timerParent = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for option in TimerOption.allCases {
            let mi = item(option.title, #selector(setTimer(_:)))
            mi.tag = option.rawValue
            if engine.isActive {
                let matches = (option == .indefinite && engine.selectedTimerMinutes == nil)
                    || (engine.selectedTimerMinutes == option.rawValue)
                mi.state = matches ? .on : .off
            }
            timerMenu.addItem(mi)
        }
        timerParent.submenu = timerMenu
        menu.addItem(timerParent)

        menu.addItem(.separator())

        let lid = item("Allow Lid to Close", #selector(toggleLidMode))
        lid.state = engine.lidCloseMode ? .on : .off
        menu.addItem(lid)

        let display = item("Keep Display On", #selector(toggleDisplay))
        display.state = engine.keepDisplayAwake ? .on : .off
        menu.addItem(display)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)

        if engine.helperInstalled {
            menu.addItem(item("Remove Closed-Lid Helper…", #selector(removeHelper)))
        }

        menu.addItem(.separator())
        menu.addItem(item("About NoSleep Pro", #selector(showAbout)))
        let quit = item("Quit NoSleep Pro", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    // MARK: - Menu actions

    @objc private func toggleFromMenu() {
        engine.toggle()
        pulseIcon()
    }

    @objc private func setTimer(_ sender: NSMenuItem) {
        let minutes = sender.tag   // 0 == indefinite
        engine.activate(minutes: minutes == 0 ? nil : minutes)
        pulseIcon()
    }

    @objc private func toggleLidMode() { engine.lidCloseMode.toggle() }
    @objc private func toggleDisplay() { engine.keepDisplayAwake.toggle() }

    @objc private func removeHelper() {
        engine.uninstallHelper { ok in
            if !ok {
                let alert = NSAlert()
                alert.messageText = "Couldn't Remove Helper"
                alert.informativeText = "The closed-lid helper could not be removed. Please try again."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "NoSleep Pro"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        alert.informativeText = """
        Version \(version)

        Keep your Mac wide awake with a single tap — even with the lid closed.

        Tap the bolt to keep awake, tap again to stop.
        Right-click for timers, options, and Quit.
        """
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    private var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("NoSleep Pro: launch-at-login change failed: \(error)")
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
    }

    // MARK: - Self-test

    /// Non-interactive end-to-end check of the keep-awake engine. Run with `--selftest`.
    /// Exercises the real `SleepGuard.activate()`/`deactivate()` path (lid-close layer
    /// skipped so it never prompts) and asserts the OS actually registers/releases the
    /// power assertion. Exits 0 on success, 1 on failure.
    private func runSelfTest() {
        func assertionsHeld() -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["-g", "assertions"]
            let out = Pipe()
            p.standardOutput = out
            try? p.run()
            p.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return text.contains("NoSleep Pro")
        }

        let originalLidMode = engine.lidCloseMode
        engine.lidCloseMode = false   // avoid the interactive closed-lid setup prompt

        print("[selftest] before:  assertion held = \(assertionsHeld())")
        engine.activate()
        let duringOK = engine.isActive && assertionsHeld()
        print("[selftest] active:  isActive = \(engine.isActive), assertion held = \(assertionsHeld())")
        engine.deactivate()
        let afterOK = !engine.isActive && !assertionsHeld()
        print("[selftest] stopped: isActive = \(engine.isActive), assertion held = \(assertionsHeld())")

        engine.lidCloseMode = originalLidMode

        let passed = duringOK && afterOK
        print("[selftest] \(passed ? "PASS ✓" : "FAIL ✗")")
        exit(passed ? 0 : 1)
    }
}
