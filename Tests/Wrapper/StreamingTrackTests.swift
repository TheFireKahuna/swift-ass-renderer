import XCTest
import SwiftLibass
@testable import SwiftAssRenderer

/// A track started from a header and fed events one at a time, the way a Matroska stream carries them.
final class StreamingTrackTests: PipelineTestCase {
    private let pipeline = BlendImagePipeline()

    /// No `[Events]` section: libass falls back to the Matroska event format.
    private let header = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: 640
    PlayResY: 360
    YCbCr Matrix: TV.709

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, \
    Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, \
    MarginR, MarginV, Encoding
    Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1

    """

    override func setUpWithError() throws {
        try super.setUpWithError()
        try setupLibrary(fontProvider: .fontConfig)
    }

    override func tearDown() {
        track.map(LibraryWrapper.freeTrack)
        track = nil
        super.tearDown()
    }

    func test_newTrack_withoutEventsSection_shouldParseHeader() throws {
        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: header))

        XCTAssertEqual(track.pointee.PlayResX, 640)
        XCTAssertEqual(track.pointee.PlayResY, 360)
        XCTAssertEqual(track.pointee.n_events, 0)
        XCTAssertNotNil(styleNames().firstIndex(of: "Default"))
        XCTAssertEqual(LibraryWrapper.colorMatrix(of: track), Int32(YCBCR_BT709_TV.rawValue))
    }

    func test_newTrack_withNULTerminatedHeader_shouldParseWholeHeader() throws {
        let terminated = header.replacingOccurrences(of: "[V4+ Styles]", with: "\0[V4+ Styles]") + "\0"

        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: terminated))

        XCTAssertNotNil(styleNames().firstIndex(of: "Default"))
    }

    func test_colorMatrix_withoutHeaderLine_shouldBeDefault() throws {
        let withoutMatrix = header.replacingOccurrences(of: "YCbCr Matrix: TV.709\n", with: "")

        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: withoutMatrix))

        XCTAssertEqual(LibraryWrapper.colorMatrix(of: track), Int32(YCBCR_DEFAULT.rawValue))
    }

    func test_processChunk_shouldKeepTimingInMilliseconds() throws {
        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: header))

        // 4.004 s is 4003.9999... ms in binary floating point; it must still land on 4004.
        XCTAssertLessThan(4.004 * 1000, 4004)
        LibraryWrapper.processChunk(track, event: AssEvent(line: "0,0,Default,,0,0,0,,text", start: 4.004, duration: 1.001))

        let event = try XCTUnwrap(events().first)
        XCTAssertEqual(event.Start, 4004)
        XCTAssertEqual(event.Duration, 1001)
    }

    func test_renderImage_atFrameTimeJustBelowWholeMillisecond_shouldShowEventStartingThere() throws {
        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: header))
        LibraryWrapper.processChunk(track, event: square(readOrder: 0, color: "FFFFFF", start: 4.004))

        XCTAssertNotNil(LibraryWrapper.renderImage(renderer, track: &track.pointee, at: 4.004).image)
        XCTAssertNil(LibraryWrapper.renderImage(renderer, track: &track.pointee, at: 4.002).image)
    }

    func test_processChunk_withReadOrderZeroOnEveryEvent_shouldKeepAll() throws {
        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: header))

        for (index, text) in ["one", "two", "three"].enumerated() {
            LibraryWrapper.processChunk(track, event: AssEvent(
                line: "0,0,Default,,0,0,0,,\(text)", start: Double(index), duration: 5
            ))
        }

        XCTAssertEqual(track.pointee.n_events, 3)
        XCTAssertEqual(events().map { String(cString: $0.Text) }, ["one", "two", "three"])
    }

    func test_sameLayerAndStart_shouldDrawLaterReadOrderOnTop_whenAppendedInReverse() throws {
        // ReadOrder 1 black, ReadOrder 2 white: white on top.
        XCTAssertEqual(try topColor(events: [
            square(readOrder: 2, color: "FFFFFF"),
            square(readOrder: 1, color: "000000")
        ]), [255, 255, 255, 255])
    }

    func test_sameLayerAndStart_shouldDrawLaterReadOrderOnTop_whenAppendedInOrder() throws {
        XCTAssertEqual(try topColor(events: [
            square(readOrder: 1, color: "000000"),
            square(readOrder: 2, color: "FFFFFF")
        ]), [255, 255, 255, 255])
    }

    func test_sameLayerAndStart_shouldStackByReadOrderNotColor() throws {
        // ReadOrder 1 white, ReadOrder 2 black, appended in reverse: black on top.
        XCTAssertEqual(try topColor(events: [
            square(readOrder: 2, color: "000000"),
            square(readOrder: 1, color: "FFFFFF")
        ]), [0, 0, 0, 255])
    }
}

private extension StreamingTrackTests {
    /// An opaque 100 x 100 script-pixel square at the top-left, with no border or shadow. Needs no font.
    func square(readOrder: Int, color: String, start: TimeInterval = 1) -> AssEvent {
        AssEvent(
            line: "\(readOrder),0,Default,,0,0,0,,{\\an7\\pos(0,0)\\bord0\\shad0\\1c&H\(color)&\\p1}"
                + "m 0 0 l 100 0 100 100 0 100",
            start: start,
            duration: 2
        )
    }

    /// The B, G, R, A of the composited frame at the centre of the squares.
    func topColor(events: [AssEvent]) throws -> [UInt8] {
        track = try XCTUnwrap(LibraryWrapper.newTrack(library, header: header))
        events.forEach { LibraryWrapper.processChunk(track, event: $0) }
        XCTAssertEqual(track.pointee.n_events, Int32(events.count))

        let image = try XCTUnwrap(render(offset: 2, pipeline: pipeline))
        // Script pixel 50 at canvas scale 3 (640 x 360 script on a 1920 x 1080 canvas).
        let point = CGPoint(x: 150, y: 150)
        let tile = try XCTUnwrap(image.tiles.first { $0.rect.contains(point) })
        let data = try XCTUnwrap(tile.image.dataProvider?.data as Data?)
        let offset = Int(point.y - tile.rect.minY) * tile.image.bytesPerRow + Int(point.x - tile.rect.minX) * 4
        return Array(data[offset..<offset + 4])
    }

    func events() -> [ASS_Event] {
        Array(UnsafeBufferPointer(start: track.pointee.events, count: Int(track.pointee.n_events)))
    }

    func styleNames() -> [String] {
        UnsafeBufferPointer(start: track.pointee.styles, count: Int(track.pointee.n_styles))
            .compactMap { $0.Name.map { String(cString: $0) } }
    }
}
