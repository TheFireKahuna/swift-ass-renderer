import CoreGraphics

/// Distance, in points, from the video picture to each edge of the canvas.
///
/// Positive values leave empty bands around the picture. Negative values mean the picture extends past
/// the canvas, such as when the video is zoomed (pan and scan).
public struct FrameMargins: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat
    public var right: CGFloat

    public static let zero = FrameMargins(top: 0, bottom: 0, left: 0, right: 0)

    public init(top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    static func * (margins: FrameMargins, scale: CGFloat) -> FrameMargins {
        FrameMargins(
            top: margins.top * scale,
            bottom: margins.bottom * scale,
            left: margins.left * scale,
            right: margins.right * scale
        )
    }
}
