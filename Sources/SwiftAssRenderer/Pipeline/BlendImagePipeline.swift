import CoreGraphics
import SwiftLibass
import SwiftAssBlend

/// Composites a frame's images into premultiplied BGRA tiles, the format Core Animation draws without
/// converting.
///
/// Images whose rects come within `tileGap` pixels of each other share a tile; regions further apart get
/// their own, so a frame with a sign at the top and dialogue at the bottom costs two small bitmaps rather
/// than one spanning the screen. Images in different tiles never share a pixel, so the tiles can be drawn
/// in any order.
public final class BlendImagePipeline: ImagePipelineType {
    private static let tileGap = 8
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    )

    public init() {}

    public func process(images: [ASS_Image], colorTransform: AssColorTransform) -> ProcessedImage? {
        let visible = images.filter { $0.w > 0 && $0.h > 0 && ($0.color & 0xFF) != 0xFF }
        guard !visible.isEmpty else { return nil }
        let tiles = Self.clusters(of: visible).compactMap { members in
            Self.tile(for: members.map { visible[$0] }, colorTransform: colorTransform)
        }
        return tiles.isEmpty ? nil : ProcessedImage(tiles: tiles)
    }

    /// Groups of image indices whose padded rects touch, each group in drawing order.
    static func clusters(of images: [ASS_Image]) -> [[Int]] {
        var parent = Array(images.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        // Half the gap on each rect: two rects touch once they come within `tileGap` of each other.
        let pad = tileGap / 2
        let padded = images.map { image in
            (minX: Int(image.dst_x) - pad, minY: Int(image.dst_y) - pad,
             maxX: Int(image.dst_x) + Int(image.w) + pad, maxY: Int(image.dst_y) + Int(image.h) + pad)
        }
        for i in images.indices {
            for j in images.indices where j > i {
                let a = padded[i], b = padded[j]
                guard a.minX < b.maxX, b.minX < a.maxX, a.minY < b.maxY, b.minY < a.maxY else { continue }
                let ri = root(i), rj = root(j)
                if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
            }
        }
        var groups: [Int: [Int]] = [:]
        var order: [Int] = []
        for i in images.indices {
            let r = root(i)
            if groups[r] == nil { order.append(r) }
            groups[r, default: []].append(i)
        }
        return order.compactMap { groups[$0] }
    }

    private static func tile(for images: [ASS_Image], colorTransform: AssColorTransform) -> ProcessedImage.Tile? {
        let minX = images.map { Int($0.dst_x) }.min()!
        let minY = images.map { Int($0.dst_y) }.min()!
        let maxX = images.map { Int($0.dst_x) + Int($0.w) }.max()!
        let maxY = images.map { Int($0.dst_y) + Int($0.h) }.max()!
        let width = maxX - minX
        let height = maxY - minY
        let stride = width * 4
        let byteCount = stride * height
        guard width > 0, height > 0, let pixels = calloc(byteCount, 1) else { return nil }

        let tile = pixels.assumingMemoryBound(to: UInt8.self)
        for var image in images {
            ass_blend_image_into_tile(tile, stride, Int32(minX), Int32(minY), &image,
                                      colorTransform.apply(to: image.color))
        }

        guard let provider = CGDataProvider(
            dataInfo: nil, data: pixels, size: byteCount,
            releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }
        ) else {
            free(pixels)
            return nil
        }
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
            space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        ) else {
            return nil
        }
        return ProcessedImage.Tile(image: image, rect: CGRect(x: minX, y: minY, width: width, height: height))
    }
}
