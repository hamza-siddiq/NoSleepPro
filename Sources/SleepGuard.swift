import Foundation
import AppKit
import IOKit.pwr_mgt

/// The engine that keeps the Mac awake.
///
/// NoSleep Pro combines two independent layers so it stays reliable in every situation:
///
/// 1. **IOKit power assertion** (`IOPMAssertionCreateWithName`) — instant, needs no
///    privileges. Prevents idle system sleep (and, optionally, display sleep) while the
///    lid is open. This is the same mechanism the `caffeinate` command uses.
///
/// 2. **`pmset disablesleep`** — the *only* mechanism that keeps a MacBook awake with the
///    **lid closed**. Clamshell sleep cannot be blocked by a power assertion, so this is
///    what makes "close the lid and keep working" actually work. It requires root, so the
///    first time it is needed NoSleep Pro installs a tightly-scoped, password-less helper:
///    a single `sudoers` rule limited to *exactly* `pmset disablesleep 1|0` and nothing
///    else. After that one-time approval every toggle is instant and silent.
///
/// Safety: the IOKit assertion is released automatically by the OS the instant the app dies.
/// `disablesleep` is reverted to `0` on quit, defensively on every launch, and by macOS on
/// reboot. The one uncovered case is a hard crash *while closed-lid mode is engaged* — sleep
/// then stays disabled until NoSleep Pro next launches (Launch at Login covers the next login)
/// or the Mac reboots.
@MainActor
final class SleepGuard {
    static let shared = SleepGuard()

    /// Invoked on the main thread whenever the active state or a capability changes,
    /// so the menu-bar UI can refresh.
    var onChange: (() -> Void)?

    private(set) var isActive = false
    private(set) var expiresAt: Date?
    private(set) var selectedTimerMinutes: Int?   // nil / 0 == indefinite
    private(set) var lidCloseEngaged = false       // did `pmset disablesleep 1` actually take effect?

    private let defaults = UserDefaults.standard
    private enum Key {
        static let lidClose = "lidCloseMode"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let helperInstalled = "helperInstalled"
    }

    private var assertionID = IOPMAssertionID(0)
    private var hasAssertion = false
    private var timer: Timer?
    private var lidSetupInFlight = false

    private init() {
        // Defensive: if a previous session crashed while sleep was disabled and the
        // password-less helper is present, silently restore normal sleep on launch.
        // Done off the main thread so startup never blocks on `sudo` (slow on directory-
        // bound Macs). `runSudoN` is nonisolated and touches no shared state.
        if helperInstalled {
            DispatchQueue.global(qos: .utility).async { [self] in _ = runSudoN(disable: false) }
        }
    }

    // MARK: - Preferences

    /// When active, also prevent lid-close (clamshell) sleep. On by default — it's the
    /// whole point of the app.
    var lidCloseMode: Bool {
        get { defaults.object(forKey: Key.lidClose) == nil ? true : defaults.bool(forKey: Key.lidClose) }
        set {
            defaults.set(newValue, forKey: Key.lidClose)
            if isActive { reapplyLidClose() }
            onChange?()
        }
    }

    /// When active, also keep the display awake. Off by default to save power — most
    /// "keep awake" needs (downloads, builds, streaming to a TV) don't need the screen on.
    var keepDisplayAwake: Bool {
        get { defaults.bool(forKey: Key.keepDisplayAwake) }
        set {
            defaults.set(newValue, forKey: Key.keepDisplayAwake)
            if isActive { acquireAssertion() }   // re-acquire with the new assertion type
            onChange?()
        }
    }

    var helperInstalled: Bool { defaults.bool(forKey: Key.helperInstalled) }

    // MARK: - Public control

    /// Flip keep-awake on or off. Returns the new active state.
    @discardableResult
    func toggle() -> Bool { isActive ? deactivate() : activate() }

    /// Turn keep-awake on. `minutes == nil` (or 0) means "until turned off".
    @discardableResult
    func activate(minutes: Int? = nil) -> Bool {
        guard acquireAssertion() else {
            // The OS refused the power assertion — don't pretend we're keeping the Mac awake.
            isActive = false
            onChange?()
            return false
        }
        isActive = true
        scheduleExpiry(minutes: minutes)
        onChange?()   // light up the menu-bar bolt immediately, before any setup prompt
        if lidCloseMode {
            ensureLidClose()
        } else {
            lidCloseEngaged = false
        }
        return isActive
    }

    /// Turn keep-awake off and restore normal system behaviour.
    @discardableResult
    func deactivate() -> Bool {
        releaseAssertion()
        cancelTimer()
        expiresAt = nil
        selectedTimerMinutes = nil
        if lidCloseEngaged {
            _ = runSudoN(disable: false)   // only touch pmset if we actually disabled sleep
        }
        lidCloseEngaged = false
        isActive = false
        onChange?()
        return isActive
    }

    // MARK: - Status text

    /// Absolute end-time (not a live countdown) so the status is always accurate without
    /// any polling timer running in the background.
    var statusLine: String {
        guard isActive else { return "Your Mac sleeps normally" }
        if let expiresAt {
            return "Awake until \(Self.timeFormatter.string(from: expiresAt))"
        }
        return lidCloseEngaged ? "Awake · lid can stay closed" : "Awake"
    }

    var tooltip: String {
        isActive ? statusLine : "NoSleep Pro — click to keep your Mac awake"
    }

    // MARK: - IOKit assertion (layer 1)

    @discardableResult
    private func acquireAssertion() -> Bool {
        releaseAssertion()
        let type = (keepDisplayAwake
            ? kIOPMAssertPreventUserIdleDisplaySleep
            : kIOPMAssertPreventUserIdleSystemSleep) as CFString
        var id = IOPMAssertionID(0)
        let reason = "NoSleep Pro is keeping your Mac awake" as CFString
        let result = IOPMAssertionCreateWithName(type,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason,
                                                 &id)
        if result == kIOReturnSuccess {
            assertionID = id
            hasAssertion = true
        }
        return hasAssertion
    }

    private func releaseAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
    }

    // MARK: - pmset / lid-close (layer 2)

    private func reapplyLidClose() {
        guard isActive else { return }
        if lidCloseMode {
            ensureLidClose()
        } else {
            _ = runSudoN(disable: false)
            lidCloseEngaged = false
        }
    }

    /// Try to disable lid-close sleep. If the password-less helper isn't installed yet,
    /// walk the user through the one-time setup.
    private func ensureLidClose() {
        if runSudoN(disable: true) {
            lidCloseEngaged = true
            onChange?()
            return
        }
        // Not provisioned yet — offer the one-time setup.
        lidCloseEngaged = false
        promptForLidCloseSetup()
    }

    /// Run `sudo -n pmset disablesleep <1|0>`. Succeeds silently only when the password-less
    /// helper is installed; otherwise returns false without prompting. `nonisolated` and
    /// state-free, so it's safe to call from any thread (output goes to /dev/null — nothing
    /// to drain, no deadlock risk).
    @discardableResult
    nonisolated private func runSudoN(disable: Bool) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/usr/bin/pmset", "disablesleep", disable ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func promptForLidCloseSetup() {
        guard !lidSetupInFlight else { return }   // don't stack prompts / password panels

        let alert = NSAlert()
        alert.messageText = "Enable Closed-Lid Mode?"
        alert.informativeText = """
        To keep your Mac awake even with the lid closed, NoSleep Pro needs a one-time \
        permission to control system sleep.

        You'll be asked for your password once. NoSleep Pro installs a single, tightly-scoped \
        rule that only ever runs "pmset disablesleep" — nothing else — so future toggles are \
        instant. You can remove it anytime from the menu.

        Your Mac is already being kept awake while the lid is open.
        """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else {
            // Declined — stop offering closed-lid mode until they re-enable it from the menu,
            // so a left-click or timer pick doesn't re-nag on every activation.
            lidCloseMode = false
            return
        }

        lidSetupInFlight = true
        installHelper { [weak self] ok in
            guard let self else { return }
            self.lidSetupInFlight = false
            if ok, self.isActive, self.lidCloseMode {
                self.lidCloseEngaged = self.runSudoN(disable: true)
            }
            if !ok {
                let fail = NSAlert()
                fail.messageText = "Couldn't Enable Closed-Lid Mode"
                fail.informativeText = "Your Mac is still being kept awake while the lid is open. You can try again anytime from the menu."
                fail.alertStyle = .warning
                fail.runModal()
            }
            self.onChange?()
        }
    }

    // MARK: - Privileged helper install / uninstall

    /// Install the password-less `sudoers` drop-in via a single native admin prompt.
    func installHelper(completion: @escaping (Bool) -> Void) {
        // Capture the *original* user — the script runs as root, so `id -un` would be wrong.
        // Require the whole name to already be safe ASCII; bail rather than install a rule
        // for a *different* (filtered) name that `sudo -n` would then never match.
        let user = NSUserName()
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !user.isEmpty, user.unicodeScalars.allSatisfy(allowed.contains) else {
            completion(false); return
        }

        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        let script = """
        #!/bin/sh
        set -e
        tmp=$(mktemp /tmp/nsp.XXXXXX)
        printf '%s\\n' '# NoSleep Pro — allow toggling system sleep without a password' '\(rule)' > "$tmp"
        chmod 0440 "$tmp"
        if /usr/sbin/visudo -cf "$tmp" >/dev/null 2>&1; then
          /bin/cp "$tmp" /etc/sudoers.d/nosleeppro
          /usr/sbin/chown root:wheel /etc/sudoers.d/nosleeppro
          /bin/chmod 0440 /etc/sudoers.d/nosleeppro
          /bin/rm -f "$tmp"
          echo NOSLEEPPRO_OK
        else
          /bin/rm -f "$tmp"
          echo NOSLEEPPRO_BAD
          exit 1
        fi
        """
        runAdminScript(script, marker: "NOSLEEPPRO_OK") { [weak self] ok in
            if ok { self?.defaults.set(true, forKey: Key.helperInstalled) }
            completion(ok)
        }
    }

    /// Remove the helper and restore normal sleep. Prompts for admin once.
    func uninstallHelper(completion: @escaping (Bool) -> Void) {
        let script = """
        #!/bin/sh
        /usr/bin/pmset disablesleep 0 >/dev/null 2>&1 || true
        /bin/rm -f /etc/sudoers.d/nosleeppro
        echo NOSLEEPPRO_OK
        """
        runAdminScript(script, marker: "NOSLEEPPRO_OK") { [weak self] ok in
            guard let self else { completion(ok); return }
            if ok {
                self.defaults.set(false, forKey: Key.helperInstalled)
                self.lidCloseEngaged = false
                self.onChange?()
            }
            completion(ok)
        }
    }

    /// Write `script` to a temp file and execute it once with administrator privileges
    /// (the secure system password panel). Runs off the main thread; completion is on main.
    private func runAdminScript(_ script: String, marker: String, completion: @escaping (Bool) -> Void) {
        let path = NSTemporaryDirectory() + "nosleeppro_\(UUID().uuidString).sh"
        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let apple = "do shell script \"/bin/sh \\\"\(path)\\\"\" with administrator privileges"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", apple]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            var ok = false
            do {
                try p.run()
                // Drain the pipe *before* waiting so a large write can never deadlock us.
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                ok = (p.terminationStatus == 0) && text.contains(marker)
            } catch {
                ok = false
            }
            try? FileManager.default.removeItem(atPath: path)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: - Auto-off timer

    private func scheduleExpiry(minutes: Int?) {
        cancelTimer()
        guard let minutes, minutes > 0 else {
            expiresAt = nil
            selectedTimerMinutes = nil
            return
        }
        selectedTimerMinutes = minutes
        let interval = TimeInterval(minutes * 60)
        expiresAt = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.deactivate() }
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short   // locale-aware, e.g. "3:45 PM" or "15:45"
        f.dateStyle = .none
        return f
    }()
}
