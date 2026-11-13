import CoreGraphics
import SwiftLibass

/// Pipeline that turns a frame's `ASS_Image` list into a ``ProcessedImage`` that can be drawn on the screen.
public protocol ImagePipelineType: Sendable {
    /// - Parameters:
    ///   - images: The frame's images in libass's drawing order. Rects are in canvas pixels.
    ///   - colorTransform: Applied to every image colour before it is drawn.
    /// - Returns: Tiles with rects in canvas pixels, or nil when nothing is visible.
    func process(images: [ASS_Image], colorTransform: AssColorTransform) -> ProcessedImage?
}
