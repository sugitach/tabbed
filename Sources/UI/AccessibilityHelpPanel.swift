import AppKit

/// Modeless guidance with ordinary controls. NSAlert reserves its response
/// buttons' target/action for modal presentation, so do not repurpose them.
@MainActor
final class AccessibilityHelpPanel: NSObject, NSWindowDelegate {
    let window: NSPanel
    private let onResponse: (NSApplication.ModalResponse) -> Void

    init(information: String, onResponse: @escaping (NSApplication.ModalResponse) -> Void) {
        self.onResponse = onResponse
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 528, height: 500),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Accessibility Permission"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self

        let heading = NSTextField(wrappingLabelWithString: "Accessibility access is not active")
        heading.font = .boldSystemFont(ofSize: 14)
        let body = NSTextField(wrappingLabelWithString: information)
        body.font = .systemFont(ofSize: 13)
        body.isSelectable = true
        body.preferredMaxLayoutWidth = 480
        body.maximumNumberOfLines = 0
        body.lineBreakMode = .byWordWrapping

        let titles = ["Open Accessibility Settings…", "Show Current App in Finder", "Not Now"]
        let buttons = titles.enumerated().map { index, title in
            let button = NSButton(title: title, target: self, action: #selector(respond(_:)))
            button.bezelStyle = .rounded
            button.tag = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
            button.keyEquivalent = index == 0 ? "\r" : (index == 2 ? "\u{1b}" : "")
            return button
        }
        let actions = NSStackView(views: buttons)
        actions.orientation = .vertical
        actions.alignment = .leading
        actions.spacing = 8
        for button in buttons { button.widthAnchor.constraint(equalToConstant: 480).isActive = true }
        let stack = NSStackView(views: [heading, body, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            heading.widthAnchor.constraint(equalToConstant: 480),
            body.widthAnchor.constraint(equalToConstant: 480),
            actions.widthAnchor.constraint(equalToConstant: 480)
        ])
        window.contentView = content
        window.setContentSize(content.fittingSize)
        content.layoutSubtreeIfNeeded()
        window.center()
    }

    @objc private func respond(_ sender: NSButton) {
        onResponse(NSApplication.ModalResponse(rawValue: sender.tag))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onResponse(.alertThirdButtonReturn)
        return false
    }
}
