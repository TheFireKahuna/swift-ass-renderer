import Foundation

/// One subtitle event as a Matroska block carries it.
public struct AssEvent: Equatable, Sendable {
    /// `ReadOrder, Layer, Style, Name, MarginL, MarginR, MarginV, Effect, Text`.
    public let line: String
    /// Start, in seconds on the timeline the renderer's offsets use.
    public let start: TimeInterval
    /// Duration in seconds.
    public let duration: TimeInterval

    public init(line: String, start: TimeInterval, duration: TimeInterval) {
        self.line = line
        self.start = start
        self.duration = duration
    }
}
