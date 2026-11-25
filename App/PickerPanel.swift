import AppKit

// A small floating chooser shown at the mouse. It is our own window rather than a menu,
// because macOS closes menus from background apps before you can see them.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    private var onChoose: ((Int) -> Void)?
    private var rows: [PickerRow] = []
    private var outsideClick: Any?

    // Rows are (icon, title, detail, isDefault). `onChoose` gets the row index, or -1 when dismissed.
    static func show(header: String, rows items: [(NSImage?, String, String?, Bool)], onChoose: @escaping (Int) -> Void) {
        let panel = PickerPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
        panel.build(header: header, items: items, onChoose: onChoose)
        panel.present()
    }

    private func build(header: String, items: [(NSImage?, String, String?, Bool)], onChoose: @escaping (Int) -> Void) {
        self.onChoose = onChoose
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)

        let title = NSTextField(labelWithString: header)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        let titleRow = NSStackView(views: [title])
        titleRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 4, right: 8)
        stack.addArrangedSubview(titleRow)

        for (i, item) in items.enumerated() {
            let row = PickerRow(index: i, icon: item.0, title: item.1, detail: item.2, isDefault: item.3,
                                shortcut: i < 9 ? "\(i + 1)" : nil) { [weak self] in self?.finish(i) }
            rows.append(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
        }

        background.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
        contentView = background
        background.layoutSubtreeIfNeeded()
        setContentSize(stack.fittingSize)
    }

    private func present() {
        // Top-left corner at the mouse, kept on screen.
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            finish(-1)  // No screen to show it on.
            return
        }
        let area = screen.visibleFrame
        var origin = NSPoint(x: mouse.x + 2, y: mouse.y - frame.height - 2)
        origin.x = min(max(origin.x, area.minX + 4), area.maxX - frame.width - 4)
        origin.y = min(max(origin.y, area.minY + 4), area.maxY - frame.height - 4)
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
        // Any click outside the chooser dismisses it.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.finish(-1)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(-1); return }  // Escape
        if let digit = Int(event.charactersIgnoringModifiers ?? ""), digit >= 1, digit <= min(9, rows.count) {
            finish(digit - 1)
            return
        }
        if event.charactersIgnoringModifiers == "c", rows.count > 0 { finish(rows.count - 1); return }  // Copy Link is last
        super.keyDown(with: event)
    }

    private func finish(_ index: Int) {
        guard let done = onChoose else { return }
        onChoose = nil
        if let monitor = outsideClick { NSEvent.removeMonitor(monitor) }
        orderOut(nil)
        done(index)
    }
}

// One clickable line: icon, title, grey detail, a check for the default, and its number key.
final class PickerRow: NSView {
    private let action: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(index: Int, icon: NSImage?, title: String, detail: String?, isDefault: Bool, shortcut: String?, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        let views: [NSView] = {
            var v: [NSView] = []
            let check = NSTextField(labelWithString: isDefault ? "✓" : "")
            check.font = .systemFont(ofSize: 12, weight: .semibold)
            check.widthAnchor.constraint(equalToConstant: 12).isActive = true
            v.append(check)
            let image = NSImageView(image: icon ?? NSImage())
            image.widthAnchor.constraint(equalToConstant: 18).isActive = true
            image.heightAnchor.constraint(equalToConstant: 18).isActive = true
            v.append(image)
            let label = NSTextField(labelWithString: title)
            label.font = .menuFont(ofSize: 0)
            v.append(label)
            if let detail {
                let d = NSTextField(labelWithString: detail)
                d.font = .systemFont(ofSize: 11)
                d.textColor = .secondaryLabelColor
                v.append(d)
            }
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            v.append(spacer)
            let key = NSTextField(labelWithString: shortcut ?? "")
            key.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            key.textColor = .tertiaryLabelColor
            v.append(key)
            return v
        }()
        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { action() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
