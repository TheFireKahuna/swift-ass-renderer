import XCTest
import SwiftUI
import SwiftLibass
import SnapshotTesting
@testable import SwiftAssRenderer

open class PipelineTestCase: XCTestCase {
    let canvasSize = CGSize(width: 640, height: 360)
    let canvasScale = 3.0

    open var library: OpaquePointer!
    open var renderer: OpaquePointer!
    open var track: UnsafeMutablePointer<ASS_Track>!

    func render(
        offset: TimeInterval,
        pipeline: ImagePipelineType,
        colorTransform: AssColorTransform = .identity
    ) -> ProcessedImage? {
        guard let image = LibraryWrapper.renderImage(renderer, track: &track.pointee, at: offset).image else {
            return nil
        }
        return pipeline.process(images: linkedImages(from: image), colorTransform: colorTransform)
    }

    func snapshotName(offset: TimeInterval) -> String {
        "\(String(offset).split(separator: ".").joined(separator: "_"))"
    }

    /// All tiles drawn into one bitmap the size of their bounding rect, each at its place relative to it, so
    /// the snapshot is one image like the references (separate tile layers would be filtered at their edges).
    func value(image: ProcessedImage) -> CALayer {
        let boundingRect = image.boundingRect
        let width = Int(boundingRect.width), height = Int(boundingRect.height)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.setBlendMode(.copy)
        for tile in image.tiles {
            // Tile rects have a top-left origin; Core Graphics draws from the bottom left.
            context.draw(tile.image, in: CGRect(
                x: tile.rect.minX - boundingRect.minX,
                y: boundingRect.maxY - tile.rect.maxY,
                width: tile.rect.width,
                height: tile.rect.height
            ))
        }
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: boundingRect.size)
        layer.contents = context.makeImage()
        layer.contentsGravity = .center

        return layer
    }

    /// Library and renderer at the canvas size, with the test fonts; no track.
    func setupLibrary(fontProvider: FontProvider) throws {
        library = try XCTUnwrap(LibraryWrapper.libraryInit())
        renderer = try XCTUnwrap(LibraryWrapper.rendererInit(library))
        LibraryWrapper.setRendererSize(renderer, size: canvasSize * canvasScale)
        let fontsPath = try XCTUnwrap(Bundle.module.resourceURL)
        let fontConfig = FontConfig(fontsPath: fontsPath.appendingPathComponent("Fonts"), fontProvider: fontProvider)
        try fontConfig.configure(library: library, renderer: renderer)
    }

    func setup(fontProvider: FontProvider, subtitle: String) throws {
        try setupLibrary(fontProvider: fontProvider)
        let contentsPath = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Subs/\(subtitle).ass"))
        let content = try String(contentsOfFile: contentsPath.path)
        track = try XCTUnwrap(LibraryWrapper.readTrack(library, content: content))
    }
}
