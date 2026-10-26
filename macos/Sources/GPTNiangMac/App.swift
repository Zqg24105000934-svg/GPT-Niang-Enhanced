import AppKit
import SwiftUI
import Combine
import GPTNiangCore
import Darwin
import os

@main
struct GPTNiangEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: WidgetModel!
    private var updater: NativeUpdater!
    private var completion: CompletionNotificationController!
    private var languageSubscription: AnyCancellable?
    private var preferenceSubscriptions = Set<AnyCancellable>()
    private var inertiaTimer: Timer?
    private var inertiaState: PetInertia?
    private var lastInertiaTime: TimeInterval = 0
    private var suspended = false
    private var trackingMenus = 0
    private var panel: WidgetPanel!
    private var settingsWindow: NSWindow?
    private var speedWindow: NSWindow?
    private let speedStore = ThreadSpeedStore()
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lockDescriptor: Int32 = -1
    private var hostRect: CGRect?
    private var lastHostNumber: Int?
    private var selectedHostNumber: Int?
    private var hostApplication: NSRunningApplication?
    private var cadence = WindowFollowCadence()
    private var wasCodexFrontmost = false
    private var followPolicy = WindowFollowPolicy()
    private var hostGeometry = HostGeometryStability()
    private var frontmostScreen: CGRect?
    private var focusDisplay = FocusDisplayTracker()
    private var focusMouseMonitor: Any?
    private var forceHostDiscovery = true
    private var needsHostOrder = true
    private var stageManagerEnabled = false
    private var dragOrigin: CGPoint?
    private var previousFollow: Bool?
    private var dragEvents = 0
    private var diagnosticsURL: URL?
    private let logger = Logger(subsystem: "io.github.t7moris.GPTNiangMac", category: "window")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        func argument(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let dataDirectory = argument("--data-dir").map { URL(fileURLWithPath: $0, isDirectory: true) } ??
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\(enhancedBuild ? "GPTNiangEnhanced" : "GPTNiangUsage")", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        lockDescriptor = Darwin.open(dataDirectory.appendingPathComponent("gui.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            // Reopening the app must not create a second character or quota worker.
            NSApp.terminate(nil); return
        }
        if Bundle.main.bundleURL.pathExtension == "app" && !enhancedBuild {
            do {
                if try NativeUpdater.recoverBeforeLaunch(data: dataDirectory) { NSApp.terminate(nil); return }
            } catch { logger.error("Update recovery: \(error.localizedDescription, privacy: .public)") }
        }
        guard let resources = Bundle.main.resourceURL else { NSApp.terminate(nil); return }
        diagnosticsURL = argument("--diagnostics").map { URL(fileURLWithPath: $0) }
        model = WidgetModel(dataDirectory: dataDirectory, resources: resources)
        updater = NativeUpdater(data: dataDirectory, idle: { [weak self] in
            guard let self else { return false }
            return self.dragOrigin == nil && self.trackingMenus == 0 && self.settingsWindow?.isVisible != true &&
                self.speedWindow?.isVisible != true && self.model.updateIdle
        }, workerReady: { [weak self] version in
            self?.model.workerHealthy(version: version) == true
        }, terminate: { NSApp.terminate(nil) })
        panel = WidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 378, height: 378),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = model.text("GPT 娘額度掛件")
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.isFloatingPanel = false; panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        // Join the host's Stage Manager set/fullscreen space without becoming a
        // separate managed window that slides through the switching animation.
        panel.collectionBehavior = WindowFollowPolicy.collectionBehavior
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.install(NSHostingView(rootView: WidgetView(model: model, onDrag: { [weak self] in self?.drag($0) }, onSettings: { [weak self] in self?.showSettings() }, onContextMenu: { [weak self] event, view in self?.showContextMenu(event, view: view) }, onRelease: { [weak self] in self?.startInertia($0) })))
        completion = CompletionNotificationController(model: model, panel: panel)
        buildMenu()
        languageSubscription = model.$language.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.buildMenu(); self?.localizeWindowTitles() }
        }
        model.$enhancements.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.stopInertia(); self.model.savePreferences(); self.configureTimer(); self.updateWindow()
        }.store(in: &preferenceSubscriptions)
        model.$followCodex.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.stopInertia(); self?.configureTimer(); self?.updateWindow()
        }.store(in: &preferenceSubscriptions)
        model.start()
        observeWorkspace()
        updateWindow()
        configureTimer()
        if args.contains("--speed") { showSpeed() }
        updater.start()
        logger.info("macOS widget launched")
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let focusMouseMonitor { NSEvent.removeMonitor(focusMouseMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate(); stopInertia(); completion?.stop(); updater?.stop(); model?.stop(); speedStore.stop()
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again must recover a hidden or click-through pet.
        if model != nil, model.userHidden || model.enhancements.clickThrough { restorePet() }
        return true
    }
    private var enhancedBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "GPTNiangEnhanced") as? Bool == true }
    private func configureTimer() {
        timer?.invalidate()
        model.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let interval = PetCadence.windowInterval(following: model.followCodex, visible: !model.userHidden && !suspended, economy: model.effectivePerformance == .economy)
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateWindow() }
        }
        next.tolerance = interval * 0.2
        RunLoop.main.add(next, forMode: .common); timer = next
    }
    func menuWillOpen(_ menu: NSMenu) {
        trackingMenus += 1
        for item in menu.items {
            model.audio.updateNativeItem(item)
            if item.action == #selector(toggleCompletion) { item.state = model.completionEnabled ? .on : .off }
            if item.action == #selector(showQuota) { item.title = model.text(model.bubble && model.message == nil ? "收起气泡" : "查看額度") }
            if item.action == #selector(toggleHidden) { item.title = model.userHidden ? "显示桌宠" : "隐藏桌宠（节能）" }
            if item.action == #selector(toggleLocked) { item.state = model.enhancements.positionLocked ? .on : .off }
            if item.action == #selector(toggleThrough) { item.state = model.enhancements.clickThrough ? .on : .off }
        }
    }
    func menuDidClose(_ menu: NSMenu) { trackingMenus = max(0, trackingMenus - 1) }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window === speedWindow { speedStore.stop() }
            if window === settingsWindow || window === speedWindow { NSApp.setActivationPolicy(.accessory) }
        }
    }
    private func localizeWindowTitles() {
        panel?.title = model.text("GPT 娘額度掛件")
        settingsWindow?.title = model.text("GPT 娘設定")
        speedWindow?.title = model.text("GPT 娘 · 聊天速度")
    }
    private func buildMenu() {
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }
        statusItem?.button?.image = NSImage(systemSymbolName: enhancedBuild ? "pawprint.fill" : "sparkles", accessibilityDescription: enhancedBuild ? "GPT 娘增强版" : model.text("GPT 娘"))
        statusItem?.button?.toolTip = enhancedBuild ? "GPT 娘增强版 · 显示、穿透与设置" : model.text("GPT 娘")
        let menu = NSMenu(); menu.delegate = self
        for (title, selector) in [(model.text("GPT 娘 · Codex 額度"), #selector(showQuota)), (model.text("刷新額度"), #selector(refresh)), (model.text("來一句語錄"), #selector(quote)), (model.text("聊天速度…"), #selector(showSpeed))] {
            let item = NSMenuItem(title: model.text(title), action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let playItem = NSMenuItem(title: "陪她玩", action: nil, keyEquivalent: "")
        let playMenu = NSMenu(title: "陪她玩"); playMenu.delegate = self
        for reaction in PetReaction.allCases {
            let item = NSMenuItem(title: reaction.title, action: #selector(petInteraction(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = reaction.rawValue
            playMenu.addItem(item)
        }
        playMenu.addItem(.separator())
        let stopPlay = NSMenuItem(title: "停止互动", action: #selector(stopPetInteraction), keyEquivalent: "")
        stopPlay.target = self; playMenu.addItem(stopPlay)
        playItem.submenu = playMenu; menu.addItem(playItem)
        for (title, selector) in [("跳一下", #selector(hop)), ("锁定位置", #selector(toggleLocked)), ("鼠标穿透", #selector(toggleThrough)), ("隐藏桌宠（节能）", #selector(toggleHidden)), ("恢复显示与操作", #selector(restorePet))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        menu.addItem(.separator())
        let reminder = NSMenuItem(title: model.text("回答结束提醒"), action: #selector(toggleCompletion), keyEquivalent: ""); reminder.target = self; menu.addItem(reminder)
        let audio = NSMenuItem(title: model.text("声音与点击"), action: nil, keyEquivalent: "")
        audio.submenu = model.audio.nativeMenu(target: self, action: #selector(audioAction(_:)), delegate: self); menu.addItem(audio)
        let settings = NSMenuItem(title: model.text("設定…"), action: #selector(showSettings), keyEquivalent: ","); settings.target = self; menu.addItem(settings)
        if !enhancedBuild {
            let update = NSMenuItem(title: model.text("檢查更新…"), action: #selector(checkUpdate), keyEquivalent: ""); update.target = self; menu.addItem(update)
        }
        let quit = NSMenuItem(title: model.text("退出 GPT 娘"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(quit)
        statusItem?.menu = menu
        let main = NSMenu()
        let appMenu = NSMenuItem()
        let applicationMenu = NSMenu(title: model.text("GPT 娘")); applicationMenu.delegate = self
        for item in menu.items {
            if item.isSeparatorItem { applicationMenu.addItem(.separator()); continue }
            let copy = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.keyEquivalent)
            copy.target = item.target; copy.representedObject = item.representedObject
            copy.submenu = item.submenu?.copy() as? NSMenu; applicationMenu.addItem(copy)
        }
        appMenu.submenu = applicationMenu; main.addItem(appMenu)
        let editItem = NSMenuItem(title: model.text("編輯"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: model.text("編輯"))
        for (title, selector, key) in [(model.text("復原"), Selector(("undo:")), "z"), (model.text("剪下"), #selector(NSText.cut(_:)), "x"), (model.text("複製"), #selector(NSText.copy(_:)), "c"), (model.text("貼上"), #selector(NSText.paste(_:)), "v"), (model.text("全選"), #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: model.text(title), action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    private func showContextMenu(_ event: NSEvent, view: NSView) {
        guard let menu = statusItem?.menu?.copy() as? NSMenu else { return }
        menu.delegate = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
    @objc private func audioAction(_ item: NSMenuItem) {
        guard let command = item.representedObject as? [String], command.count == 2 else { return }
        model.audio.perform(command[0], slot: AudioSlot(rawValue: command[1]))
    }
    @objc private func toggleCompletion() { model.completionEnabled.toggle(); model.savePreferences() }
    @objc private func toggleLocked() { stopInertia(); model.enhancements.positionLocked.toggle(); model.savePreferences() }
    @objc private func toggleThrough() { model.enhancements.clickThrough.toggle(); model.savePreferences(); updateWindow() }
    @objc private func toggleHidden() { stopInertia(); model.stopPetInteraction(); model.userHidden.toggle(); model.hideBubble(); configureTimer(); updateWindow() }
    @objc private func petInteraction(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let reaction = PetReaction(rawValue: raw) else { return }
        stopInertia(); model.userHidden = false; configureTimer(); updateWindow(); model.interact(reaction)
    }
    @objc private func stopPetInteraction() { model.stopPetInteraction() }
    @objc private func restorePet() { stopInertia(); model.resetPosition(); model.enhancements.opacity = 1; model.savePreferences(); configureTimer(); updateWindow() }
    @objc private func hop() { model.userHidden = false; configureTimer(); updateWindow(); model.hop() }
    @objc private func showQuota() { model.userHidden = false; configureTimer(); model.toggleQuota(); updateWindow() }
    @objc private func refresh() { model.refresh() }
    @objc private func quote() { model.showQuote() }
    @objc private func checkUpdate() { showSettings(); updater.check(manual: true) }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = model.text("GPT 娘設定"); window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: SettingsView(model: model, updater: updater))
            window.center(); settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func showSpeed() {
        if speedWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = model.text("GPT 娘 · 聊天速度"); window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: ThreadSpeedView(store: speedStore, model: model)); window.center(); speedWindow = window
        }
        speedStore.start(model: model)
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        speedWindow?.makeKeyAndOrderFront(nil)
    }
    private func observeWorkspace() {
        recordFocusDisplay()
        // Desktop clicks can switch Stage Manager sets without activating a
        // different app. Mouse-only monitoring needs no keyboard/accessibility
        // access and does not consume or alter the user's click.
        focusMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.recordFocusDisplay()
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleepPet), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(sleepPet), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(wakePet), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(wakePet), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(spaceChanged(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(applicationChanged(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(spaceChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    @objc private func sleepPet() { suspended = true; stopInertia(); configureTimer(); updateWindow() }
    @objc private func wakePet() { suspended = false; configureTimer(); updateWindow() }
    @objc private func powerChanged() { configureTimer() }
    private func recordFocusDisplay() {
        focusDisplay.recordInteraction(at: NSEvent.mouseLocation, screens: NSScreen.screens.map(\.frame))
        forceHostDiscovery = true
    }
    private func readStageManager() {
        // Read the system setting; never change Stage Manager or the user's Spaces.
        stageManagerEnabled = (CFPreferencesCopyAppValue("GloballyEnabled" as CFString,
            "com.apple.WindowManager" as CFString) as? Bool) ?? false
    }
    private func hideFollowingPanel() {
        needsHostOrder = true; forceHostDiscovery = true
        // A host hide/quit event must not cut short an active background notice.
        // Its controller retains the existing deadline and restores the layer;
        // the ordinary follow tick can then hide the unavailable host's panel.
        guard !completion.temporaryTopmost else { return }
        if panel.isVisible { panel.orderOut(nil) }
        selectedHostNumber = nil; lastHostNumber = nil; hostRect = nil
        let now = ProcessInfo.processInfo.systemUptime
        if cadence.presence(now: now, visible: false) { model.writePresence(visible: false) }
    }
    @objc private func spaceChanged(_ notification: Notification) {
        guard model.followCodex else { return }
        // The notification covers every display. A Space change on another
        // monitor must not hide an unchanged host on this one.
        forceHostDiscovery = true; needsHostOrder = true
        updateWindow()
    }
    @objc private func applicationChanged(_ notification: Notification) {
        if notification.name == NSWorkspace.didActivateApplicationNotification { recordFocusDisplay() }
        guard model.followCodex else { return }
        forceHostDiscovery = true; needsHostOrder = true
        readStageManager()
        let changed = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let isHost = changed?.bundleIdentifier == "com.openai.codex"
        let hostUnavailable = isHost && [NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification].contains(notification.name)
        if hostUnavailable {
            hideFollowingPanel()
        } else {
            // Check the newly active window's display, instead of treating any
            // application deactivation as a reason to hide all companions.
            updateWindow()
        }
    }
    private func codexWindow(now: TimeInterval, frontmost: Bool) -> (CGRect, Int)? {
        let discover = cadence.discover(now: now, force: forceHostDiscovery || (frontmost && !wasCodexFrontmost))
        if discover {
            forceHostDiscovery = false
            readStageManager()
            hostApplication = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first
        }
        let activeApp = NSWorkspace.shared.frontmostApplication
        let companionActive = activeApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        guard let app = hostApplication, !app.isTerminated, !app.isHidden else { return nil }
        let options: CGWindowListOption = discover ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionIncludingWindow]
        let windowID: CGWindowID? = discover ? kCGNullWindowID : selectedHostNumber.map { CGWindowID($0) }
        guard let windowID,
              let windows = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] else { return nil }
        let screens = NSScreen.screens.map(\.frame)
        if discover {
            var frontmostFrame: CGRect?
            for window in windows {
                guard (window[kCGWindowOwnerPID as String] as? Int32) == activeApp?.processIdentifier,
                      (window[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                      let width = bounds["Width"], let height = bounds["Height"], width >= 200, height >= 120 else { continue }
                let frame = WidgetPlacement.appKitRect(quartz: CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                    width: width, height: height), mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
                if WindowFollowPolicy.screen(for: frame, screens: screens) != nil {
                    frontmostFrame = frame; break
                }
            }
            frontmostScreen = focusDisplay.resolve(window: frontmostFrame, screens: screens)
        }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowIsOnscreen as String] as? Bool) == true,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"], width >= 480, height >= 300,
                  let number = window[kCGWindowNumber as String] as? Int else { continue }
            let quartz = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: width, height: height)
            let frame = WidgetPlacement.appKitRect(quartz: quartz, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
            let mouseDraggingHost = frontmost && (NSEvent.pressedMouseButtons & 1) != 0
            guard WindowFollowPolicy.usableHost(frame, screens: screens,
                allowClipped: mouseDraggingHost || hostGeometry.isTracking(number: number)) else { continue }
            let hostScreen = WindowFollowPolicy.screen(for: frame, screens: screens)
            let otherScreenActive = frontmostScreen != nil && hostScreen != nil && frontmostScreen != hostScreen
            guard followPolicy.mayFollow(stageManager: stageManagerEnabled, hostActive: frontmost,
                companionActive: companionActive, frontmostOnAnotherScreen: otherScreenActive) else { continue }
            selectedHostNumber = number
            guard hostGeometry.accept(number: number, frame: frame, screens: screens, now: now,
                mouseDraggingHost: mouseDraggingHost) else { return nil }
            if discover {
                let order = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
                if WindowFollowPolicy.needsOrdering(host: number, panel: panel.windowNumber, frontToBack: order) {
                    needsHostOrder = true
                }
            }
            // A full list is front-to-back: choose the current foremost Codex
            // window rather than retaining an older, still-visible window.
            selectedHostNumber = number
            return (frame, number)
        }
        selectedHostNumber = nil
        return nil
    }
    private func updateWindow() {
        guard model != nil, panel != nil else { return }
        panel.ignoresMouseEvents = model.enhancements.clickThrough
        if panel.alphaValue != model.enhancements.opacity { panel.alphaValue = model.enhancements.opacity }
        if model.userHidden || suspended {
            if model.petReaction != nil { model.stopPetInteraction() }
            if panel.isVisible { panel.orderOut(nil) }
            if model.visualsActive { model.visualsActive = false; model.writePresence(visible: false) }
            return
        }
        if completion.temporaryTopmost {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
            let busy = trackingMenus > 0 || dragOrigin != nil || model.interactionActive || model.audio.busy || settingsWindow?.isVisible == true || speedWindow?.isVisible == true || (model.bubble && !model.isCompletionMessage)
            completion.tick(codexFrontmost: front, busy: busy)
            if completion.temporaryTopmost {
                // Show the whole existing canvas for the temporary reminder.
                _ = panel.place(panel.placementFrame, clippedTo: nil)
                if cadence.presence(now: ProcessInfo.processInfo.systemUptime, visible: true) { model.writePresence(visible: true) }
                return
            }
        }
        if let previousFollow, previousFollow != model.followCodex {
            if !model.followCodex && model.desktopLeft == nil {
                model.desktopLeft = panel.placementFrame.minX; model.desktopBottom = panel.placementFrame.minY
            }
            dragOrigin = nil; model.savePreferences()
            forceHostDiscovery = true; needsHostOrder = true
        }
        previousFollow = model.followCodex
        var size = CGSize(width: model.canvasSize.width * model.scale, height: model.canvasSize.height * model.scale)
        let now = ProcessInfo.processInfo.systemUptime
        let codexFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
        let host = model.followCodex ? codexWindow(now: now, frontmost: codexFrontmost) : nil
        var visible = false
        if model.followCodex {
            let companionActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            let level = WindowFollowPolicy.level(hostActive: codexFrontmost, companionActive: companionActive)
            if panel.level != level { panel.level = level; needsHostOrder = true }
            if let (rect, number) = host {
                hostRect = rect
                let desired: CGRect? = dragOrigin == nil
                    ? WidgetPlacement.followFrame(host: rect, size: size, x: model.x, y: model.y)
                    : panel.placementFrame
                if let desired, panel.place(desired, clippedTo: rect) {
                    if model.displayScale != model.scale { model.displayScale = model.scale }
                    if dragOrigin == nil && (!panel.isVisible || !panel.isOnActiveSpace || needsHostOrder || lastHostNumber != number || (codexFrontmost && !wasCodexFrontmost)) {
                        panel.order(.above, relativeTo: number)
                        needsHostOrder = false
                    }
                    visible = panel.isVisible && panel.isOnActiveSpace
                } else {
                    panel.orderOut(nil)
                }
                lastHostNumber = number; if model.trackingNote != nil { model.trackingNote = nil }
            } else {
                // Never carry a stale panel into the next Stage Manager set or
                // Space. The former 0.75s grace period caused traveling flashes.
                if panel.isVisible { panel.orderOut(nil) }
                lastHostNumber = nil; hostRect = nil; needsHostOrder = true
                let note = model.text("未找到可見的 Codex 主視窗。你仍可關閉跟隨，在桌面顯示掛件。")
                if model.trackingNote != note { model.trackingNote = note }
            }
        } else {
            let level: NSWindow.Level = model.desktopTopmost ? .floating : .normal
            let levelChanged = panel.level != level
            panel.level = level
            let point = CGPoint(x: model.desktopLeft ?? panel.placementFrame.minX, y: model.desktopBottom ?? panel.placementFrame.minY)
            let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.screens.min {
                hypot($0.frame.midX-point.x, $0.frame.midY-point.y) < hypot($1.frame.midX-point.x, $1.frame.midY-point.y)
            } ?? NSScreen.main!
            let area = screen.visibleFrame
            let fitted = min(model.scale, area.width / model.canvasSize.width, area.height / model.canvasSize.height)
            if abs(model.displayScale - fitted) > 0.001 { model.displayScale = fitted }
            size = CGSize(width: model.canvasSize.width * fitted, height: model.canvasSize.height * fitted)
            if dragOrigin == nil {
                model.migrateDesktopPosition(area: area, size: size)
                let defaultFrame = WidgetPlacement.frame(host: area, visibleScreen: area, size: size, x: 1, y: 0)
                let frame = WidgetPlacement.desktopFrame(area: area, size: size,
                    origin: CGPoint(x: model.desktopLeft ?? defaultFrame.minX, y: model.desktopBottom ?? defaultFrame.minY))
                _ = panel.place(frame, clippedTo: nil)
            }
            if !panel.isVisible || levelChanged { panel.orderFrontRegardless() }; visible = true; hostRect = area
        }
        if let area = hostRect {
            let left = panel.placementFrame.midX < area.midX
            if model.facingLeft != left { model.facingLeft = left }
        }
        let completionBusy = trackingMenus > 0 || dragOrigin != nil || model.interactionActive || model.audio.busy || settingsWindow?.isVisible == true || speedWindow?.isVisible == true || (model.bubble && !model.isCompletionMessage)
        completion.tick(codexFrontmost: codexFrontmost, busy: completionBusy)
        if completion.temporaryTopmost { _ = panel.place(panel.placementFrame, clippedTo: nil) }
        wasCodexFrontmost = codexFrontmost
        if model.visualsActive != visible { model.visualsActive = visible }
        if cadence.presence(now: now, visible: visible) { model.writePresence(visible: visible) }
        if let diagnosticsURL, cadence.diagnostics(now: now) {
            let values: [String: Any] = ["visible": panel.isVisible, "followCodex": model.followCodex, "hostFound": host != nil,
                "panelWindow": panel.windowNumber, "onActiveSpace": panel.isOnActiveSpace, "stageManager": stageManagerEnabled,
                "geometryTransition": hostGeometry.transitioning, "windowLevel": panel.level.rawValue,
                "focusScreen": frontmostScreen.map { NSStringFromRect($0) } ?? "",
                "hostFrontmost": codexFrontmost, "collectionBehavior": panel.collectionBehavior.rawValue,
                "hostWindow": host?.1 ?? 0, "frame": NSStringFromRect(panel.frame), "placementFrame": NSStringFromRect(panel.placementFrame), "quotaOK": model.snapshot.ok,
                "queryOK": model.snapshot.queryOk ?? false, "quotaWindowCount": model.snapshot.windows.count,
                "hasMessage": model.message != nil, "bubbleVisible": model.bubble, "scale": model.scale,
                "settingsVisible": settingsWindow?.isVisible ?? false, "speedVisible": speedWindow?.isVisible ?? false, "speedRows": speedStore.rows.count, "dragEvents": dragEvents, "displayScale": model.displayScale,
                "fullBody": model.enhancements.fullBody, "positionLocked": model.enhancements.positionLocked,
                "clickThrough": panel.ignoresMouseEvents, "opacity": panel.alphaValue,
                "performance": model.effectivePerformance.rawValue, "windowTimerInterval": timer?.timeInterval ?? 0,
                "inertiaActive": inertiaTimer != nil, "at": Date().timeIntervalSince1970]
            if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: diagnosticsURL, options: .atomic) }
        }
    }
    private func drag(_ translation: CGSize) {
        guard !model.enhancements.positionLocked else { return }
        if translation != .zero { stopInertia() }
        if translation == .zero {
            if model.followCodex, let area = hostRect {
                let travel = max(0, area.width - panel.placementFrame.width - 24)
                if travel > 0 {
                    if model.x * travel <= 18 { model.x = 0 }
                    else if (1 - model.x) * travel <= 18 { model.x = 1 }
                }
            }
            dragOrigin = nil; return
        }
        dragEvents += 1
        if dragOrigin == nil { dragOrigin = panel.placementFrame.origin }
        guard let origin = dragOrigin else { return }
        let proposed = CGPoint(x: origin.x + translation.width, y: origin.y - translation.height)
        if !model.followCodex {
            let center = CGPoint(x: proposed.x+panel.placementFrame.width/2, y: proposed.y+panel.placementFrame.height/2)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.screens.min {
                hypot($0.frame.midX-center.x, $0.frame.midY-center.y) < hypot($1.frame.midX-center.x, $1.frame.midY-center.y)
            }
            guard let area = screen?.visibleFrame else { return }
            let frame = WidgetPlacement.desktopFrame(area: area, size: panel.placementFrame.size, origin: proposed)
            _ = panel.place(frame, clippedTo: nil); model.desktopLeft = frame.minX; model.desktopBottom = frame.minY
            let left = frame.midX < area.midX
            if model.facingLeft != left { model.facingLeft = left }; hostRect = area
            return
        }
        guard let area = hostRect else { return }
        let insetX = min(12, max(0, area.width - panel.placementFrame.width))
        let insetY = min(12, max(0, area.height - panel.placementFrame.height))
        let usableX = max(0, area.width - panel.placementFrame.width - 24)
        let usableY = max(0, area.height - panel.placementFrame.height - 24)
        if usableX > 0 { model.x = min(1, max(0, (proposed.x - area.minX - insetX) / usableX)) }
        if usableY > 0 { model.y = min(1, max(0, (proposed.y - area.minY - insetY) / usableY)) }
        // Keep the full canvas/grab origin; only the visible viewport may change.
        _ = panel.place(CGRect(x: area.minX + insetX + usableX * model.x,
                               y: area.minY + insetY + usableY * model.y,
                               width: panel.placementFrame.width, height: panel.placementFrame.height), clippedTo: area)
    }
    private func stopInertia() {
        let wasMoving = inertiaTimer != nil
        inertiaTimer?.invalidate(); inertiaTimer = nil; inertiaState = nil
        if wasMoving { model.savePreferences() }
    }
    private func startInertia(_ velocity: CGPoint) {
        stopInertia()
        guard model.enhancements.inertia, !model.enhancements.positionLocked, !model.followCodex,
              !model.userHidden, !suspended, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              hypot(velocity.x, velocity.y) > 40 else { return }
        inertiaState = PetInertia(velocity: velocity)
        lastInertiaTime = ProcessInfo.processInfo.systemUptime
        let next = Timer(timeInterval: model.effectivePerformance == .economy ? 1 / 30 : 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceInertia() }
        }
        RunLoop.main.add(next, forMode: .common); inertiaTimer = next
    }
    private func advanceInertia() {
        guard var state = inertiaState, let area = hostRect, !model.interactionActive,
              !model.enhancements.positionLocked, !model.userHidden, !suspended else { stopInertia(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let point = state.step(origin: panel.placementFrame.origin, size: panel.placementFrame.size, area: area, dt: now - lastInertiaTime)
        lastInertiaTime = now; inertiaState = state
        _ = panel.place(CGRect(origin: point, size: panel.placementFrame.size), clippedTo: nil)
        model.desktopLeft = point.x; model.desktopBottom = point.y
        if state.finished { stopInertia() }
    }
}

private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
