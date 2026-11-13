import CoreGraphics

/// One rendered subtitle frame: premultiplied bitmaps and where each sits on the canvas.
///
/// Separate regions of the frame (a sign at the top, dialogue at the bottom) are separate tiles, so the empty
/// space between them is never allocated, blended or uploaded.
public struct ProcessedImage: Equatable, Sendable {
    public struct Tile: Equatable, Sendable {
        public let image: CGImage
        /// Where the tile is drawn on the canvas, in canvas points with a top-left origin.
        public let rect: CGRect

        public init(image: CGImage, rect: CGRect) {
            self.image = image
            self.rect = rect
        }
    }

    /// Tiles in drawing order; they never overlap.
    public let tiles: [Tile]

    public init(tiles: [Tile]) {
        self.tiles = tiles
    }

    /// The smallest rect holding every tile.
    public var boundingRect: CGRect {
        tiles.dropFirst().reduce(tiles.first?.rect ?? .null) { $0.union($1.rect) }
    }
}
