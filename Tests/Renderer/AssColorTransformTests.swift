import XCTest
@testable import SwiftAssRenderer

final class AssColorTransformTests: XCTestCase {
    private let bt601TV: Int32 = 3
    private let bt601PC: Int32 = 4
    private let bt709TV: Int32 = 5
    private let defaultMatrix: Int32 = 0
    private let unknownMatrix: Int32 = 1
    private let noneMatrix: Int32 = 2

    private let bt709Limited = VideoColorimetry(matrix: .bt709, isFullRange: false)
    private let bt601Limited = VideoColorimetry(matrix: .bt601, isFullRange: false)

    func test_sameMatrixAndRange_isIdentity() {
        XCTAssertEqual(AssColorTransform(scriptMatrix: bt709TV, video: bt709Limited), .identity)
        XCTAssertEqual(AssColorTransform(scriptMatrix: bt601TV, video: bt601Limited), .identity)
        XCTAssertEqual(AssColorTransform(scriptMatrix: bt601PC, video: VideoColorimetry(matrix: .bt601, isFullRange: true)),
                       .identity)
    }

    func test_defaultMatrix_isBT601Limited() {
        XCTAssertEqual(AssColorTransform(scriptMatrix: defaultMatrix, video: bt601Limited), .identity)
        XCTAssertEqual(
            AssColorTransform(scriptMatrix: defaultMatrix, video: bt709Limited),
            AssColorTransform(scriptMatrix: bt601TV, video: bt709Limited)
        )
    }

    func test_rgbVideo_isIdentity() {
        for isFullRange in [false, true] {
            let video = VideoColorimetry(matrix: .rgb, isFullRange: isFullRange)
            XCTAssertEqual(AssColorTransform(scriptMatrix: bt601TV, video: video), .identity)
            XCTAssertEqual(AssColorTransform(scriptMatrix: defaultMatrix, video: video), .identity)
        }
    }

    func test_noneAndUnknownMatrix_isIdentity() {
        for matrix in [unknownMatrix, noneMatrix] {
            XCTAssertEqual(AssColorTransform(scriptMatrix: matrix, video: bt709Limited), .identity)
            XCTAssertEqual(AssColorTransform(scriptMatrix: matrix, video: bt601Limited), .identity)
        }
    }

    func test_unknownVideo_isIdentity() {
        XCTAssertEqual(AssColorTransform(scriptMatrix: bt601TV, video: nil), .identity)
    }

    func test_identity_returnsColorUnchanged() {
        XCTAssertEqual(AssColorTransform.identity.apply(to: 0x12345678), 0x12345678)
    }

    func test_bt601TVScriptOnBT709TVVideo_keepsWhiteAndBlack() {
        let transform = AssColorTransform(scriptMatrix: bt601TV, video: bt709Limited)
        XCTAssertFalse(transform.isIdentity)

        assertColor(transform.apply(to: 0xFFFF_FF00), equals: (255, 255, 255), within: 1)
        assertColor(transform.apply(to: 0x0000_0000), equals: (0, 0, 0), within: 1)
        // Greys have no chroma, so no matrix moves them.
        assertColor(transform.apply(to: 0x8080_8000), equals: (128, 128, 128), within: 1)
    }

    func test_bt601TVScriptOnBT709TVVideo_movesSaturatedColorsByTheMatrixDifference() {
        let transform = AssColorTransform(scriptMatrix: bt601TV, video: bt709Limited)
        let colors: [(Double, Double, Double)] = [(200, 40, 60), (40, 180, 70), (60, 80, 210), (230, 200, 30)]

        for color in colors {
            let expected = reencode(color, from: (kr: 0.299, kb: 0.114), to: (kr: 0.2126, kb: 0.0722))
            let moved = max(abs(expected.0 - color.0), abs(expected.1 - color.1), abs(expected.2 - color.2))
            XCTAssertGreaterThanOrEqual(moved, 3, "\(color) should move visibly")

            let input = UInt32(color.0) << 24 | UInt32(color.1) << 16 | UInt32(color.2) << 8
            assertColor(transform.apply(to: input), equals: (Int(expected.0), Int(expected.1), Int(expected.2)), within: 1)
        }
    }

    func test_bt601FullRangeScriptOnBT601LimitedVideo_expandsRange() {
        let transform = AssColorTransform(scriptMatrix: bt601PC, video: bt601Limited)

        // Full-range Y 128 read as limited range: (128 - 16) / 219.
        let grey = Int(((128.0 - 16) / 219 * 255).rounded())
        assertColor(transform.apply(to: 0x8080_8000), equals: (grey, grey, grey), within: 1)
        assertColor(transform.apply(to: 0xFFFF_FF00), equals: (255, 255, 255), within: 0)
        assertColor(transform.apply(to: 0x0000_0000), equals: (0, 0, 0), within: 0)
    }

    func test_apply_preservesTransparencyByte() {
        let transform = AssColorTransform(scriptMatrix: bt601TV, video: bt709Limited)

        for alpha: UInt32 in [0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF] {
            XCTAssertEqual(transform.apply(to: 0xC828_3C00 | alpha) & 0xFF, alpha)
        }
    }
}

private extension AssColorTransformTests {
    /// Limited-range 8-bit encode with one matrix, decode with the other, from the standard Kr/Kb equations.
    /// Returns rounded, clamped 8-bit RGB.
    func reencode(
        _ rgb: (Double, Double, Double),
        from source: (kr: Double, kb: Double),
        to target: (kr: Double, kb: Double)
    ) -> (Double, Double, Double) {
        let (r, g, b) = (rgb.0 / 255, rgb.1 / 255, rgb.2 / 255)
        let sourceKg = 1 - source.kr - source.kb
        let luma = source.kr * r + sourceKg * g + source.kb * b
        let y = 16 + 219 * luma
        let cb = 128 + 224 * (b - luma) / (2 * (1 - source.kb))
        let cr = 128 + 224 * (r - luma) / (2 * (1 - source.kr))

        let decodedLuma = (y - 16) / 219
        let pb = (cb - 128) / 224
        let pr = (cr - 128) / 224
        let outR = decodedLuma + 2 * (1 - target.kr) * pr
        let outB = decodedLuma + 2 * (1 - target.kb) * pb
        let outG = (decodedLuma - target.kr * outR - target.kb * outB) / (1 - target.kr - target.kb)

        func byte(_ value: Double) -> Double { (min(max(value, 0), 1) * 255).rounded() }
        return (byte(outR), byte(outG), byte(outB))
    }

    func assertColor(
        _ color: UInt32,
        equals expected: (Int, Int, Int),
        within tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = (Int(color >> 24), Int((color >> 16) & 0xFF), Int((color >> 8) & 0xFF))
        let delta = max(abs(actual.0 - expected.0), abs(actual.1 - expected.1), abs(actual.2 - expected.2))
        XCTAssertLessThanOrEqual(delta, tolerance, "got \(actual), expected \(expected)", file: file, line: line)
    }
}
