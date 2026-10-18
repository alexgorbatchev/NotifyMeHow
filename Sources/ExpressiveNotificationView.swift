import Cocoa

/// The native banner surface used by the local NotifyMeHow build.
final class ExpressiveNotificationView: NSView {
    private var backgroundLayer: CALayer?

    init(content: NotificationContent, config: CustomNotificationConfig) {
        let scale = config.scaleFactor
        let width = 420 * scale
        let padding = 20 * scale
        let icon = config.hideIcon ? nil : config.customIcon ?? content.profileImage ?? content.appIcon
            ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Notification")
        let hasAppName = config.showAppName && !content.appName.isEmpty
        // Keep slk's transport marker for rule matching, but omit it from the banner.
        let titleText = content.title.hasPrefix("[slk] ") ? String(content.title.dropFirst(6)) : content.title
        let hasTitle = !config.hideTitle && !titleText.isEmpty
        let textWidth = width - padding * 2

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        wantsLayer = true
        layer?.cornerRadius = 14 * scale
        layer?.masksToBounds = true
        layer?.backgroundColor = config.backgroundColor.withAlphaComponent(1).cgColor
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

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6 * scale
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        column.widthAnchor.constraint(equalToConstant: textWidth).isActive = true

        if hasAppName {
            column.addArrangedSubview(makeLabel(content.appName.uppercased(), face: "Medium", size: 9 * scale,
                                               color: config.subtitleColor, width: textWidth, lines: 2))
        }

        if hasTitle || icon != nil {
            let header = NSView()
            header.translatesAutoresizingMaskIntoConstraints = false
            column.addArrangedSubview(header)
            header.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
            var headerHeight: CGFloat = icon == nil ? 0 : 24 * scale
            let textInset: CGFloat = icon == nil ? 0 : 34 * scale

            if hasTitle {
                let title = makeLabel(titleText, face: "Bold", size: 20 * scale,
                                      color: config.titleColor, width: textWidth - textInset - 20 * scale,
                                      lines: 2)
                header.addSubview(title)
                NSLayoutConstraint.activate([
                    title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: textInset),
                    title.centerYAnchor.constraint(equalTo: header.centerYAnchor)
                ])
                headerHeight = max(headerHeight, title.fittingSize.height)
            }

            if let icon {
                let iconView = NSImageView()
                iconView.image = icon
                if icon.isTemplate { iconView.contentTintColor = config.appColor }
                iconView.imageScaling = .scaleProportionallyUpOrDown
                iconView.translatesAutoresizingMaskIntoConstraints = false
                header.addSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                    iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: 24 * scale),
                    iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor)
                ])
            }

            let indicator = NSView()
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = config.appColor.withAlphaComponent(1).cgColor
            indicator.layer?.cornerRadius = 3 * scale
            indicator.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                indicator.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 6 * scale),
                indicator.heightAnchor.constraint(equalTo: indicator.widthAnchor),
                header.heightAnchor.constraint(equalToConstant: headerHeight)
            ])
            column.setCustomSpacing(6 * scale, after: header)
        }

        if !config.hideText && !content.subtitle.isEmpty {
            let context = makeLabel(content.subtitle, face: "Medium", size: 10 * scale,
                                    color: config.subtitleColor, width: textWidth, lines: 2)
            column.addArrangedSubview(context)
        }

        if !config.hideText && !content.body.isEmpty {
            if let preceding = column.arrangedSubviews.last {
                column.setCustomSpacing(12 * scale, after: preceding)
            }

            var body = content.body
            if config.maxBodyCharacters > 0 && body.count > config.maxBodyCharacters {
                body = String(body.prefix(config.maxBodyCharacters - 1)) + "…"
            }
            column.addArrangedSubview(makeLabel(body, face: "Regular", size: 12 * scale,
                                               color: config.bodyColor, width: textWidth,
                                               lines: config.maxBodyLines))
        }

        frame.size.height = max(64 * scale, column.fittingSize.height + padding * 2)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            column.topAnchor.constraint(equalTo: topAnchor, constant: padding)
        ])

        layoutSubtreeIfNeeded()
        backgroundLayer?.frame = bounds
    }

    required init?(coder: NSCoder) {
        fatalError("ExpressiveNotificationView is created programmatically")
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
