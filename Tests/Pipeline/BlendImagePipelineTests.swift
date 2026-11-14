import XCTest
import SwiftUI
import SwiftLibass
import SnapshotTesting
@testable import SwiftAssRenderer

final class BlendImagePipelineTests: PipelineTestCase {
    private let pipeline = BlendImagePipeline()
    private let offsets: [TimeInterval] = [
        40.0,
        72.72,
        374.52,
        389.79,
        392.08,
        406.84,
        409.43,
        813.64,
        832.70,
        837.94,
        862.48,
        1354.62
    ]

    func test_processImage() throws {
        for subtitle in ["en", "ru", "ar"] {
            try setup(fontProvider: .fontConfig, subtitle: subtitle)
            for offset in offsets {
                let image = try XCTUnwrap(try XCTUnwrap(render(offset: offset, pipeline: pipeline)))
                assertSnapshot(
                    of: value(image: image),
                    as: .image,
                    named: snapshotName(offset: offset),
                    snapshotDirectory: snapshotsDirectory(pathComponents: platformName(), subtitle)
                )
            }
        }
    }

    func test_processImage_fontConfig_shouldNotCrash() throws {
        for subtitle in ["en", "ru", "ar"] {
            try setup(fontProvider: .fontConfig, subtitle: subtitle)
            for event in Array(UnsafeBufferPointer(start: track.pointee.events, count: Int(track.pointee.n_events))) {
                _ = render(offset: TimeInterval(event.Start) / 1000, pipeline: pipeline)
            }
        }
    }

    func test_processImage_coreText_shouldNotCrash() throws {
        for subtitle in ["en", "ru", "ar"] {
            try setup(fontProvider: .coreText, subtitle: subtitle)
            for event in Array(UnsafeBufferPointer(start: track.pointee.events, count: Int(track.pointee.n_events))) {
                _ = render(offset: TimeInterval(event.Start) / 1000, pipeline: pipeline)
            }
        }
    }

    // MARK: - Tiles from hand-built images

    private var bitmaps: [UnsafeMutableBufferPointer<UInt8>] = []

    override func tearDown() {
        bitmaps.forEach { $0.deallocate() }
        bitmaps = []
        super.tearDown()
    }

    func test_process_farApartImages_shouldMakeOneTileEach() throws {
        let top = makeImage(x: 10, y: 20, width: 6, height: 4, coverage: 255, color: 0xFFFF_FF00)
        let bottom = makeImage(x: 300, y: 900, width: 8, height: 5, coverage: 255, color: 0x0000_0000)

        let result = try XCTUnwrap(pipeline.process(images: [top, bottom], colorTransform: .identity))

        XCTAssertEqual(result.tiles.map(\.rect), [
            CGRect(x: 10, y: 20, width: 6, height: 4),
            CGRect(x: 300, y: 900, width: 8, height: 5)
        ])
        XCTAssertEqual(result.tiles.map { CGSize(width: $0.image.width, height: $0.image.height) },
                       [CGSize(width: 6, height: 4), CGSize(width: 8, height: 5)])
        XCTAssertEqual(result.boundingRect, CGRect(x: 10, y: 20, width: 298, height: 885))
    }

    func test_process_overlappingImages_shouldShareOneTile() throws {
        let first = makeImage(x: 10, y: 10, width: 10, height: 10, coverage: 255, color: 0x0000_0000)
        let second = makeImage(x: 15, y: 12, width: 10, height: 10, coverage: 255, color: 0xFFFF_FF00)

        let result = try XCTUnwrap(pipeline.process(images: [first, second], colorTransform: .identity))

        XCTAssertEqual(result.tiles.map(\.rect), [CGRect(x: 10, y: 10, width: 15, height: 12)])
    }

    func test_process_tilePixels_shouldBeTheBytesItsImageDraws() throws {
        let image = makeImage(x: 3, y: 4, width: 7, height: 5, coverage: 200, color: 0x3366_9900)

        let tile = try XCTUnwrap(pipeline.process(images: [image], colorTransform: .identity)?.tiles.first)
        let drawn = try XCTUnwrap(tile.image.dataProvider?.data as Data?)

        XCTAssertEqual(tile.bytesPerRow, tile.image.bytesPerRow)
        XCTAssertEqual(tile.pixels.count, tile.bytesPerRow * tile.image.height)
        XCTAssertEqual(tile.pixels, drawn)
    }

    func test_process_imagesAFewPixelsApart_shouldShareOneTile() throws {
        let first = makeImage(x: 0, y: 0, width: 4, height: 4, coverage: 255, color: 0x0000_0000)
        let second = makeImage(x: 8, y: 0, width: 4, height: 4, coverage: 255, color: 0x0000_0000)

        let result = try XCTUnwrap(pipeline.process(images: [first, second], colorTransform: .identity))

        XCTAssertEqual(result.tiles.map(\.rect), [CGRect(x: 0, y: 0, width: 12, height: 4)])
        // The gap between the two images stays transparent.
        XCTAssertEqual(try pixel(in: result.tiles[0], x: 6, y: 1), [0, 0, 0, 0])
    }

    func test_process_fullyTransparentImage_shouldBeSkipped() throws {
        let visible = makeImage(x: 0, y: 0, width: 4, height: 4, coverage: 255, color: 0xFFFF_FF00)
        let transparent = makeImage(x: 500, y: 500, width: 4, height: 4, coverage: 255, color: 0x0000_00FF)

        let result = try XCTUnwrap(pipeline.process(images: [visible, transparent], colorTransform: .identity))
        XCTAssertEqual(result.tiles.map(\.rect), [CGRect(x: 0, y: 0, width: 4, height: 4)])
        XCTAssertNil(pipeline.process(images: [transparent], colorTransform: .identity))
    }

    func test_process_emptyImage_shouldBeSkipped() throws {
        let empty = makeImage(x: 500, y: 500, width: 0, height: 0, coverage: 255, color: 0xFFFF_FF00)
        let visible = makeImage(x: 0, y: 0, width: 2, height: 2, coverage: 255, color: 0xFFFF_FF00)

        XCTAssertNil(pipeline.process(images: [empty], colorTransform: .identity))
        let result = try XCTUnwrap(pipeline.process(images: [empty, visible], colorTransform: .identity))
        XCTAssertEqual(result.tiles.map(\.rect), [CGRect(x: 0, y: 0, width: 2, height: 2)])
    }

    func test_process_partialCoverage_shouldWritePremultipliedBGRA() throws {
        // R 255, G 128, B 64, fully opaque colour at coverage 128.
        let image = makeImage(x: 3, y: 4, width: 2, height: 2, coverage: 128, color: 0xFF80_4000)

        let tile = try XCTUnwrap(pipeline.process(images: [image], colorTransform: .identity)?.tiles.first)

        let alpha = 128.0
        XCTAssertEqual(try pixel(in: tile, x: 1, y: 1), [
            premultiplied(64, alpha), premultiplied(128, alpha), premultiplied(255, alpha), UInt8(alpha)
        ])
        XCTAssertEqual(try pixel(in: tile, x: 1, y: 1), [32, 64, 128, 128])
    }

    func test_process_colorTransparency_shouldScaleCoverage() throws {
        // Transparency 0x80 leaves opacity 127; full coverage gives alpha 127.
        let image = makeImage(x: 0, y: 0, width: 1, height: 1, coverage: 255, color: 0xFFFF_FF80)

        let tile = try XCTUnwrap(pipeline.process(images: [image], colorTransform: .identity)?.tiles.first)

        XCTAssertEqual(try pixel(in: tile, x: 0, y: 0), [127, 127, 127, 127])
    }

    func test_process_laterImage_shouldBeDrawnOverEarlier() throws {
        let border = makeImage(x: 0, y: 0, width: 4, height: 4, coverage: 255, color: 0x0000_0000)
        let fill = makeImage(x: 1, y: 1, width: 2, height: 2, coverage: 128, color: 0xFFFF_FF00)

        let tile = try XCTUnwrap(pipeline.process(images: [border, fill], colorTransform: .identity)?.tiles.first)

        // White at alpha 128 over opaque black: 255 * 128 / 255 + 0, alpha 128 + 255 * 127 / 255.
        let white = premultiplied(255, 128)
        XCTAssertEqual(try pixel(in: tile, x: 0, y: 0), [0, 0, 0, 255])
        XCTAssertEqual(try pixel(in: tile, x: 2, y: 2), [white, white, white, 255])
    }

    func test_process_shouldApplyColorTransform() throws {
        let transform = AssColorTransform(
            scriptMatrix: 3,
            video: VideoColorimetry(matrix: .bt709, isFullRange: false)
        )
        let color: UInt32 = 0xC828_3C00
        let converted = transform.apply(to: color)
        XCTAssertNotEqual(converted, color)
        let image = makeImage(x: 0, y: 0, width: 1, height: 1, coverage: 255, color: color)

        let tile = try XCTUnwrap(pipeline.process(images: [image], colorTransform: transform)?.tiles.first)

        XCTAssertEqual(try pixel(in: tile, x: 0, y: 0), [
            UInt8((converted >> 8) & 0xFF), UInt8((converted >> 16) & 0xFF), UInt8(converted >> 24), 255
        ])
    }

    private func makeImage(x: Int32, y: Int32, width: Int32, height: Int32, coverage: UInt8, color: UInt32) -> ASS_Image {
        // Stride wider than the image, so a blend that ignores it reads the padding.
        let stride = Int(width) + 3
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: max(stride * Int(height), 1))
        buffer.initialize(repeating: 0)
        for row in 0..<Int(height) {
            for column in 0..<Int(width) { buffer[row * stride + column] = coverage }
        }
        bitmaps.append(buffer)
        var image = ASS_Image()
        image.w = width
        image.h = height
        image.stride = Int32(stride)
        image.bitmap = buffer.baseAddress
        image.color = color
        image.dst_x = x
        image.dst_y = y
        return image
    }

    /// Bytes B, G, R, A of one tile pixel.
    private func pixel(in tile: ProcessedImage.Tile, x: Int, y: Int) throws -> [UInt8] {
        let data = try XCTUnwrap(tile.image.dataProvider?.data as Data?)
        let offset = y * tile.image.bytesPerRow + x * 4
        return Array(data[offset..<offset + 4])
    }

    private func premultiplied(_ channel: Double, _ alpha: Double) -> UInt8 {
        UInt8((channel * alpha / 255).rounded())
    }
}
