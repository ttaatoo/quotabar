import AppKit

enum StatusItemRenderer {
    private static let height: CGFloat = 22
    private static let horizontalPad: CGFloat = 7
    private static let logoWidth: CGFloat = 11
    private static let gap: CGFloat = 5
    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// Fixed menu-bar slot and pill width, sized once for the widest label (`100%`).
    static let itemWidth: CGFloat = measuredItemWidth()

    static func image(text: String, warning: Bool) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: warning
                ? NSColor(calibratedRed: 1, green: 0.48, blue: 0.10, alpha: 1)
                : NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let width = itemWidth

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1.5), xRadius: 7, yRadius: 7)
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
            pill.fill()
            NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
            pill.lineWidth = 1
            pill.stroke()

            drawLogo(in: NSRect(x: horizontalPad, y: (rect.height - 11) / 2, width: 11, height: 11))

            let textSlotMaxX = width - horizontalPad
            let textOrigin = NSPoint(
                x: textSlotMaxX - textSize.width,
                y: (rect.height - textSize.height) / 2 - 0.5
            )
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func measuredItemWidth() -> CGFloat {
        let textWidth = ("100%" as NSString).size(withAttributes: [.font: labelFont]).width
        return ceil(horizontalPad + logoWidth + gap + textWidth + horizontalPad)
    }

    private static func drawLogo(in rect: NSRect) {
        let colors = [
            NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.71, green: 0.42, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.59, alpha: 1)
        ]
        let heights: [CGFloat] = [0.42, 0.68, 1.0]
        let barWidth = rect.width / 4.6
        let spacing = (rect.width - barWidth * 3) / 2

        for index in 0..<3 {
            let barHeight = rect.height * heights[index]
            let x = rect.minX + CGFloat(index) * (barWidth + spacing)
            let bar = NSRect(x: x, y: rect.minY, width: barWidth, height: barHeight)
            colors[index].setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.1, yRadius: 1.1).fill()
        }
    }
}
