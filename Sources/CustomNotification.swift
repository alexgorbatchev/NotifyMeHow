import Cocoa
import ApplicationServices

/// What a banner is drawn on.
enum BannerBackground: String {
    case solid
    case glass
    case clearGlass

    /// Glass needs macOS 26; earlier systems draw the solid background instead.
    var isAvailableGlass: Bool {
        guard self != .solid else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Glass banners sharpen from a blur as they fade in and blur again as they fade out.
    var usesBlurTransition: Bool {
        return isAvailableGlass
    }
}

/// Configuration for custom notification appearance
struct CustomNotificationConfig {
    var backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.85)
    var appColor: NSColor = NSColor.white.withAlphaComponent(0.6)
    var titleColor: NSColor = .white
    var subtitleColor: NSColor = NSColor.white.withAlphaComponent(0.8)
    var bodyColor: NSColor = NSColor.white.withAlphaComponent(0.7)
    // Banner metrics in points before scaleFactor is applied.
    var titleFontSize: CGFloat = 20
    var subtitleFontSize: CGFloat = 10
    var bodyFontSize: CGFloat = 12
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 20
    var width: CGFloat = 420
    var hasShadow: Bool = true
    var background: BannerBackground = .solid
    var glassTintOpacity: CGFloat = 0  // How strongly glass is tinted toward backgroundColor (0-1)
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

    var clipboardText: String {
        let cleanedTitle = title.hasPrefix("[slk] ") ? String(title.dropFirst(6)) : title
        return [cleanedTitle, subtitle, body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Manages custom notification windows
class CustomNotificationManager {
    static let shared = CustomNotificationManager()

    private static let reflowDuration: TimeInterval = 0.25
    private static let fadeDuration: TimeInterval = 0.3
    /// Blur radius glass banner content starts from when fading in and ends at when fading out.
    private static let transitionBlurRadius: CGFloat = 12
    private static let transitionBlurFilterName = "transitionBlur"

    private var activeWindows: [NSWindow] = []
    private var windowConfigs: [NSWindow: CustomNotificationConfig] = [:]
    /// The banner content of each window, which the blur transition is applied to
    private var bannerViews: [NSWindow: NSView] = [:]
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

            let bannerView = self.bannerViews[window]
            if config.background.usesBlurTransition, let bannerView {
                self.animateBlur(of: bannerView, from: Self.transitionBlurRadius, to: 0)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                window.animator().alphaValue = config.opacity
            } completionHandler: { [weak self] in
                // A zero-radius blur still costs a Core Image pass, so drop the filter once sharp
                bannerView?.contentFilters = []
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
        if windowConfigs[window]?.background.usesBlurTransition == true, let bannerView = bannerViews[window] {
            animateBlur(of: bannerView, from: 0, to: Self.transitionBlurRadius)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.activeWindows.removeAll { $0 == window }
            self?.windowConfigs.removeValue(forKey: window)
            self?.bannerViews.removeValue(forKey: window)
            if let self {
                for remainingWindow in self.activeWindows {
                    self.positionWindow(remainingWindow, animated: true)
                }
            }
        })
    }

    /// Animates a Gaussian blur on the banner content, in step with the window fade.
    private func animateBlur(of view: NSView, from startRadius: CGFloat, to endRadius: CGFloat) {
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
        blur.name = Self.transitionBlurFilterName
        blur.setValue(endRadius, forKey: kCIInputRadiusKey)

        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        view.contentFilters = [blur]

        let animation = CABasicAnimation(keyPath: "filters.\(Self.transitionBlurFilterName).inputRadius")
        animation.fromValue = startRadius
        animation.toValue = endRadius
        animation.duration = Self.fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(animation, forKey: Self.transitionBlurFilterName)
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

        window.hasShadow = config.hasShadow
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        if config.background.isAvailableGlass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: contentView.bounds)
            glass.style = config.background == .clearGlass ? .clear : .regular
            glass.cornerRadius = config.cornerRadius * config.scaleFactor
            glass.tintColor = config.glassTintOpacity > 0
                ? config.backgroundColor.withAlphaComponent(config.glassTintOpacity) : nil
            glass.contentView = contentView
            window.contentView = glass
        } else {
            window.contentView = contentView
        }
        contentView.frame = window.contentView!.bounds
        bannerViews[window] = contentView

        return window
    }

    /// Places a banner in the stack; `animated` slides it when the stack reflows.
    private func positionWindow(_ window: NSWindow, animated: Bool = false) {
        guard let screen = NSScreen.main, let config = windowConfigs[window] else { return }
        let precedingWindows = activeWindows.prefix { $0 !== window }
        let origin = NotificationStackLayout.origin(
            for: window.frame.size,
            position: config.position,
            screenFrame: screen.visibleFrame,
            precedingHeights: precedingWindows.map { $0.frame.height },
            firstHeight: activeWindows.first?.frame.height
        )

        guard animated else {
            window.setFrameOrigin(origin)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reflowDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrameOrigin(origin)
        }
    }
}
