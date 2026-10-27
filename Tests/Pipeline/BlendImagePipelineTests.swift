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
}
