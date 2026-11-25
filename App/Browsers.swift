import AppKit

// One row in the picker or the "Links open in" menu.
struct Choice {
    let title: String
    let detail: String?
    let target: Target
    let icon: NSImage?
}

enum Browsers {
    static let ownBundleID = "org.linkrouter.desktop"
    // Link handlers left out of the picker: not real browsers, or hidden by configuration.
    static let skip: Set<String> = [ownBundleID, "com.sindresorhus.velja",
                                    "com.openai.codex",                // ChatGPT
                                    "com.google.chrome.for.testing"]   // test browser used by automation tools

    static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func appName(_ url: URL) -> String {
        let bundle = Bundle(url: url)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    static func icon(_ url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    // Chrome profiles first (default profile on top), then every other installed browser.
    static func choices(config: Config) -> [Choice] {
        var list: [Choice] = []
        if let chrome = appURL(Config.chrome) {
            let chromeIcon = icon(chrome)
            for p in ChromeProfiles.all() {
                list.append(Choice(title: "Chrome: \(p.name)", detail: p.email.isEmpty ? nil : p.email,
                                   target: Target(bundleID: Config.chrome, profile: p.dir),
                                   icon: ChromeProfiles.picture(dir: p.dir) ?? chromeIcon))
            }
        }
        let handlers = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        for url in handlers.sorted(by: { appName($0) < appName($1) }) {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  !skip.contains(id.lowercased()), id != Config.chrome,
                  seen.insert(id).inserted else { continue }
            list.append(Choice(title: appName(url), detail: nil, target: Target(bundleID: id, profile: nil), icon: icon(url)))
        }
        if let i = list.firstIndex(where: { $0.target == config.defaultTarget }) {
            list.insert(list.remove(at: i), at: 0)
        }
        return list
    }

    static func open(_ url: URL, with target: Target) {
        guard let app = appURL(target.bundleID) else { return }
        if let profile = target.profile {
            // Chrome picks the profile only from a launch argument, so go through `open`.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-na", app.path, "--args", "--profile-directory=\(profile)", url.absoluteString]
            try? p.run()
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

enum ChromeProfiles {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome")
    // LinkRouter's own copies of the profile photos.
    static let pictures = ConfigStore.url.deletingLastPathComponent().appendingPathComponent("profile-pictures")

    // The profile list LinkRouter keeps. LinkRouter never reads Chrome's own files, because
    // macOS blocks that and shows a warning; scripts/refresh-profiles.sh updates this copy.
    static func all() -> [(dir: String, name: String, email: String)] {
        (ConfigStore.load().chromeProfiles ?? []).map { ($0.dir, $0.name, $0.email) }
    }

    // Used only by scripts/refresh-profiles.sh: copies Chrome's profile list and photos.
    static func refresh() -> [ChromeProfile] {
        if ConfigStore.isBroken() {
            NSLog("LinkRouter: fix the mistake in config.json first; profiles not refreshed")
            return []
        }
        guard let fresh = readChrome() else { return [] }
        var config = ConfigStore.load()
        config.chromeProfiles = fresh
        ConfigStore.save(config)
        copyPictures(fresh)
        return fresh
    }

    static func readChrome() -> [ChromeProfile]? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (json["profile"] as? [String: Any])?["info_cache"] as? [String: [String: Any]] else { return nil }
        return cache.map { ChromeProfile(dir: $0.key, name: $0.value["name"] as? String ?? $0.key, email: $0.value["user_name"] as? String ?? "") }
            .sorted { $0.name == $1.name ? $0.email < $1.email : $0.name < $1.name }
    }

    static func copyPictures(_ profiles: [ChromeProfile]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: pictures, withIntermediateDirectories: true)
        for p in profiles {
            let source = root.appendingPathComponent(p.dir).appendingPathComponent("Google Profile Picture.png")
            let copy = pictures.appendingPathComponent("\(p.dir).png")
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.removeItem(at: copy)
            try? fm.copyItem(at: source, to: copy)
        }
    }

    // The round account photo Chrome shows for the profile, when it has one.
    static func picture(dir: String) -> NSImage? {
        guard let source = NSImage(contentsOf: pictures.appendingPathComponent("\(dir).png")) else { return nil }
        let size = NSSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            source.draw(in: rect)
            return true
        }
    }
}
