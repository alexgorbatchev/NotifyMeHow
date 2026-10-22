import Cocoa

/// Computes where a banner sits in the stack of visible custom notifications.
enum NotificationStackLayout {
    /// Vertical space between stacked banners.
    static let gap: CGFloat = 16

    /// - Parameters:
    ///   - precedingHeights: heights of the banners shown before this one, oldest first.
    ///   - firstHeight: height of the oldest visible banner, used to align centered stacks.
    static func origin(
        for size: CGSize,
        position: NotificationPosition,
        screenFrame: CGRect,
        precedingHeights: [CGFloat],
        firstHeight: CGFloat?
    ) -> CGPoint {
        var x: CGFloat
        var y: CGFloat

        switch position.corner {
        case .topRight, .middleRight, .bottomRight:
            x = screenFrame.maxX - size.width - position.offsetX
        case .topLeft, .middleLeft, .bottomLeft:
            x = screenFrame.minX + position.offsetX
        case .topCenter, .center, .bottomCenter:
            x = screenFrame.midX - size.width / 2
        }

        switch position.corner {
        case .topLeft, .topCenter, .topRight:
            y = screenFrame.maxY - size.height - position.offsetY
        case .middleLeft, .center, .middleRight:
            y = screenFrame.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = screenFrame.minY + position.offsetY
        }

        var stackOffset = precedingHeights.reduce(CGFloat.zero) { $0 + $1 + gap }
        switch position.corner {
        case .topLeft, .topCenter, .topRight:
            y -= stackOffset
        case .bottomLeft, .bottomCenter, .bottomRight:
            y += stackOffset
        case .middleLeft, .center, .middleRight:
            // Centered banners start relative to their own height; align to the first
            // banner's top edge so mixed-height windows keep the same visible gap.
            if let firstHeight {
                stackOffset += (size.height - firstHeight) / 2
            }
            y -= stackOffset
        }

        // Clamp to screen bounds to prevent off-screen notifications
        // (e.g., when importing settings from a different screen size)
        x = max(screenFrame.minX, min(x, screenFrame.maxX - size.width))
        y = max(screenFrame.minY, min(y, screenFrame.maxY - size.height))

        return CGPoint(x: x, y: y)
    }
}
