import AppKit
import Foundation
import Testing
import TansuCore
@testable import TansuUI

enum TestPaths {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let repositoryRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
}

@Suite struct StringCatalogTests {
    static let designFolder = TestPaths.packageRoot.appendingPathComponent("Sources/TansuUI/Design")
    static let catalogFile = TestPaths.packageRoot.appendingPathComponent("Sources/TansuUI/Resources/Localizable.xcstrings")

    /// Strings.swift and its extensions (Strings+Profiles.swift…).
    static func stringsFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: designFolder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Strings") && $0.pathExtension == "swift" }
    }

    /// Every `String(localized: "…"` key of the Strings files.
    static func codeKeys() throws -> Set<String> {
        var keys: Set<String> = []
        for file in try stringsFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            keys.formUnion(text.matches(of: /String\(localized: "((?:[^"\\]|\\.)*)"/).map {
                String($0.output.1).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            })
        }
        return keys
    }

    static func catalog() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: catalogFile)) as? [String: Any] ?? [:]
    }

    static func catalogKeys() throws -> Set<String> {
        Set((try catalog()["strings"] as? [String: Any] ?? [:]).keys)
    }

    @Test func thereAreStrings() throws {
        #expect(try Self.codeKeys().count > 150)
    }

    @Test func everyStringIsInTheCatalog() throws {
        let missing = try Self.codeKeys().subtracting(Self.catalogKeys())
        #expect(missing.isEmpty, "run node scripts/sync-strings.mjs: missing \(missing.sorted())")
    }

    @Test func theCatalogHasNoStaleKeys() throws {
        let stale = try Self.catalogKeys().subtracting(Self.codeKeys())
        #expect(stale.isEmpty, "run node scripts/sync-strings.mjs: stale \(stale.sorted())")
    }

    @Test func theSourceLanguageIsEnglish() throws {
        #expect(try Self.catalog()["sourceLanguage"] as? String == "en")
    }

    @Test func noVisibleStringHasADash() throws {
        for key in try Self.codeKeys() {
            #expect(!key.contains("\u{2014}") && !key.contains("\u{2013}"), "dash in \(key)")
        }
    }

    /// A literal % outside a format specifier would be read as one by `String(format:)`.
    @Test func percentSignsAreFormatSpecifiersOnly() throws {
        for key in try Self.codeKeys() {
            let stripped = key.replacingOccurrences(of: "%lld", with: "").replacingOccurrences(of: "%@", with: "")
            #expect(!stripped.contains("%"), "stray % in \(key)")
        }
    }

    @Test func formatStringsFillIn() {
        #expect(Strings.iconCount(1) == "1 icon")
        #expect(Strings.iconCount(3) == "3 icons")
        #expect(Strings.smartSortFound(17) == "Tansu found 17 icons. Here is a tidier menu bar.")
        #expect(Strings.roomUsed(412, of: 664) == "412 of 664 points")
        #expect(Strings.readyBody(search: "⌃⌥⌘Space").hasSuffix("⌃⌥⌘Space."))
        #expect(Strings.categoryName(.files) == "Files & Cloud")
    }

    /// The product speaks of icons, not emoji: emoji are one option among three.
    @Test func theWelcomeDoesNotSellEmoji() {
        for text in [Strings.welcomeBody, Strings.smartSortHint, Strings.readyBody(search: "x"), Strings.readyBodyWithoutShortcut] {
            #expect(!text.lowercased().contains("emoji"), "\(text)")
        }
    }
}

@MainActor
@Suite struct SymbolLibraryTests {
    @Test func everySymbolExistsOnThisMac() {
        let missing = SymbolLibrary.allSymbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "unknown symbols: \(missing)")
    }

    @Test func noSymbolIsListedTwice() {
        let all = SymbolLibrary.allSymbols
        #expect(Set(all).count == all.count)
        #expect(all.count > 300)
    }

    @Test func everyCategoryStartsWithALibraryIcon() {
        for category in CategoryID.allCases {
            #expect(SymbolLibrary.allSymbols.contains(category.symbol) || NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func everySectionHasATranslatedTitle() {
        for section in SymbolLibrary.sections {
            #expect(!Strings.symbolSection(section.title).isEmpty)
        }
    }

    @Test func searchMatchesPartsOfNamesAndThemes() {
        let lock = SymbolLibrary.search("lock").flatMap(\.symbols)
        #expect(lock.contains("lock.fill"))
        #expect(lock.contains("lock.shield"))
        let theme = SymbolLibrary.search("music")
        #expect(theme.contains { $0.title == "Music & Video" })
        #expect(SymbolLibrary.search("").count == SymbolLibrary.sections.count)
        #expect(SymbolLibrary.search("zzzz").isEmpty)
    }

    @Test func anExactSymbolOutsideTheLibraryIsOffered() {
        let found = SymbolLibrary.search("figure.walk")
        #expect(found.first?.symbols == ["figure.walk"])
    }

    @Test func noAppleLogo() {
        #expect(!SymbolLibrary.allSymbols.contains { $0.contains("apple.logo") })
    }
}

@Suite struct ThemeTests {
    static let tokensFile = TestPaths.repositoryRoot.appendingPathComponent("brand/tokens/tokens.json")

    static func token(_ group: String, _ name: String) throws -> String {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: tokensFile)) as? [String: Any]
        let color = json?["color"] as? [String: Any]
        let entry = (color?[group] as? [String: Any])?[name] as? [String: Any]
        return try #require(entry?["$value"] as? String)
    }

    @Test func themeColorsMatchTheBrandTokens() throws {
        let pairs: [(RGBA, String, String)] = [
            (Theme.night, "dark", "night"), (Theme.lacquer, "dark", "lacquer"), (Theme.rice, "dark", "rice"),
            (Theme.ash, "dark", "ash"), (Theme.honey, "dark", "honey"), (Theme.ember, "dark", "ember"),
            (Theme.paper, "light", "paper"), (Theme.ink, "light", "ink"), (Theme.graphite, "light", "graphite"),
            (Theme.deepHoney, "light", "deep-honey"), (Theme.hairline, "light", "hairline"),
        ]
        for (color, group, name) in pairs {
            #expect(color.hex == (try Self.token(group, name)).uppercased(), "\(name)")
        }
    }

    @Test func textPairsAreLegible() {
        #expect(Theme.rice.contrast(with: Theme.night) >= 4.5)
        #expect(Theme.ash.contrast(with: Theme.night) >= 4.5)
        #expect(Theme.honey.contrast(with: Theme.night) >= 4.5)
        #expect(Theme.ink.contrast(with: Theme.paper) >= 4.5)
        #expect(Theme.graphite.contrast(with: Theme.paper) >= 4.5)
        #expect(Theme.deepHoney.contrast(with: Theme.paper) >= 4.5)
    }
}
