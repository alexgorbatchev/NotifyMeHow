import Cocoa

/// Banner geometry in points, laid out like a macOS notification: the icon on the left, a text
/// column beside it, and the copy button in the top-right corner. Style values are multiplied by
/// the scale factor.
struct BannerMetrics {
    let width: CGFloat
    let padding: CGFloat
    let iconSize: CGFloat
    let cornerRadius: CGFloat
    /// Space between the icon and the text column (matches the padding, as on macOS)
    let iconGap: CGFloat
    let copyButtonSize: CGFloat
    let copyButtonGap: CGFloat
    /// Vertical space between the title, subtitle and body lines
    let lineSpacing: CGFloat
    let textLeading: CGFloat
    let textWidth: CGFloat
    let minimumHeight: CGFloat

    init(config: CustomNotificationConfig, hasIcon: Bool) {
        let scale = config.scaleFactor
        width = config.width * scale
        padding = config.padding * scale
        iconSize = hasIcon ? config.iconSize * scale : 0
        cornerRadius = config.cornerRadius * scale
        iconGap = hasIcon ? padding : 0
        copyButtonSize = 20 * scale
        copyButtonGap = 8 * scale
        lineSpacing = 2 * scale
        textLeading = padding + iconSize + iconGap
        textWidth = width - textLeading - padding - copyButtonSize - copyButtonGap
        minimumHeight = max(iconSize, copyButtonSize) + padding * 2
    }
}
