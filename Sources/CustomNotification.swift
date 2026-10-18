import Cocoa
import ApplicationServices

/// Configuration for custom notification appearance
struct CustomNotificationConfig {
    var backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.85)
    var appColor: NSColor = NSColor.white.withAlphaComponent(0.6)
    var titleColor: NSColor = .white
    var subtitleColor: NSColor = NSColor.white.withAlphaComponent(0.8)
    var bodyColor: NSColor = NSColor.white.withAlphaComponent(0.7)
    var titleFontSize: CGFloat = 16
    var subtitleFontSize: CGFloat = 13
    var bodyFontSize: CGFloat = 13
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 10
    var width: CGFloat = 380
    var maxHeight: CGFloat = 200
    var opacity: CGFloat = 1.0
    var dwellTime: TimeInterval = 5.0  // How long to show before auto-dismiss
    var position: NotificationPosition = .bottomLeft
    var scaleFactor: CGFloat = 1.5  // Make it bigger than original
    var customIcon: NSImage? = nil  // Custom icon to override app icon
    var backgroundImage: NSImage? = nil  // Background image instead of solid color
    var maxBodyCharacters: Int = 500  // Max characters for body text (0 = unlimited)
    var maxBodyLines: Int = 4  // Max lines for body text (0 = unlimited)
    var showAppName: Bool = true  // Whether to show app name label
    var borderWidth: CGFloat = 0  // Border width (0 = none)
    var borderColor: NSColor = .white  // Border color
    var animation: String = "none"  // Animation type: none, pulse, jiggle, wiggle, bounce
    var animationLoops: Bool = false  // Whether animation repeats continuously
    var hideSystemNotification: Bool = false  // Move system notification off-screen
    var hideIcon: Bool = false  // Hide the app icon
    var hideTitle: Bool = false  // Hide the title
    var hideText: Bool = false  // Hide subtitle and body text
}

/// Content extracted from a notification
struct NotificationContent {
    var appName: String = ""
    var title: String = ""
    var subtitle: String = ""
    var body: String = ""
    var appIcon: NSImage? = nil      // App icon from bundle
    var profileImage: NSImage? = nil  // Profile/contact image if available
}

/// Manages custom notification windows
class CustomNotificationManager {
    static let shared = CustomNotificationManager()

    private var activeWindows: [NSWindow] = []
    private var windowConfigs: [NSWindow: CustomNotificationConfig] = [:]
    private var config = CustomNotificationConfig()

    func configure(_ config: CustomNotificationConfig) {
        self.config = config
    }

    /// Extract content from an AX notification banner
    func extractContent(from banner: AXUIElement) -> NotificationContent {
        var content = NotificationContent()

        // Get app name from description
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(banner, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let desc = descRef as? String {
            // Format: "AppName, Title, Subtitle, Body"
            let parts = desc.components(separatedBy: ", ")
            if parts.count > 0 {
                content.appName = parts[0]
            }
        }

        // Get text values from children
        var texts: [String] = []
        extractTexts(from: banner, into: &texts)

        if texts.count >= 1 { content.title = texts[0] }
        if texts.count >= 2 { content.subtitle = texts[1] }
        if texts.count >= 3 { content.body = texts[2] }

        // Get app icon from running applications
        if !content.appName.isEmpty {
            content.appIcon = getAppIcon(for: content.appName)
        }

        // Try to extract profile/contact image from AX hierarchy
        content.profileImage = extractImage(from: banner)

        return content
    }

    /// Get the app icon for a given app name
    private func getAppIcon(for appName: String) -> NSImage? {
        // Try to find the app in running applications
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let name = app.localizedName, name.localizedCaseInsensitiveContains(appName) {
                return app.icon
            }
        }

        // Try to find by bundle identifier patterns
        let workspace = NSWorkspace.shared
        let commonBundlePatterns = [
            "com.apple.\(appName.lowercased())",
            "com.apple.\(appName.lowercased().replacingOccurrences(of: " ", with: ""))"
        ]

        for pattern in commonBundlePatterns {
            if let url = workspace.urlForApplication(withBundleIdentifier: pattern) {
                return workspace.icon(forFile: url.path)
            }
        }

        return nil
    }

    /// Try to extract an image from the AX element hierarchy
    private func extractImage(from element: AXUIElement) -> NSImage? {
        // Check if this element has an image
        var imageRef: CFTypeRef?

        // Try AXImage attribute (some elements expose images this way)
        if AXUIElementCopyAttributeValue(element, "AXImage" as CFString, &imageRef) == .success,
           let ref = imageRef {
            // AXImage can be various types - try to convert to NSImage
            // Check if the CFTypeRef is actually a CGImage by comparing type IDs
            if CFGetTypeID(ref) == CGImage.typeID {
                let cgImage = ref as! CGImage
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        // Check role - look for image elements
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            if role == "AXImage" || role == kAXImageRole as String {
                // This is an image element - try to get its contents
                // Unfortunately, AX doesn't typically expose raw image data
                // but we can try a few approaches

                // Try AXValue which sometimes contains image data
                var valueRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
                    if let cgImage = valueRef as! CGImage? {
                        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    }
                }
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let image = extractImage(from: child) {
                    return image
                }
            }
        }

        return nil
    }

    private func extractTexts(from element: AXUIElement, into texts: inout [String]) {
        // Check for AXValue (text content)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            texts.append(value)
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                extractTexts(from: child, into: &texts)
            }
        }
    }

    /// Show a custom notification window
    func showNotification(content: NotificationContent) {
        let config = self.config
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let window = self.createNotificationWindow(content: content, config: config)
            self.windowConfigs[window] = config
            self.activeWindows.append(window)

            // Position the window
            self.positionWindow(window)

            // Show with fade-in
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                window.animator().alphaValue = config.opacity
            } completionHandler: { [weak self] in
                // Start animation after fade-in completes
                self?.startAnimation(for: window, config: config)
            }

            // Auto-dismiss after dwell time (0 = indefinite, no auto-dismiss)
            if config.dwellTime > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + config.dwellTime) { [weak self] in
                    self?.dismissNotification(window)
                }
            }
        }
    }

    private func startAnimation(for window: NSWindow, config: CustomNotificationConfig) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        let repeatCount: Float = config.animationLoops ? .infinity : 1

        switch config.animation {
        case "pulse":
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = config.opacity
            pulse.toValue = config.opacity * 0.6
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = repeatCount
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "pulse")

        case "jiggle":
            let jiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            let angle = Double.pi / 90  // ~2 degrees
            jiggle.values = [-angle, angle, -angle]
            jiggle.duration = 0.2
            jiggle.repeatCount = repeatCount
            jiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(jiggle, forKey: "jiggle")

        case "wiggle":
            // Decaying wiggle that settles down
            let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            let angle = Double.pi / 60  // ~3 degrees
            wiggle.values = [0, -angle, angle, -angle * 0.6, angle * 0.6, -angle * 0.3, angle * 0.3, 0]
            wiggle.keyTimes = [0, 0.1, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
            wiggle.duration = 0.6
            wiggle.repeatCount = repeatCount
            layer.add(wiggle, forKey: "wiggle")

        case "bounce":
            let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
            bounce.values = [1.0, 1.05, 0.98, 1.02, 1.0]
            bounce.keyTimes = [0, 0.2, 0.5, 0.75, 1.0]
            bounce.duration = 0.5
            bounce.repeatCount = repeatCount
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(bounce, forKey: "bounce")

        default:
            break  // "none" - no animation
        }
    }

    private func dismissNotification(_ window: NSWindow) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.activeWindows.removeAll { $0 == window }
            self?.windowConfigs.removeValue(forKey: window)
            if let self {
                for remainingWindow in self.activeWindows {
                    self.positionWindow(remainingWindow)
                }
            }
        })
    }

    private func createNotificationWindow(content: NotificationContent, config: CustomNotificationConfig) -> NSWindow {
        let contentView = ExpressiveNotificationView(content: content, config: config)
        let scaledWidth = contentView.frame.width
        let windowHeight = contentView.frame.height

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: scaledWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = contentView
        contentView.frame = window.contentView!.bounds

        return window
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main, let config = windowConfigs[window] else { return }
        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame

        var x: CGFloat
        var y: CGFloat

        // Horizontal position
        switch config.position.corner {
        case .topRight, .middleRight, .bottomRight:
            x = screenFrame.maxX - windowFrame.width - config.position.offsetX
        case .topLeft, .middleLeft, .bottomLeft:
            x = screenFrame.minX + config.position.offsetX
        case .topCenter, .center, .bottomCenter:
            x = screenFrame.midX - windowFrame.width / 2
        }

        // Vertical position
        switch config.position.corner {
        case .topLeft, .topCenter, .topRight:
            y = screenFrame.maxY - windowFrame.height - config.position.offsetY
        case .middleLeft, .center, .middleRight:
            y = screenFrame.midY - windowFrame.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = screenFrame.minY + config.position.offsetY
        }

        // Stack multiple notifications
        let precedingWindows = activeWindows.prefix { $0 !== window }
        let gap: CGFloat = 16
        var stackOffset = precedingWindows.reduce(CGFloat.zero) { $0 + $1.frame.height + gap }
        // Centered banners start relative to their own height; adjust to the first
        // banner's top edge so mixed-height windows retain the same visible gap.
        switch config.position.corner {
        case .middleLeft, .center, .middleRight:
            if let firstWindow = activeWindows.first {
                stackOffset += (windowFrame.height - firstWindow.frame.height) / 2
            }
        default:
            break
        }
        switch config.position.corner {
        case .topLeft, .topCenter, .topRight:
            y -= stackOffset
        case .bottomLeft, .bottomCenter, .bottomRight:
            y += stackOffset
        case .middleLeft, .center, .middleRight:
            y -= stackOffset
        }

        // Clamp to screen bounds to prevent off-screen notifications
        // (e.g., when importing settings from a different screen size)
        x = max(screenFrame.minX, min(x, screenFrame.maxX - windowFrame.width))
        y = max(screenFrame.minY, min(y, screenFrame.maxY - windowFrame.height))

        window.setFrameOrigin(CGPoint(x: x, y: y))
    }
}
