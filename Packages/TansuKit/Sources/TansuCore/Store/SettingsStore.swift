import Foundation

/// Reads and writes Tansu's settings as one JSON value in the preferences (key `settings`).
public final class SettingsStore: @unchecked Sendable {
    /// What `load()` found.
    public enum Outcome: Equatable, Sendable {
        /// Nothing stored yet: the defaults.
        case fresh
        /// The stored settings, clamped to their ranges.
        case loaded
        /// The stored value could not be read: the defaults, and the value is left untouched until the next save.
        case unreadable
        /// The settings come from a newer Tansu: the defaults, and the value is left untouched until the next save.
        case newerVersion(Int)
    }

    // UserDefaults is thread-safe; the store adds no state of its own.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> (settings: TansuSettings, outcome: Outcome) {
        guard let data = defaults.data(forKey: key) else { return (.defaults, .fresh) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (.defaults, .unreadable)
        }
        if let version = object["schemaVersion"] as? Int, version > TansuSettings.currentSchemaVersion {
            return (.defaults, .newerVersion(version))
        }
        guard let settings = try? JSONDecoder().decode(TansuSettings.self, from: data) else {
            return (.defaults, .unreadable)
        }
        return (settings.clamped, .loaded)
    }

    public func save(_ settings: TansuSettings) {
        var stored = settings.clamped
        stored.schemaVersion = TansuSettings.currentSchemaVersion
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets everything: the next launch starts with the welcome.
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
