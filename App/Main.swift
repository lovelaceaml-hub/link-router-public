import AppKit

// LinkRouter: receives every link you click (as your default browser), opens it in your
// default Chrome profile, or shows a picker when you hold Option or Fn while clicking.
@main
final class LinkRouter: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = LinkRouter()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    var config = ConfigStore.load()
    var statusItem: NSStatusItem!

    func applicationWillFinishLaunching(_ note: Notification) {
        // Must be registered before launch finishes so the link that launched us is not lost.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "LinkRouter.Main"
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "LinkRouter")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // Right-click a link (or selected link text) > "Open in Chrome: …" calls openLink below.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSLog("LinkRouter: started, %d Chrome profiles found", ChromeProfiles.all().count)
        // Watch Option/Fn a few times a second, so a click still counts as "hold to choose"
        // if the key was let go just before the link reached us.
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            let keys = NSEvent.modifierFlags
            if keys.contains(.option) || keys.contains(.function) { self?.chooserKeyAt = Date() }
        }
    }

    var chooserKeyAt = Date.distantPast

    // MARK: Incoming links

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              var url = URL(string: text) else { return }
        let keys = NSEvent.modifierFlags
        let choose = keys.contains(.option) || keys.contains(.function) || Date().timeIntervalSince(chooserKeyAt) < 1.5
        NSLog("LinkRouter: link %@ (%@)", url.host ?? "?", choose ? "show picker" : "open default")
        config = ConfigStore.load()
        if config.removeTrackingParameters { url = Router.clean(url) }
        if choose {
            chooserKeyAt = .distantPast
            DispatchQueue.main.async { self.showPicker(for: url) }
        } else {
            Browsers.open(url, with: Router.target(for: url, config: config))
        }
    }

    // MARK: Right-click menu (macOS Services)

    // `userData` is a Chrome profile folder, or empty to show the picker. install.sh lists
    // one service per profile in Info.plist.
    @objc(openLink:userData:error:)
    func openLink(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = (pboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first?.absoluteString
            ?? pboard.string(forType: .string)
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              var url = URL(string: raw.contains("://") ? raw : "https://" + raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            error.pointee = "That is not a web link."
            return
        }
        config = ConfigStore.load()
        if config.removeTrackingParameters { url = Router.clean(url) }
        let profile = userData ?? ""
        NSLog("LinkRouter: right-click %@ (%@)", url.host ?? "?", profile.isEmpty ? "show picker" : profile)
        if profile.isEmpty {
            DispatchQueue.main.async { self.showPicker(for: url) }
        } else {
            Browsers.open(url, with: Target(bundleID: Config.chrome, profile: profile))
        }
    }

    // MARK: Picker

    func showPicker(for url: URL) {
        let choices = Browsers.choices(config: config)
        let current = Router.target(for: url, config: config)
        var rows: [(NSImage?, String, String?, Bool)] = choices.map { ($0.icon, $0.title, $0.detail, $0.target == current) }
        rows.append((NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil), "Copy Link", nil, false))
        PickerPanel.show(header: "Open \(url.host ?? url.absoluteString) in", rows: rows) { index in
            NSLog("LinkRouter: picker %@", index < 0 ? "dismissed" : "chose \(index)")
            if index < 0 { return }
            if index < choices.count {
                Browsers.open(url, with: choices[index].target)
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }

    func choiceItem(_ choice: Choice, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: choice.title, action: action, keyEquivalent: "")
        item.target = self
        item.image = choice.icon
        item.representedObject = choice.target.bundleID + "|" + (choice.target.profile ?? "")
        if let detail = choice.detail {
            let title = NSMutableAttributedString(string: "\(choice.title)  ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: detail, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = title
        }
        return item
    }

    func target(from item: NSMenuItem) -> Target? {
        guard let raw = item.representedObject as? String else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        return Target(bundleID: parts[0], profile: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
    }

    // MARK: Menu bar menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        config = ConfigStore.load()
        menu.removeAllItems()

        if !isDefaultBrowser() {
            let make = NSMenuItem(title: "Make LinkRouter your default browser…", action: #selector(makeDefault), keyEquivalent: "")
            make.target = self
            menu.addItem(make)
            menu.addItem(.separator())
        }

        let defaults = NSMenu()
        for choice in Browsers.choices(config: config) {
            let item = choiceItem(choice, action: #selector(setDefault(_:)))
            item.state = choice.target == config.defaultTarget ? .on : .off
            defaults.addItem(item)
        }
        let defaultsItem = NSMenuItem(title: "Links open in", action: nil, keyEquivalent: "")
        defaultsItem.submenu = defaults
        menu.addItem(defaultsItem)

        let copied = NSMenuItem(title: "Open Copied Link In…", action: #selector(openCopied), keyEquivalent: "")
        copied.target = self
        copied.isEnabled = copiedURL() != nil
        menu.addItem(copied)

        let clean = NSMenuItem(title: "Remove Tracking From Links", action: #selector(toggleClean), keyEquivalent: "")
        clean.target = self
        clean.state = config.removeTrackingParameters ? .on : .off
        menu.addItem(clean)

        menu.addItem(.separator())
        let tip = NSMenuItem(title: "Hold ⌥ Option or Fn while clicking a link to choose", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)
        let rules = NSMenuItem(title: "Edit Rules…", action: #selector(editRules), keyEquivalent: "")
        rules.target = self
        menu.addItem(rules)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LinkRouter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func setDefault(_ sender: NSMenuItem) {
        guard let target = target(from: sender) else { return }
        config.defaultTarget = target
        ConfigStore.save(config)
    }

    @objc func toggleClean() {
        config.removeTrackingParameters.toggle()
        ConfigStore.save(config)
    }

    func copiedURL() -> URL? {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    @objc func openCopied() {
        guard var url = copiedURL() else { return }
        if config.removeTrackingParameters { url = Router.clean(url) }
        // Wait for the menu bar menu to close before showing the picker.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showPicker(for: url) }
    }

    @objc func editRules() {
        NSWorkspace.shared.open([ConfigStore.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func isDefaultBrowser() -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.standardizedFileURL
            == Bundle.main.bundleURL.standardizedFileURL
    }

    @objc func makeDefault() {
        // macOS asks you to confirm each change.
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { _ in
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https") { _ in }
        }
    }
}
