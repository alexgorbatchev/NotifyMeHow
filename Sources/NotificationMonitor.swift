import ApplicationServices
import Cocoa

/// Mode for handling notification display
enum NotificationMode {
    case reposition       // Just move the original notification
    case replaceWithLarger // Hide original, show custom larger notification
}

/// Configuration for where to place notifications
struct NotificationPosition {
    enum Corner: String {
        case topLeft = "topLeft"
        case topCenter = "topCenter"
        case topRight = "topRight"
        case middleLeft = "middleLeft"
        case center = "center"
        case middleRight = "middleRight"
        case bottomLeft = "bottomLeft"
        case bottomCenter = "bottomCenter"
        case bottomRight = "bottomRight"
    }

    var corner: Corner
    var offsetX: CGFloat
    var offsetY: CGFloat

    static let topLeft = NotificationPosition(corner: .topLeft, offsetX: 20, offsetY: 40)
    static let topCenter = NotificationPosition(corner: .topCenter, offsetX: 0, offsetY: 40)
    static let topRight = NotificationPosition(corner: .topRight, offsetX: 20, offsetY: 40)
    static let middleLeft = NotificationPosition(corner: .middleLeft, offsetX: 20, offsetY: 0)
    static let center = NotificationPosition(corner: .center, offsetX: 0, offsetY: 0)
    static let middleRight = NotificationPosition(corner: .middleRight, offsetX: 20, offsetY: 0)
    static let bottomLeft = NotificationPosition(corner: .bottomLeft, offsetX: 20, offsetY: 20)
    static let bottomCenter = NotificationPosition(corner: .bottomCenter, offsetX: 0, offsetY: 20)
    static let bottomRight = NotificationPosition(corner: .bottomRight, offsetX: 20, offsetY: 20)

    static let defaultTopRight = topRight
}

/// Monitors for notification windows and repositions them
class NotificationMonitor {
    private var observer: AXObserver?
    private var isRunning = false
    private var targetPosition: NotificationPosition
    private var scaleFactor: CGFloat
    private var showCustomNotification: Bool = false
    private var customConfig: CustomNotificationConfig?
    private var seenBanners: Set<String> = []  // Track banners we've already processed
    private var seenBannerOrder: [String] = [] // Bounded FIFO queue to prevent memory growth
    private let maxSeenBanners = 500

    // Cached initial notification data for relative positioning
    private var cachedInitialPosition: CGPoint?
    private var cachedInitialWindowSize: CGSize?
    private var cachedInitialNotifSize: CGSize?
    private var cachedInitialPadding: CGFloat?

    // Track recently shown notifications to avoid duplicates but allow different content
    private var recentNotifications: [(content: String, time: Date)] = []
    private let dedupeWindow: TimeInterval = 10.0  // Ignore exact duplicates within 10 seconds

    init(position: NotificationPosition = .bottomRight, scaleFactor: CGFloat = 1.0) {
        self.targetPosition = position
        self.scaleFactor = scaleFactor
    }

    /// Enable custom notifications that duplicate the system notification
    func enableCustomNotifications(config: CustomNotificationConfig) {
        self.showCustomNotification = true
        self.customConfig = config
        CustomNotificationManager.shared.configure(config)
    }

    /// Disable custom notifications
    func disableCustomNotifications() {
        self.showCustomNotification = false
        self.customConfig = nil
    }

    private var permissionTimer: Timer?

    func start() {
        if checkAccessibilityPermissions() {
            startObserver()
        } else {
            print("Accessibility permissions not granted yet, will poll...")
            startPermissionPolling()
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if hasAccessibilityPermissions() {
                print("Accessibility permissions granted!")
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                self?.startObserver()
            }
        }
    }

    private func startObserver() {
        guard let pid = getNotificationCenterPID() else {
            print("ERROR: Could not find NotificationCenter process")
            return
        }

        print("Found NotificationCenter process with PID: \(pid)")

        // Create an observer for the NotificationCenter process
        var observerRef: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleNotification(element: element, notification: notification as String)
        }

        let result = AXObserverCreate(pid, callback, &observerRef)
        guard result == .success, let observer = observerRef else {
            print("ERROR: Could not create AXObserver: \(result)")
            return
        }

        self.observer = observer

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Watch for window creation, focus changes, and content updates
        let notifications = [
            kAXWindowCreatedNotification,
            kAXFocusedWindowChangedNotification,
            kAXUIElementDestroyedNotification,
            kAXMovedNotification,
            kAXResizedNotification,
            kAXValueChangedNotification,
            kAXLayoutChangedNotification
        ]

        for notif in notifications {
            let addResult = AXObserverAddNotification(observer, app, notif as CFString, refcon)
            if addResult != .success && addResult != .notificationAlreadyRegistered {
                print("Warning: Could not add notification \(notif): \(addResult)")
            }
        }

        // Add observer to run loop
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        isRunning = true
        print("Notification monitor started.")
        print("Target position: \(targetPosition.corner), offset: (\(targetPosition.offsetX), \(targetPosition.offsetY))")
        print("Scale factor: \(scaleFactor)")

        // Also reposition any existing notification windows
        repositionExistingNotifications()
    }

    deinit {
        stop()
    }

    func stop() {
        if let observer = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        observer = nil
        isRunning = false
        print("Notification monitor stopped.")
    }

    func setPosition(_ position: NotificationPosition) {
        targetPosition = position
        print("Position updated to: \(position.corner)")
        repositionExistingNotifications()
    }

    func setScaleFactor(_ factor: CGFloat) {
        scaleFactor = factor
        print("Scale factor updated to: \(factor)")
    }

    private func handleNotification(element: AXUIElement, notification: String) {
        // For window creation or content changes, process the notification
        if notification == kAXWindowCreatedNotification as String ||
           notification == kAXValueChangedNotification as String ||
           notification == kAXLayoutChangedNotification as String {
            repositionNotificationWindow(element)
        }
    }

    /// Move notification using relative positioning on the window
    private func repositionNotificationWindow(_ window: AXUIElement) {
        let bannerContainers = findAllBannerContainers(in: window)
        guard !bannerContainers.isEmpty else { return }

        for bannerContainer in bannerContainers {
            processBannerContainer(bannerContainer, in: window)
        }
    }

    private func processBannerContainer(_ bannerContainer: AXUIElement, in window: AXUIElement) {
        guard let windowSize = getSize(of: window),
              let notifSize = getSize(of: bannerContainer),
              let position = getPosition(of: bannerContainer) else {
            return
        }

        // Reposition notification (skip if topRight - the default position)
        let shouldReposition = !(targetPosition.corner == .topRight)
        if shouldReposition {
            // Cache initial data if not already cached
            if cachedInitialPosition == nil {
                cacheInitialNotificationData(windowSize: windowSize, notifSize: notifSize, position: position)
            }

            if let cachedPos = cachedInitialPosition,
               let cachedWinSize = cachedInitialWindowSize,
               let cachedNotifSize = cachedInitialNotifSize,
               let cachedPad = cachedInitialPadding {
                // Calculate new position as relative offset
                let newPosition = calculateRelativeOffset(
                    windowSize: cachedWinSize,
                    notifSize: cachedNotifSize,
                    position: cachedPos,
                    padding: cachedPad
                )

                // Set position directly on the window
                var point = CGPoint(x: newPosition.x, y: newPosition.y)
                if let value = AXValueCreate(.cgPoint, &point) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                }
            }
        }

        // Show custom notification based on rules (always check, regardless of position)
        let content = CustomNotificationManager.shared.extractContent(from: bannerContainer)
        if !content.title.isEmpty || !content.body.isEmpty {
            let identifier = getElementIdentifier(bannerContainer)

            guard shouldProcessNotification(identifier: identifier, content: content) else {
                // If this is an already-seen notification and style requests hiding, ensure system notification is dismissed
                if let style = RulesManager.shared.styleFor(content: content), style.hideSystemNotification {
                    dismissSystemNotification(bannerContainer)
                }
                return
            }

            // Record notification for history (used by Recent tab)
            NotificationHistory.shared.record(content)

            if let style = RulesManager.shared.styleFor(content: content) {
                let config = style.toConfig()
                CustomNotificationManager.shared.configure(config)
                CustomNotificationManager.shared.showNotification(content: content)

                // Hide system notification by dismissing it cleanly
                if style.hideSystemNotification {
                    hideSystemNotification(bannerContainer, window: window)
                }
            }
        }
    }

    /// Determine whether a notification should be processed or skipped as a duplicate.
    /// Records the notification in `seenBanners` and `recentNotifications` if accepted.
    func shouldProcessNotification(identifier: String?, content: NotificationContent, now: Date = Date()) -> Bool {
        guard !content.title.isEmpty || !content.body.isEmpty else {
            return false
        }

        if let id = identifier, !id.isEmpty {
            if seenBanners.contains(id) {
                return false
            }
        }

        let contentHash = "\(content.appName)|\(content.title)|\(content.subtitle)|\(content.body)"

        // Clean up old entries
        recentNotifications.removeAll { now.timeIntervalSince($0.time) > dedupeWindow }

        // Check if we've recently shown this exact notification
        if recentNotifications.contains(where: { $0.content == contentHash }) {
            if let id = identifier, !id.isEmpty {
                recordSeenBanner(id)
            }
            return false
        }

        if let id = identifier, !id.isEmpty {
            recordSeenBanner(id)
        }
        recentNotifications.append((content: contentHash, time: now))
        return true
    }

    private func recordSeenBanner(_ id: String) {
        seenBanners.insert(id)
        seenBannerOrder.append(id)
        if seenBannerOrder.count > maxSeenBanners {
            let oldest = seenBannerOrder.removeFirst()
            seenBanners.remove(oldest)
        }
    }

    /// Extract AXIdentifier string from element
    private func getElementIdentifier(_ element: AXUIElement) -> String? {
        var idRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &idRef) == .success,
           let id = idRef as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    /// Cleanly dismiss a system notification banner or alert
    @discardableResult
    private func dismissSystemNotification(_ banner: AXUIElement) -> Bool {
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(banner, &actionsRef) == .success,
           let actions = actionsRef as? [String] {
            if let closeAction = actions.first(where: { $0.contains("Close") || $0 == "AXCancel" }) {
                if AXUIElementPerformAction(banner, closeAction as CFString) == .success {
                    return true
                }
            }
        }
        if let children = getChildren(of: banner) {
            for child in children {
                if getRole(of: child) == "AXButton" {
                    if getSubrole(of: child) == "AXCloseButton" || getTitle(of: child) == "Close" {
                        if AXUIElementPerformAction(child, kAXPressAction as CFString) == .success {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    /// Hide system notification by moving the banner off-screen instantly and dismissing it cleanly
    private func hideSystemNotification(_ banner: AXUIElement, window: AXUIElement) {
        // Move the banner itself off-screen so it disappears instantly without waiting for fade-out
        var point = CGPoint(x: -5000, y: -5000)
        if let value = AXValueCreate(.cgPoint, &point) {
            let setBannerRes = AXUIElementSetAttributeValue(banner, kAXPositionAttribute as CFString, value)
            if setBannerRes != .success {
                // Fallback only if moving the banner failed
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }

        // Cleanly dismiss the notification from NotificationCenter
        dismissSystemNotification(banner)
    }

    private func findAllBannerContainers(in root: AXUIElement, maxDepth: Int = 6) -> [AXUIElement] {
        var results: [AXUIElement] = []
        let targetSubroles = [
            "AXNotificationCenterBanner",
            "AXNotificationCenterBannerWindow",
            "AXNotificationCenterAlert",
            "AXNotificationCenterNotification"
        ]

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String, targetSubroles.contains(subrole) {
            results.append(root)
            return results
        }

        guard maxDepth > 0 else { return results }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                results.append(contentsOf: findAllBannerContainers(in: child, maxDepth: maxDepth - 1))
            }
        }
        return results
    }

    private func cacheInitialNotificationData(windowSize: CGSize, notifSize: CGSize, position: CGPoint) {
        guard cachedInitialPosition == nil else { return }

        guard let screen = NSScreen.main else { return }
        let screenWidth = screen.frame.width

        var padding: CGFloat
        var effectivePosition = position

        if position.x + notifSize.width > screenWidth {
            padding = 16.0
            effectivePosition.x = screenWidth - notifSize.width - padding
        } else {
            let rightEdge = position.x + notifSize.width
            padding = screenWidth - rightEdge
        }

        cachedInitialPosition = effectivePosition
        cachedInitialWindowSize = windowSize
        cachedInitialNotifSize = notifSize
        cachedInitialPadding = padding
    }

    private func calculateRelativeOffset(
        windowSize: CGSize,
        notifSize: CGSize,
        position: CGPoint,
        padding: CGFloat
    ) -> (x: CGFloat, y: CGFloat) {
        var newX: CGFloat
        var newY: CGFloat

        guard let screen = NSScreen.main else { return (0, 0) }
        let dockSize = screen.frame.height - screen.visibleFrame.height
        let paddingAboveDock: CGFloat = 30

        // Horizontal positioning (relative offset)
        switch targetPosition.corner {
        case .topLeft, .middleLeft, .bottomLeft:
            newX = padding - position.x + targetPosition.offsetX
        case .topCenter, .center, .bottomCenter:
            newX = (windowSize.width - notifSize.width) / 2 - position.x
        case .topRight, .middleRight, .bottomRight:
            newX = -targetPosition.offsetX  // Negative moves it left from right edge
        }

        // Vertical positioning (relative offset)
        switch targetPosition.corner {
        case .topLeft, .topCenter, .topRight:
            newY = targetPosition.offsetY
        case .middleLeft, .center, .middleRight:
            newY = (windowSize.height - notifSize.height) / 2 - dockSize
        case .bottomLeft, .bottomCenter, .bottomRight:
            newY = windowSize.height - notifSize.height - dockSize - paddingAboveDock - targetPosition.offsetY
        }

        return (newX, newY)
    }

    func repositionExistingNotifications() {
        // Get all NotificationCenter windows and reposition them using the same method as new notifications
        let windows = getNotificationWindows()
        for window in windows {
            // Restore window if it was left off-screen by a previous session
            if let pos = getPosition(of: window), pos.x <= -1000 || pos.y <= -1000 {
                var origin = CGPoint.zero
                if let val = AXValueCreate(.cgPoint, &origin) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
                }
            }
            repositionNotificationWindow(window)
        }
    }
}
