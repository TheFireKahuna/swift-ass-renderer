import Foundation

/// How the video's YCbCr is turned into the RGB on screen.
public struct VideoColorimetry: Equatable, Sendable {
    public enum Matrix: Equatable, Sendable {
        case bt601
        case bt709
        case smpte240m
        case fcc
        case bt2020NonConstantLuminance
        /// The video is RGB: there is no YCbCr step for a script's colours to disagree with.
        case rgb
    }

    public var matrix: Matrix
    public var isFullRange: Bool

    public init(matrix: Matrix, isFullRange: Bool) {
        self.matrix = matrix
        self.isFullRange = isFullRange
    }
}

/// Maps the colours a script was written in onto the colours the video is shown in.
///
/// Typesetters pick colours off the video as their tools decoded it, with the YCbCr matrix the script's
/// `YCbCr Matrix` header names (BT.601 limited range when the header is missing, as VSFilter assumed). When
/// the player decodes the video with a different matrix, the same picture comes out in different RGB, and a
/// sign colour-matched to a wall no longer matches it. Re-encoding each colour with the script's matrix and
/// decoding it with the video's gives the colour the typesetter saw on that wall.
public struct AssColorTransform: Equatable, Sendable {
    /// Row-major 3x3 on RGB in 0...1, then `offset`.
    private let matrix: [Double]
    private let offset: [Double]

    public static let identity = AssColorTransform(matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1], offset: [0, 0, 0])

    public var isIdentity: Bool { self == .identity }

    /// - Parameters:
    ///   - scriptMatrix: The track's `ASS_YCbCrMatrix` value.
    ///   - video: How the video is decoded; nil when unknown, which leaves colours as authored.
    public init(scriptMatrix: Int32, video: VideoColorimetry?) {
        guard let video,
              let script = Encoding(assMatrix: scriptMatrix),
              let shown = Encoding(video: video),
              script != shown else {
            self = .identity
            return
        }
        let encode = script.rgbToCoded
        let decode = shown.rgbToCoded.inverted
        self = decode.then(after: encode)
    }

    private init(matrix: [Double], offset: [Double]) {
        self.matrix = matrix
        self.offset = offset
    }

    /// Applies the transform to libass's RRGGBBTT colour, keeping the transparency byte.
    public func apply(to color: UInt32) -> UInt32 {
        if isIdentity { return color }
        let rgb = [Double((color >> 24) & 0xFF), Double((color >> 16) & 0xFF), Double((color >> 8) & 0xFF)]
            .map { $0 / 255 }
        var out: UInt32 = color & 0xFF
        for row in 0..<3 {
            let value = matrix[row * 3] * rgb[0] + matrix[row * 3 + 1] * rgb[1] + matrix[row * 3 + 2] * rgb[2]
                + offset[row]
            let byte = UInt32((min(max(value, 0), 1) * 255).rounded())
            out |= byte << (24 - 8 * UInt32(row))
        }
        return out
    }

    /// `self` applied to the output of `first`.
    private func then(after first: AssColorTransform) -> AssColorTransform {
        var m = [Double](repeating: 0, count: 9)
        var o = offset
        for row in 0..<3 {
            for col in 0..<3 {
                m[row * 3 + col] = (0..<3).reduce(0) { $0 + matrix[row * 3 + $1] * first.matrix[$1 * 3 + col] }
            }
            o[row] += (0..<3).reduce(0) { $0 + matrix[row * 3 + $1] * first.offset[$1] }
        }
        return AssColorTransform(matrix: m, offset: o)
    }

    private var inverted: AssColorTransform {
        let a = matrix
        let det = a[0] * (a[4] * a[8] - a[5] * a[7])
            - a[1] * (a[3] * a[8] - a[5] * a[6])
            + a[2] * (a[3] * a[7] - a[4] * a[6])
        let inv = [
            (a[4] * a[8] - a[5] * a[7]) / det, (a[2] * a[7] - a[1] * a[8]) / det, (a[1] * a[5] - a[2] * a[4]) / det,
            (a[5] * a[6] - a[3] * a[8]) / det, (a[0] * a[8] - a[2] * a[6]) / det, (a[2] * a[3] - a[0] * a[5]) / det,
            (a[3] * a[7] - a[4] * a[6]) / det, (a[1] * a[6] - a[0] * a[7]) / det, (a[0] * a[4] - a[1] * a[3]) / det
        ]
        let o = (0..<3).map { row in -(0..<3).reduce(0) { $0 + inv[row * 3 + $1] * offset[$1] } }
        return AssColorTransform(matrix: inv, offset: o)
    }

    /// A YCbCr matrix and its quantisation range, at 8 bits.
    private struct Encoding: Equatable {
        let kr: Double
        let kb: Double
        let isFullRange: Bool

        init?(assMatrix: Int32) {
            // ASS_YCbCrMatrix: DEFAULT, UNKNOWN, NONE, BT601_TV, BT601_PC, BT709_TV, BT709_PC,
            // SMPTE240M_TV, SMPTE240M_PC, FCC_TV, FCC_PC.
            switch assMatrix {
            case 0, 3: self.init(kr: 0.299, kb: 0.114, isFullRange: false)
            case 4: self.init(kr: 0.299, kb: 0.114, isFullRange: true)
            case 5: self.init(kr: 0.2126, kb: 0.0722, isFullRange: false)
            case 6: self.init(kr: 0.2126, kb: 0.0722, isFullRange: true)
            case 7: self.init(kr: 0.212, kb: 0.087, isFullRange: false)
            case 8: self.init(kr: 0.212, kb: 0.087, isFullRange: true)
            case 9: self.init(kr: 0.30, kb: 0.11, isFullRange: false)
            case 10: self.init(kr: 0.30, kb: 0.11, isFullRange: true)
            // UNKNOWN (unparseable) and NONE ("leave colours alone").
            default: return nil
            }
        }

        init?(video: VideoColorimetry) {
            switch video.matrix {
            case .bt601: self.init(kr: 0.299, kb: 0.114, isFullRange: video.isFullRange)
            case .bt709: self.init(kr: 0.2126, kb: 0.0722, isFullRange: video.isFullRange)
            case .smpte240m: self.init(kr: 0.212, kb: 0.087, isFullRange: video.isFullRange)
            case .fcc: self.init(kr: 0.30, kb: 0.11, isFullRange: video.isFullRange)
            case .bt2020NonConstantLuminance: self.init(kr: 0.2627, kb: 0.0593, isFullRange: video.isFullRange)
            case .rgb: return nil
            }
        }

        private init(kr: Double, kb: Double, isFullRange: Bool) {
            self.kr = kr
            self.kb = kb
            self.isFullRange = isFullRange
        }

        /// RGB to coded Y, Cb, Cr, each over 0...1 of the 8-bit code range.
        var rgbToCoded: AssColorTransform {
            let kg = 1 - kr - kb
            let cb = 2 * (1 - kb)
            let cr = 2 * (1 - kr)
            let ys: Double = isFullRange ? 1 : 219.0 / 255
            let cs: Double = isFullRange ? 1 : 224.0 / 255
            let yo: Double = isFullRange ? 0 : 16.0 / 255
            let co = 128.0 / 255
            return AssColorTransform(
                matrix: [
                    ys * kr, ys * kg, ys * kb,
                    cs * -kr / cb, cs * -kg / cb, cs * (1 - kb) / cb,
                    cs * (1 - kr) / cr, cs * -kg / cr, cs * -kb / cr
                ],
                offset: [yo, co, co]
            )
        }
    }
}
