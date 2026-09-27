import AppKit
import SwiftUI
import TansuCore
import TansuSystem

/// Settings, Behavior (spec 6.3).
struct BehaviorPane: View {
    @Bindable var model: InterfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: Strings.newIcons) {
                Picker("", selection: Binding(get: { model.settings.layout.newIconPolicy }, set: { value in
                    model.update { $0.layout.newIconPolicy = value }
                })) {
                    Text(verbatim: Strings.sortIntoTheirDrawer).tag(NewIconPolicy.sortIntoDrawer)
                    Text(verbatim: Strings.showInMenuBar).tag(NewIconPolicy.menuBar)
                    Text(verbatim: Strings.hideNewIcons).tag(NewIconPolicy.hidden)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .padding(.vertical, 6)
            }
            SettingsGroup {
                SettingRow(title: Strings.openOnHover) {
                    Toggle("", isOn: behavior(\.opensOnHover)).labelsHidden().toggleStyle(.switch)
                }
                if model.settings.behavior.opensOnHover {
                    SettingRow(title: Strings.hoverDelay) {
                        HStack {
                            Slider(value: behavior(\.hoverDelay), in: Behavior.hoverDelayRange).frame(width: 180)
                            Text(verbatim: Strings.seconds(String(format: "%.2g", model.settings.behavior.hoverDelay))).monospacedDigit().frame(width: 44)
                        }
                    }
                }
                SettingRow(title: Strings.returnIconsAfter, note: Strings.returnIconsNote) {
                    HStack {
                        Slider(value: behavior(\.rehideDelay), in: 0...5, step: 0.5).frame(width: 180)
                        Text(verbatim: Strings.seconds(String(format: "%.1f", model.settings.behavior.rehideDelay))).monospacedDigit().frame(width: 44)
                    }
                }
                SettingRow(title: Strings.optionClickShowsEverything) {
                    Toggle("", isOn: behavior(\.showsEverythingWithOption)).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.showTansuIcon, note: Strings.showTansuIconNote) {
                    Toggle("", isOn: behavior(\.showsTansuIcon)).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: Strings.engine) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verbatim: engineDescription).font(.system(size: 13))
                        if model.engineKind == .goldenGate {
                            Text(verbatim: Strings.beta).font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.selection))
                        }
                    }
                    if model.engineKind == .goldenGate {
                        Text(verbatim: Strings.goldenGateSideEffects).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var engineDescription: String {
        switch model.engineKind {
        case .tahoe: Strings.engineTahoe
        case .goldenGate: Strings.engineGoldenGate
        case .demo: Strings.engineDemo
        }
    }

    private func behavior<Value>(_ keyPath: WritableKeyPath<Behavior, Value>) -> Binding<Value> {
        Binding(get: { model.settings.behavior[keyPath: keyPath] }, set: { value in
            model.update { $0.behavior[keyPath: keyPath] = value }
        })
    }
}

/// Settings, Shortcuts (spec 6.3).
struct ShortcutsPane: View {
    @Bindable var model: InterfaceModel

    var body: some View {
        SettingsGroup {
            SettingRow(title: Strings.searchIconsShortcut) {
                ShortcutRecorder(shortcut: shortcut(\.search), problem: problem("search"))
            }
            SettingRow(title: Strings.openAllDrawers) {
                ShortcutRecorder(shortcut: shortcut(\.allDrawer), problem: problem("allDrawer"))
            }
            SettingRow(title: Strings.focusShortcut, note: Strings.focusShortcutNote) {
                ShortcutRecorder(shortcut: shortcut(\.focus), problem: problem("focus"))
            }
        }
    }

    private func shortcut(_ keyPath: WritableKeyPath<Shortcuts, Shortcut?>) -> Binding<Shortcut?> {
        Binding(get: { model.settings.shortcuts[keyPath: keyPath] }, set: { value in
            model.update { $0.shortcuts[keyPath: keyPath] = value }
        })
    }

    private func problem(_ key: String) -> String? {
        model.refusedShortcuts.contains(key) ? Strings.shortcutTaken : nil
    }
}

/// Settings, General (spec 6.3).
struct GeneralPane: View {
    @Bindable var model: InterfaceModel
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup {
                SettingRow(title: Strings.openAtLogin, note: model.loginItemStatus == .needsApproval ? Strings.loginNeedsApproval : nil) {
                    Toggle("", isOn: Binding(get: { model.loginItemStatus == .enabled || model.loginItemStatus == .needsApproval },
                                             set: { model.actions.setOpenAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.accessibility) {
                    HStack(spacing: 10) {
                        Text(verbatim: model.accessibilityTrusted ? Strings.on : Strings.off)
                            .foregroundStyle(model.accessibilityTrusted ? Color.green : Theme.warning)
                        if !model.accessibilityTrusted {
                            Button(Strings.openSystemSettings) {
                                model.actions.requestAccessibility()
                                model.actions.openAccessibilitySettings()
                            }
                            .buttonStyle(PillButtonStyle(.primary))
                        }
                    }
                }
                SettingRow(title: Strings.memory) {
                    Text(verbatim: model.memoryBytes.map { Strings.memoryInUse(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory)) } ?? "")
                        .monospacedDigit().foregroundStyle(Theme.secondaryText)
                }
            }
            SettingsGroup(title: Strings.updates) {
                SettingRow(title: Strings.checkAutomatically) {
                    Toggle("", isOn: Binding(get: { model.automaticUpdates }, set: { model.actions.setAutomaticUpdates($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: Strings.checkForUpdates) {
                    Button(Strings.checkNow) { model.actions.checkForUpdates() }
                        .buttonStyle(PillButtonStyle(.secondary))
                        .disabled(!model.canCheckForUpdates)
                }
            }
            SettingsGroup {
                SettingRow(title: Strings.pauseTansu) {
                    Toggle("", isOn: Binding(get: { model.isShowingEverything }, set: { _ in model.actions.toggleShowEverything() }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            HStack(spacing: 10) {
                Button(Strings.resetLayout) { confirmingReset = true }.buttonStyle(PillButtonStyle(.destructive))
                Spacer()
                Button(Strings.quitTansu) { model.actions.quit() }.buttonStyle(PillButtonStyle(.secondary))
            }
        }
        .confirmationDialog(Strings.resetLayoutQuestion, isPresented: $confirmingReset) {
            Button(Strings.reset, role: .destructive) { model.actions.resetLayout() }
            Button(Strings.cancel, role: .cancel) {}
        }
        .task {
            while !Task.isCancelled {
                model.actions.refreshMemory()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Settings, About (spec 6.3).
struct AboutPane: View {
    let model: InterfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: Strings.appName).font(.system(size: 22, weight: .semibold))
                    Text(verbatim: Strings.tagline).foregroundStyle(Theme.secondaryText)
                    Text(verbatim: Strings.version(model.appVersion)).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
            }
            Text(verbatim: Strings.freeAndOpenSource).font(.system(size: 13))
            HStack(spacing: 10) {
                Link(Strings.website, destination: TansuInfo.website)
                Link(Strings.sourceCode, destination: TansuInfo.repository)
                Link(Strings.reportIssue, destination: TansuInfo.issues)
            }
            .font(.system(size: 13, weight: .medium))
            Text(verbatim: Strings.creditsLine).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            Text(verbatim: Strings.notAffiliated).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
        }
        .padding(18)
        .card()
    }
}
