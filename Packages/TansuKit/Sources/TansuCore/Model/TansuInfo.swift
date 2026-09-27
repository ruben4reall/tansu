import Foundation

/// Where Tansu lives on the web. The website also serves the update feed.
public enum TansuInfo {
    public static let repository = URL(string: "https://github.com/ruben4reall/tansu")!
    public static let website = URL(string: "https://gettansu.vercel.app")!
    public static let issues = URL(string: "https://github.com/ruben4reall/tansu/issues")!
    public static let bundleIdentifier = "ch.rubencatalao.tansu"
}
