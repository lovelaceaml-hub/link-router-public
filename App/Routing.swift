import Foundation

// Where a link goes: an app, plus a Chrome profile folder when the app is Chrome.
struct Target: Codable, Equatable {
    var bundleID: String
    var profile: String?
}

// Sends links for a host (and its subdomains) to a fixed target.
struct Rule: Codable {
    var host: String
    var target: Target
}

struct ChromeProfile: Codable {
    var dir: String
    var name: String
    var email: String
}

struct Config: Codable {
    var defaultTarget: Target
    var rules: [Rule]
    var removeTrackingParameters: Bool
    // Copy of Chrome's profile list, used when macOS blocks reading Chrome's own files.
    var chromeProfiles: [ChromeProfile]?

    static let chrome = "com.google.Chrome"
    static let standard = Config(
        defaultTarget: Target(bundleID: chrome, profile: nil),
        rules: [],
        removeTrackingParameters: true,
        chromeProfiles: nil
    )
}

enum Router {
    static func target(for url: URL, config: Config) -> Target {
        guard let host = url.host?.lowercased() else { return config.defaultTarget }
        for rule in config.rules {
            let h = rule.host.lowercased()
            if host == h || host.hasSuffix("." + h) { return rule.target }
        }
        return config.defaultTarget
    }

    // Common ad and tracking parameters that never change what a page shows.
    static let trackingKeys: Set<String> = [
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "fbclid", "msclkid", "mc_eid", "mc_cid",
        "igshid", "igsh", "si", "yclid", "twclid", "ttclid", "li_fat_id", "_hsenc", "_hsmi",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "spm", "ref_src",
    ]

    static func clean(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems, !items.isEmpty else { return url }
        let kept = items.filter { item in
            let key = item.name.lowercased()
            return !key.hasPrefix("utm_") && !trackingKeys.contains(key)
        }
        if kept.count == items.count { return url }
        parts.queryItems = kept.isEmpty ? nil : kept
        return parts.url ?? url
    }
}

enum ConfigStore {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LinkRouterPortable/config.json")

    static func load() -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // First run: write the standard settings so Edit Rules… has a file to open.
            save(.standard)
            return .standard
        }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            // A typo from Edit Rules… must not wipe the rules and profile list. Keep a copy of the
            // file as it is and use the standard settings until it is fixed; save() refuses meanwhile.
            let copy = url.deletingPathExtension().appendingPathExtension("invalid.json")
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
            NSLog("LinkRouter: config.json has a mistake (%@); using standard settings, copy kept at %@",
                  String(describing: error), copy.path)
            return .standard
        }
    }

    // True when config.json exists but cannot be read as settings.
    static func isBroken() -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: url))) == nil
    }

    static func save(_ config: Config) {
        if isBroken() {
            NSLog("LinkRouter: not saving settings until the mistake in config.json is fixed")
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(config).write(to: url, options: .atomic)
    }
}
