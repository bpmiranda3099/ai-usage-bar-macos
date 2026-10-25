import AppKit

/// Status bar icon: a filled variant of the Lucide "bot-message-square" icon on a 24x24 grid.
public enum StatusBarIcon {
    public static func make(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            context.cgContext.scaleBy(x: rect.width / 24, y: rect.height / 24)
            NSColor.black.set()

            body().fill()

            let strokes = NSBezierPath()
            strokes.lineWidth = 2
            strokes.lineCapStyle = .round
            strokes.lineJoinStyle = .round
            strokes.move(to: NSPoint(x: 12, y: 6))
            strokes.line(to: NSPoint(x: 12, y: 2))
            strokes.line(to: NSPoint(x: 8, y: 2))
            strokes.move(to: NSPoint(x: 2, y: 12))
            strokes.line(to: NSPoint(x: 4, y: 12))
            strokes.move(to: NSPoint(x: 20, y: 12))
            strokes.line(to: NSPoint(x: 22, y: 12))
            strokes.stroke()

            // Eyes are cut out of the filled body.
            context.compositingOperation = .destinationOut
            let eyes = NSBezierPath()
            eyes.lineWidth = 2
            eyes.lineCapStyle = .round
            eyes.move(to: NSPoint(x: 9, y: 11))
            eyes.line(to: NSPoint(x: 9, y: 13))
            eyes.move(to: NSPoint(x: 15, y: 11))
            eyes.line(to: NSPoint(x: 15, y: 13))
            eyes.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Usage"
        return image
    }

    private static func body() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 20, y: 16))
        path.curve(to: NSPoint(x: 18, y: 18), controlPoint1: NSPoint(x: 20, y: 17.1), controlPoint2: NSPoint(x: 19.1, y: 18))
        path.line(to: NSPoint(x: 8.828, y: 18))
        path.curve(to: NSPoint(x: 7.414, y: 18.586), controlPoint1: NSPoint(x: 8.3, y: 18), controlPoint2: NSPoint(x: 7.76, y: 18.2))
        path.line(to: NSPoint(x: 5.212, y: 20.788))
        path.curve(to: NSPoint(x: 4, y: 20.286), controlPoint1: NSPoint(x: 4.5, y: 21.1), controlPoint2: NSPoint(x: 4, y: 20.85))
        path.line(to: NSPoint(x: 4, y: 8))
        path.curve(to: NSPoint(x: 6, y: 6), controlPoint1: NSPoint(x: 4, y: 6.9), controlPoint2: NSPoint(x: 4.9, y: 6))
        path.line(to: NSPoint(x: 18, y: 6))
        path.curve(to: NSPoint(x: 20, y: 8), controlPoint1: NSPoint(x: 19.1, y: 6), controlPoint2: NSPoint(x: 20, y: 6.9))
        path.close()
        return path
    }
}
