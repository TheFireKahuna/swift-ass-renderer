import CoreGraphics
import Foundation

/// One rendered subtitle frame: premultiplied bitmaps and where each sits on the canvas.
///
/// Separate regions of the frame (a sign at the top, dialogue at the bottom) are separate tiles, so the empty
/// space between them is never allocated, blended or uploaded.
public struct ProcessedImage: Equatable, Sendable {
    public struct Tile: Equatable, Sendable {
        public let image: CGImage
        /// Where the tile is drawn on the canvas, in canvas points with a top-left origin.
        public let rect: CGRect
        /// The image's pixels, premultiplied BGRA (B, G, R, A in memory), top row first: the same memory the image
        /// reads, for a host that uploads them itself.
        public let pixels: Data
        public let bytesPerRow: Int

        public init(image: CGImage, rect: CGRect, pixels: Data, bytesPerRow: Int) {
            self.image = image
            self.rect = rect
            self.pixels = pixels
            self.bytesPerRow = bytesPerRow
        }

        /// Same image at the same place. The pixels are the image's, so comparing them again would only cost a
        /// byte-by-byte pass.
        public static func == (lhs: Tile, rhs: Tile) -> Bool {
            lhs.image === rhs.image && lhs.rect == rhs.rect
        }

        /// The same pixels drawn at another rect.
        public func moved(to rect: CGRect) -> Tile {
            Tile(image: image, rect: rect, pixels: pixels, bytesPerRow: bytesPerRow)
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
