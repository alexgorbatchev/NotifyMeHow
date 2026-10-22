import Cocoa

private final class CopyNotificationButton: NSButton {
    var fixedSize: CGFloat = 20

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsetsZero
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fixedSize, height: fixedSize)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// The native banner surface used by the local NotifyMeHow build.
final class ExpressiveNotificationView: NSView {
    private var backgroundLayer: CALayer?
    private let clipboardText: String
    private let copyButton = CopyNotificationButton()
    private let defaultCopyIconColor: NSColor
    private let activeCopyIconColor: NSColor
    private let defaultBorderColor: NSColor
    private let iconPointSize: CGFloat
    private var resetCopyWorkItem: DispatchWorkItem?

    init(content: NotificationContent, config: CustomNotificationConfig) {
        let scale = config.scaleFactor
        let icon = config.hideIcon ? nil : config.customIcon ?? content.profileImage ?? content.appIcon
            ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notification")
        let metrics = BannerMetrics(config: config, hasIcon: icon != nil)
        let hasAppName = config.showAppName && !content.appName.isEmpty
        // Keep slk's transport marker for rule matching, but omit it from the banner.
        let titleText = content.title.hasPrefix("[slk] ") ? String(content.title.dropFirst(6)) : content.title
        let hasTitle = !config.hideTitle && !titleText.isEmpty

        self.clipboardText = content.clipboardText
        self.defaultCopyIconColor = config.subtitleColor.withAlphaComponent(1)
        self.activeCopyIconColor = config.appColor.withAlphaComponent(1)
        self.defaultBorderColor = config.borderColor
        self.iconPointSize = 10 * scale

        super.init(frame: NSRect(x: 0, y: 0, width: metrics.width, height: 1))
        wantsLayer = true
        layer?.cornerRadius = metrics.cornerRadius
        layer?.masksToBounds = true
        // Over glass the banner stays transparent so the glass effect shows through
        layer?.backgroundColor = config.background.isAvailableGlass
            ? NSColor.clear.cgColor : config.backgroundColor.withAlphaComponent(1).cgColor
        layer?.borderWidth = config.borderWidth * scale
        layer?.borderColor = config.borderColor.cgColor

        if let image = config.backgroundImage,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let background = CALayer()
            background.contents = cgImage
            background.contentsGravity = .resizeAspectFill
            background.opacity = 0.2
            background.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(background)
            backgroundLayer = background
        }

        // Text column beside the icon, tightly spaced like a macOS notification
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = metrics.lineSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        if hasAppName {
            column.addArrangedSubview(makeLabel(content.appName.uppercased(), face: "Medium",
                                                size: config.subtitleFontSize * scale,
                                                color: config.subtitleColor, width: metrics.textWidth, lines: 1))
        }
        if hasTitle {
            column.addArrangedSubview(makeLabel(titleText, face: "Bold", size: config.titleFontSize * scale,
                                                color: config.titleColor, width: metrics.textWidth, lines: 2))
        }
        if !config.hideText && !content.subtitle.isEmpty {
            column.addArrangedSubview(makeLabel(content.subtitle, face: "Bold",
                                                size: config.subtitleFontSize * scale,
                                                color: config.subtitleColor, width: metrics.textWidth, lines: 2))
        }
        if !config.hideText && !content.body.isEmpty {
            var body = content.body
            if config.maxBodyCharacters > 0 && body.count > config.maxBodyCharacters {
                body = String(body.prefix(config.maxBodyCharacters - 1)) + "…"
            }
            column.addArrangedSubview(makeLabel(body, face: "Regular", size: config.bodyFontSize * scale,
                                                color: config.bodyColor, width: metrics.textWidth,
                                                lines: config.maxBodyLines))
        }

        let columnHeight = column.fittingSize.height
        frame.size.height = max(metrics.minimumHeight, columnHeight + metrics.padding * 2)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.textLeading),
            column.widthAnchor.constraint(equalToConstant: metrics.textWidth),
            // Short text is centered against the icon; taller text starts at the top padding
            column.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if let icon {
            let iconView = NSImageView()
            iconView.image = icon
            if icon.isTemplate { iconView.contentTintColor = config.appColor }
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.padding),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: metrics.iconSize),
                iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
            ])
        }

        configureCopyButton(scale: scale)
        addSubview(copyButton)
        NSLayoutConstraint.activate([
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.padding),
            copyButton.topAnchor.constraint(equalTo: topAnchor, constant: metrics.padding),
            copyButton.widthAnchor.constraint(equalToConstant: metrics.copyButtonSize),
            copyButton.heightAnchor.constraint(equalTo: copyButton.widthAnchor)
        ])

        layoutSubtreeIfNeeded()
        backgroundLayer?.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("ExpressiveNotificationView is created programmatically")
    }

    private func configureCopyButton(scale: CGFloat) {
        copyButton.fixedSize = 20 * scale
        copyButton.isBordered = false
        copyButton.title = ""
        copyButton.imagePosition = .imageOnly
        copyButton.imageScaling = .scaleProportionallyDown
        copyButton.wantsLayer = true
        copyButton.layer?.cornerRadius = 5 * scale
        copyButton.layer?.backgroundColor = defaultBorderColor.withAlphaComponent(0.45).cgColor
        copyButton.layer?.borderWidth = 0.5 * scale
        copyButton.layer?.borderColor = defaultBorderColor.cgColor
        copyButton.toolTip = "Copy notification to clipboard"
        copyButton.setAccessibilityLabel("Copy notification")
        copyButton.target = self
        copyButton.action = #selector(copyToClipboard)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        setCopyButtonSymbol("doc.on.doc", weight: .medium, tint: defaultCopyIconColor)
    }

    private func setCopyButtonSymbol(_ name: String, weight: NSFont.Weight, tint: NSColor) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Copy notification")?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        copyButton.image = image
        copyButton.contentTintColor = tint
    }

    @objc func copyToClipboard() {
        guard !clipboardText.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clipboardText, forType: .string)

        resetCopyWorkItem?.cancel()
        setCopyButtonSymbol("checkmark", weight: .bold, tint: activeCopyIconColor)
        copyButton.layer?.borderColor = activeCopyIconColor.cgColor

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setCopyButtonSymbol("doc.on.doc", weight: .medium, tint: self.defaultCopyIconColor)
            self.copyButton.layer?.borderColor = self.defaultBorderColor.cgColor
        }
        resetCopyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func makeLabel(_ text: String, face: String, size: CGFloat, color: NSColor,
                           width: CGFloat, lines: Int) -> NSTextField {
        let fontName = "MapleMonoNormal-NF-\(face)"
        guard let font = NSFont(name: fontName, size: size) else {
            preconditionFailure("Required bundled font is unavailable: \(fontName)")
        }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color.withAlphaComponent(1)
        label.preferredMaxLayoutWidth = width
        label.maximumNumberOfLines = lines
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
}
