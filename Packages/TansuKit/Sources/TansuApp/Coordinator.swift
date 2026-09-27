import AppKit
import SwiftUI
import TansuCore
import TansuSystem
import TansuUI

/// Wires the engine, the settings, the menu bar items, the drawers, search and the windows together (spec 8). Every
/// change of the layout saves the settings and asks the engine to make the menu bar match, once per burst of changes.
@MainActor
public final class Coordinator {
    public let interface: InterfaceModel
    /// The app target's way to move Tansu to /Applications (it owns that code).
    public var moveToApplicationsHandler: (() -> Void)?

    private let options: LaunchOptions
    private let store: SettingsStore
    private let engine: MenuBarEngine
    private let directory = AppDirectory()
    private let classifier = Classifier()
    private let statusItems = StatusItemsController()
    private let panels = PanelController()
    private let overlay = TintOverlay()
    private let toast = Toast()
    private let windows = WindowPresenter()
    private let permission = AccessibilityPermission()
    private let appObserver = AppObserver()
    private let displayObserver = DisplayObserver()
    private let loginItem = LoginItem()
    private var shortcuts: ShortcutCenter?
    private var updater: UpdateChecking?

    private var snapshot = MenuBarSnapshot.empty
    private var categories: [IconID: CategoryID] = [:]
    private var mode: LayoutPlanner.Mode = .normal
    private var saved: TansuSettings
    private var pendingApply: Task<Void, Never>?
    private var isApplyingNow = false
    private var needsAnotherApply = false
    private var welcome: WelcomeModel?
    private var backdrop: NSWindow?

    public init(options: LaunchOptions, updater: UpdateChecking?) {
        self.options = options
        self.updater = updater
        // Demo mode never reads or writes the person's settings.
        let defaults = options.demo ? (UserDefaults(suiteName: "ch.rubencatalao.tansu.demo") ?? .standard) : .standard
        if options.demo { defaults.removePersistentDomain(forName: "ch.rubencatalao.tansu.demo") }
        store = SettingsStore(defaults: defaults)
        let loaded = store.load()
        if case .unreadable = loaded.outcome { Log.app.error("settings unreadable: using the defaults") }
        if case .newerVersion(let version) = loaded.outcome { Log.app.error("settings from a newer Tansu (schema \(version))") }
        saved = loaded.settings
        interface = InterfaceModel(settings: loaded.settings)
        engine = EngineFactory.make(demo: options.demo)
        if options.demo { directory.overrides = DemoEngine.directoryOverrides() }
        windows.isQuiet = options.quiet
        panels.isQuiet = options.quiet
    }

    // MARK: Launch

    public func start() async {
        if options.demo, let path = options.backdrop { backdrop = Backdrop.show(imageAt: path) }
        NSApp.mainMenu = MainMenu.make { [weak self] in self?.openSettings(nil) }
        wireActions()
        wireMenuBar()
        shortcuts = ShortcutCenter { [weak self] action in self?.handle(action) }
        permission.onChange = { [weak self] trusted in
            self?.interface.accessibilityTrusted = trusted
            Task { await self?.refresh(apply: true) }
        }
        appObserver.onChange = { [weak self] in Task { await self?.refresh(apply: true) } }
        displayObserver.onChange = { [weak self] in
            guard let self else { return }
            overlay.update(interface.settings.appearance)
            Task { await self.refresh(apply: false) }
        }
        engine.onStatusChange = { [weak self] status in self?.interface.engineStatus = status }
        updater?.start()

        await engine.start()
        interface.engineKind = engine.kind
        interface.engineStatus = engine.status
        interface.accessibilityTrusted = options.demo || permission.isTrusted
        interface.isInApplications = GoldenGateEngine.runsFromApplications()
        interface.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        interface.loginItemStatus = loginItem.status
        interface.automaticUpdates = updater?.automaticallyChecksForUpdates ?? false
        interface.canCheckForUpdates = updater?.canCheckForUpdates ?? false
        applyBehavior()

        await refresh(apply: interface.settings.hasCompletedWelcome)
        if options.demo, options.welcomeStep == nil, interface.settings.layout.drawers.isEmpty {
            // Demo mode starts sorted, so pictures of drawers and Settings have something to show.
            let layout = propose(.purpose)
            interface.update { settings in
                settings.layout = layout
                settings.hasCompletedWelcome = true
            }
        }
        syncChrome()

        if !interface.settings.hasCompletedWelcome || options.welcomeStep != nil {
            showWelcome(step: options.welcomeStep.flatMap(WelcomeModel.Step.init(rawValue:)) ?? .hello)
        }
        if let pane = options.settingsPane { openSettings(pane) }
        if let index = options.openDrawer {
            try? await Task.sleep(for: .milliseconds(500))
            let drawers = interface.settings.layout.drawers
            if index < 0 { openDrawer(.all) } else if drawers.indices.contains(index) { openDrawer(.drawer(drawers[index].id)) }
        }
        if let query = options.search {
            try? await Task.sleep(for: .milliseconds(500))
            openSearch(query: query)
        }
    }

    /// On quit: the menu bar goes back to what macOS would show without Tansu.
    public func shutdown() {
        pendingApply?.cancel()
        panels.close()
        engine.restore()
        statusItems.removeAll()
        overlay.removeAll()
        shortcuts?.unregisterAll()
    }

    // MARK: Reading the menu bar

    /// Scans the menu bar, names every icon, places icons Tansu sees for the first time, and applies the layout if
    /// asked.
    func refresh(apply: Bool) async {
        snapshot = await engine.scan()
        interface.accessibilityTrusted = options.demo || permission.isTrusted
        var rows: [IconRow] = []
        var found: [IconID: CategoryID] = [:]
        for icon in snapshot.icons {
            let bundleID = icon.id.bundleID
            let url = NSRunningApplication(processIdentifier: icon.pid)?.bundleURL
            let info = directory.info(bundleID: bundleID, url: url, fallbackName: icon.ownerName)
            let category: CategoryID
            if icon.kind == .system {
                category = interface.settings.userCategories[bundleID] ?? .system
            } else if options.demo, let demo = DemoEngine.categories[bundleID] {
                category = demo
            } else {
                category = classifier.classify(bundleID: bundleID, name: info.name, appStoreCategory: info.appStoreCategory,
                                               userChoice: interface.settings.userCategories[bundleID])
            }
            found[icon.id] = category
            rows.append(IconRow(
                id: icon.id, name: icon.kind == .system ? icon.displayName : info.name, label: icon.label,
                appName: info.name, appIcon: icon.kind == .system ? SystemIcons.image(for: icon.id) : info.icon,
                category: category, developer: info.developer, kind: icon.kind, isMovable: icon.isMovable, frame: icon.frame))
        }
        categories = found
        interface.icons = rows
        rememberNewIcons()
        updateCapacity()
        syncStatusItems()
        if apply { scheduleApply() }
    }

    /// Icons seen for the first time take the place the new icon policy gives them, and keep it: a later change of
    /// the policy never reshuffles the menu bar.
    private func rememberNewIcons() {
        guard interface.settings.hasCompletedWelcome else { return }
        let newcomers = interface.icons.filter { $0.isMovable && !interface.settings.layout.knows($0.id) }
        guard !newcomers.isEmpty else { return }
        interface.update { settings in
            for row in newcomers {
                settings.layout.assign(row.id, to: settings.layout.placement(of: row.id, category: row.category))
            }
        }
    }

    private func updateCapacity() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        guard let screen else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        interface.hasNotch = hasNotch
        let room: CGFloat
        if hasNotch, let right = screen.auxiliaryTopRightArea {
            room = right.width
        } else {
            // Without a notch, the app menus on the left take roughly half of the bar.
            room = screen.frame.width * 0.5
        }
        var items = interface.menuBarRows.map { NotchCapacity.Item(id: $0.id, width: max($0.frame.width, 24)) }
        let own = interface.settings.layout.drawers.map { NotchCapacity.Item(id: IconID(bundleID: TansuInfo.bundleIdentifier, key: $0.id.uuidString), width: 30) }
        items.append(contentsOf: own)
        if interface.settings.behavior.showsTansuIcon {
            items.append(NotchCapacity.Item(id: IconID(bundleID: TansuInfo.bundleIdentifier, key: "main"), width: 30))
        }
        interface.capacity = NotchCapacity.evaluate(room: room, items: items)
    }

    // MARK: Making the menu bar match

    func scheduleApply(after delay: Duration = .milliseconds(350)) {
        pendingApply?.cancel()
        pendingApply = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.applyNow()
        }
    }

    @discardableResult
    func applyNow() async -> ApplyReport {
        if isApplyingNow {
            needsAnotherApply = true
            return .nothing
        }
        isApplyingNow = true
        defer { isApplyingNow = false }
        var report = ApplyReport.nothing
        repeat {
            needsAnotherApply = false
            let plan = LayoutPlanner.plan(layout: interface.settings.layout, snapshot: snapshot, granularity: engine.granularity,
                                          categories: categories, mode: mode)
            interface.isApplying = true
            report = await engine.apply(plan)
            interface.isApplying = false
            interface.failedMoves = report.failed
            interface.conflicts = plan.conflicts
            if !report.moved.isEmpty { await refresh(apply: false) }
        } while needsAnotherApply
        return report
    }

    // MARK: Menu bar items and chrome

    private func wireMenuBar() {
        statusItems.onOpen = { [weak self] target in self?.openDrawer(target) }
        statusItems.onShowEverything = { [weak self] in
            guard let self, interface.settings.behavior.showsEverythingWithOption else { return }
            toggleShowEverything()
        }
        statusItems.menuFor = { [weak self] target in self?.menu(for: target) ?? NSMenu() }
    }

    private func syncStatusItems() {
        let layout = interface.settings.layout
        var counts: [UUID: Int] = [:]
        for drawer in layout.drawers { counts[drawer.id] = interface.members(of: drawer.id).count }
        statusItems.update(drawers: layout.drawers, counts: counts, showsMain: interface.settings.behavior.showsTansuIcon,
                           isFocusOn: mode == .focus, isShowingEverything: mode == .showEverything)
    }

    private func syncChrome() {
        syncStatusItems()
        overlay.update(interface.settings.appearance)
        registerShortcuts()
    }

    private func applyBehavior() {
        let behavior = interface.settings.behavior
        statusItems.hoverDelay = behavior.opensOnHover ? behavior.hoverDelay : nil
        (engine as? TahoeEngine)?.rehideDelay = behavior.rehideDelay
        (engine as? GoldenGateEngine)?.rehideDelay = behavior.rehideDelay
    }

    private func registerShortcuts() {
        guard let shortcuts else { return }
        let refused = shortcuts.apply(ShortcutCenter.wanted(from: interface.settings))
        interface.refusedShortcuts = Set(refused.map { action in
            switch action {
            case .search: "search"
            case .allDrawer: "allDrawer"
            case .focus: "focus"
            case .drawer(let id): id.uuidString
            }
        })
    }

    private func handle(_ action: ShortcutCenter.Action) {
        switch action {
        case .search: openSearch()
        case .allDrawer: openDrawer(.all)
        case .focus: toggleFocus()
        case .drawer(let id): openDrawer(.drawer(id))
        }
    }

    private func menu(for target: StatusItemsController.Target) -> NSMenu {
        let menu = NSMenu()
        if case .drawer(let id) = target {
            menu.addItem(ActionItem(title: Strings.editDrawerMenuItem) { [weak self] in
                self?.interface.selectedDrawer = id
                self?.openSettings(.drawers)
            })
            menu.addItem(.separator())
        }
        let search = ActionItem(title: Strings.searchIconsMenuItem) { [weak self] in self?.openSearch() }
        menu.addItem(search)
        menu.addItem(ActionItem(title: mode == .showEverything ? Strings.hideThemAgain : Strings.showEveryIcon) { [weak self] in
            self?.toggleShowEverything()
        })
        menu.addItem(ActionItem(title: mode == .focus ? Strings.endFocus : Strings.focus) { [weak self] in self?.toggleFocus() })
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: Strings.settingsMenuItem) { [weak self] in self?.openSettings(nil) })
        if updater != nil {
            menu.addItem(ActionItem(title: Strings.checkForUpdates) { [weak self] in self?.updater?.checkForUpdates() })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: Strings.quitTansu) { NSApp.terminate(nil) })
        return menu
    }

    // MARK: Drawers, search, icons

    func openDrawer(_ target: StatusItemsController.Target) {
        if panels.isOpen, panels.openTarget == target {
            panels.close()
            return
        }
        guard let anchor = statusItems.anchor(for: target) else { return }
        let view = DrawerView(model: interface, target: target, onOpen: { [weak self] id in
            self?.open(id, from: target)
        }, onClose: { [weak self] in self?.panels.close() })
        panels.show(view, under: anchor.appKit, target: target)
        // The drawer shows at once; a fresh scan follows, and the panel updates by itself.
        Task { await refresh(apply: false) }
    }

    func openSearch(query: String = "") {
        if panels.isSearchOpen {
            panels.close()
            return
        }
        let view = SearchView(model: interface, initialQuery: query, onOpen: { [weak self] id in
            guard let self else { return }
            let target: StatusItemsController.Target? = interface.row(id).flatMap { row in
                if case .drawer(let drawer) = interface.placement(of: row) { return .drawer(drawer) }
                return interface.placement(of: row) == .hidden ? .all : nil
            }
            open(id, from: target)
        }, onClose: { [weak self] in self?.panels.close() })
        panels.showCentered(view, width: 560)
    }

    func open(_ id: IconID, from target: StatusItemsController.Target?) {
        panels.close()
        let anchor = target.flatMap { statusItems.anchor(for: $0) }
        Task {
            do {
                try await engine.open(id, anchor: anchor?.windowServer)
            } catch EngineError.personIsBusy {
                // The person kept moving: better not to interfere.
            } catch EngineError.notReady(.needsAccessibility) {
                toast.show(Strings.needsAccessibilityToOpen, near: anchor?.appKit)
            } catch {
                toast.show(Strings.couldNotOpen(interface.row(id)?.name ?? id.bundleID), near: anchor?.appKit)
            }
        }
    }

    func toggleFocus() {
        mode = mode == .focus ? .normal : .focus
        interface.isFocusOn = mode == .focus
        interface.isShowingEverything = false
        syncStatusItems()
        Task { await applyNow() }
    }

    func toggleShowEverything() {
        mode = mode == .showEverything ? .normal : .showEverything
        interface.isShowingEverything = mode == .showEverything
        interface.isFocusOn = false
        syncStatusItems()
        Task { await applyNow() }
    }

    // MARK: Windows

    func openSettings(_ pane: SettingsPane?) {
        panels.close()
        windows.showSettings(model: interface, pane: pane)
    }

    func showWelcome(step: WelcomeModel.Step) {
        let model = WelcomeModel(step: step)
        model.proposal = propose(interface.settings.sortStrategy)
        welcome = model
        windows.showWelcome(model: interface, welcomeModel: model) { [weak self] in self?.finishWelcome() }
    }

    private func finishWelcome() {
        interface.update { $0.hasCompletedWelcome = true }
        welcome = nil
        scheduleApply(after: .milliseconds(50))
    }

    // MARK: Settings changes

    private func settingsChanged(_ settings: TansuSettings) {
        let previous = saved
        saved = settings
        store.save(settings)
        if settings.layout != previous.layout || settings.userCategories != previous.userCategories {
            if settings.userCategories != previous.userCategories {
                Task { await refresh(apply: true) }
            } else {
                syncStatusItems()
                updateCapacity()
                if settings.hasCompletedWelcome { scheduleApply() }
            }
        }
        if settings.appearance != previous.appearance { overlay.update(settings.appearance) }
        if settings.behavior != previous.behavior {
            applyBehavior()
            syncStatusItems()
            updateCapacity()
        }
        if settings.shortcuts != previous.shortcuts || settings.layout.drawers.map(\.shortcut) != previous.layout.drawers.map(\.shortcut) {
            registerShortcuts()
        }
    }

    func propose(_ strategy: SortStrategy) -> TansuCore.Layout {
        let inputs = interface.icons.compactMap { row -> ProposalInput? in
            guard let icon = snapshot.icon(row.id) else { return nil }
            return ProposalInput(icon: icon, category: row.category, developer: row.developer)
        }
        return SmartSort.propose(inputs, strategy: strategy, pinned: interface.settings.pinned, names: Strings.categoryName,
                                 everythingName: Strings.allIcons, previous: interface.settings.layout)
    }

    private func applySmartSort(_ layout: TansuCore.Layout, strategy: SortStrategy) async -> ApplyReport {
        interface.update { settings in
            settings.layout = layout
            settings.sortStrategy = strategy
        }
        pendingApply?.cancel()
        mode = .normal
        interface.isFocusOn = false
        interface.isShowingEverything = false
        syncStatusItems()
        return await applyNow()
    }

    private func resetLayout() {
        store.reset()
        mode = .normal
        let fresh = TansuSettings.defaults
        saved = fresh
        interface.settings = fresh
        interface.isFocusOn = false
        interface.isShowingEverything = false
        syncChrome()
        Task {
            _ = await engine.apply(.showEverything)
            windows.closeAll()
            showWelcome(step: .hello)
        }
    }

    // MARK: Actions for the interface

    private func wireActions() {
        var actions = InterfaceActions()
        actions.updateSettings = { [weak self] settings in self?.settingsChanged(settings) }
        actions.openIcon = { [weak self] id, drawer in self?.open(id, from: drawer.map { .drawer($0) }) }
        actions.propose = { [weak self] strategy in self?.propose(strategy) ?? .empty }
        actions.applySmartSort = { [weak self] layout, strategy in await self?.applySmartSort(layout, strategy: strategy) ?? .nothing }
        actions.requestAccessibility = { [weak self] in self?.permission.request(); self?.permission.waitForGrant() }
        actions.openAccessibilitySettings = { [weak self] in self?.permission.openSettings() }
        actions.moveToApplications = { [weak self] in self?.moveToApplicationsHandler?() }
        actions.setOpenAtLogin = { [weak self] enabled in
            guard let self else { return }
            do { try loginItem.setEnabled(enabled) } catch { Log.app.error("login item: \(error.localizedDescription, privacy: .public)") }
            interface.loginItemStatus = loginItem.status
        }
        actions.setAutomaticUpdates = { [weak self] enabled in
            self?.updater?.automaticallyChecksForUpdates = enabled
            self?.interface.automaticUpdates = enabled
        }
        actions.checkForUpdates = { [weak self] in self?.updater?.checkForUpdates() }
        actions.toggleFocus = { [weak self] in self?.toggleFocus() }
        actions.toggleShowEverything = { [weak self] in self?.toggleShowEverything() }
        actions.resetLayout = { [weak self] in self?.resetLayout() }
        actions.retry = { [weak self] in Task { await self?.engine.start(); await self?.refresh(apply: true) } }
        actions.openSettings = { [weak self] pane in self?.openSettings(pane) }
        actions.finishWelcome = { [weak self] in self?.finishWelcome() }
        actions.showInFinder = { [weak self] id in
            guard let self, let row = interface.row(id),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.id.bundleID) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        actions.refreshMemory = { [weak self] in self?.interface.memoryBytes = MemoryUse.footprintBytes() }
        actions.quit = { NSApp.terminate(nil) }
        interface.actions = actions
    }
}
