import Combine
import Foundation
import SwiftLibass
import CombineSchedulers

public typealias LibrarySetup = @Sendable (_ library: OpaquePointer) -> Void
public typealias RendererSetup = @Sendable (_ library: OpaquePointer, _ renderer: OpaquePointer) -> Void

/// ASS/SSA subtitles renderer. Manages the current ASS track, 
/// current time offset and current visible frame (``ProcessedImage``).
public final class AssSubtitlesRenderer: Sendable {
    public enum FrameRenderResult: Equatable, Sendable {
        case loaded(ProcessedImage)
        case unchanged
        case none
    }

    /// The outcome of one render and the offset it was rendered at, so a host that renders ahead of the
    /// display can put each frame on screen at the moment it belongs to.
    public struct RenderedFrame: Equatable, Sendable {
        public let offset: TimeInterval
        /// `.unchanged` means the frame looks exactly like the previous render's.
        public let result: FrameRenderResult

        public init(offset: TimeInterval, result: FrameRenderResult) {
            self.offset = offset
            self.result = result
        }
    }

    private let workQueue: DispatchQueueType
    private let scheduler: AnySchedulerOf<DispatchQueue>
    private let wrapper: LibraryWrapperType.Type
    private let fontConfig: FontConfigType
    private let pipeline: ImagePipelineType
    private let logger: LoggerType
    private let contentsLoader: ContentsLoaderType
    private let librarySetup: LibrarySetup?
    private let rendererSetup: RendererSetup?

    nonisolated(unsafe) private var library: OpaquePointer?
    nonisolated(unsafe) private var renderer: OpaquePointer?
    nonisolated(unsafe) private var canvasSize: CGSize = .zero
    nonisolated(unsafe) private var canvasScale: CGFloat = 1.0
    nonisolated(unsafe) private var frameMargins: FrameMargins = .zero
    nonisolated(unsafe) private var usesFrameMargins = false
    /// Bumped on each margins change, so a burst of changes (such as a pinch) renders only the latest one.
    nonisolated(unsafe) private var marginsGeneration = 0
    nonisolated(unsafe) private var cancellables: Set<AnyCancellable> = []
    /// Owned by libass. Guarded by `trackLock` so a track is never freed while being rendered or read.
    nonisolated(unsafe) private(set) var currentTrack: UnsafeMutablePointer<ASS_Track>?
    private let trackLock = NSLock()
    /// Latest offset waiting for a render, so a render slower than the call rate never queues up.
    nonisolated(unsafe) private var pendingOffset: TimeInterval?
    private let pendingOffsetLock = NSLock()
    nonisolated(unsafe) private(set) var currentOffset: TimeInterval = 0
    nonisolated(unsafe) private(set) var currentFrame = CurrentValueSubject<ProcessedImage?, Never>(nil)
    nonisolated(unsafe) private let renderedFrames = PassthroughSubject<RenderedFrame, Never>()
    /// The video's colorimetry, set by the host. Read and written on the work queue.
    nonisolated(unsafe) private var videoColorimetry: VideoColorimetry?
    /// Script colours to displayed colours for the current track and video. Work queue only.
    nonisolated(unsafe) private var colorTransform = AssColorTransform.identity

    /// - Parameters:
    ///   - fontConfig: Fonts configuration. Defines where the fonts and fonts cache is located, 
    ///   fallbacks for missing fonts and the default ``FontProvider`` to use.
    ///   - pipeline: Image pipeline to use for precessing `ASS_Image` into ``ProcessedImage``.
    ///   - logOutput: Log output. 
    ///   Defaults to logging to console with `.default` level in DEBUG and `.fatal` in RELEASE.
    ///   - librarySetup: Custom actions to run when initializing the `ASS_Library`.
    ///   - rendererSetup: Custom actions to run when initializing the `ASS_Renderer`.
    public convenience init(
        fontConfig: FontConfig,
        pipeline: ImagePipelineType = BlendImagePipeline(),
        logOutput: LogOutput? = nil,
        librarySetup: LibrarySetup? = nil,
        rendererSetup: RendererSetup? = nil
    ) {
        self.init(
            workQueue: DispatchQueue(label: "com.swift-ass-renderer.work", qos: .userInteractive),
            scheduler: .main,
            wrapper: LibraryWrapper.self,
            fontConfig: fontConfig,
            pipeline: pipeline,
            logger: Logger(output: logOutput),
            contentsLoader: ContentsLoader(),
            librarySetup: librarySetup,
            rendererSetup: rendererSetup
        )
    }

    init(
        workQueue: DispatchQueueType,
        scheduler: AnySchedulerOf<DispatchQueue>,
        wrapper: LibraryWrapperType.Type,
        fontConfig: FontConfigType,
        pipeline: ImagePipelineType,
        logger: LoggerType,
        contentsLoader: ContentsLoaderType,
        librarySetup: LibrarySetup?,
        rendererSetup: RendererSetup?
    ) {
        self.workQueue = workQueue
        self.scheduler = scheduler
        self.wrapper = wrapper
        self.fontConfig = fontConfig
        self.pipeline = pipeline
        self.logger = logger
        self.contentsLoader = contentsLoader
        self.librarySetup = librarySetup
        self.rendererSetup = rendererSetup
        configure()
    }

    deinit {
        replaceTrack(with: nil)
        renderer.flatMap(wrapper.rendererDone)
        library.flatMap(wrapper.libraryDone)
    }

    /// Parse and load ASS/SSA subtitle track in memory.
    ///
    /// - Parameters:
    ///   - content: Raw ASS/SSA subtitle contents.
    ///
    /// Always call this method before starting to update the time offset.
    public func loadTrack(content: String) {
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            guard let library else {
                return logger.log(message: LogMessage(
                    message: "Track cannot be loaded since library has not been initialized",
                    level: .verbose
                ))
            }
            replaceTrack(with: wrapper.readTrack(library, content: content))
        }
    }

    /// Start a track that receives its events as they arrive, the way a Matroska stream carries them.
    ///
    /// - Parameters:
    ///   - header: The script's header (`[Script Info]`, styles and, optionally, the `[Events]` format line),
    ///   such as a Matroska track's CodecPrivate.
    ///
    /// Add events with ``appendEvents(_:)``. Each event keeps its own `ReadOrder`, which decides how
    /// events on the same layer stack. Events are not de-duplicated: append each one once.
    public func loadTrack(header: String) {
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            guard let library else {
                return logger.log(message: LogMessage(
                    message: "Track cannot be loaded since library has not been initialized",
                    level: .verbose
                ))
            }
            replaceTrack(with: wrapper.newTrack(library, header: header))
        }
    }

    /// Add events to a track started with ``loadTrack(header:)``.
    ///
    /// Nothing is rendered by this call; the next render includes the new events.
    public func appendEvents(_ events: [AssEvent]) {
        guard !events.isEmpty else { return }
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            withLock(trackLock) {
                guard let currentTrack else { return }
                for event in events {
                    wrapper.processChunk(currentTrack, event: event)
                }
            }
        }
    }

    /// Load a new track from provided content and render it at the current time offset.
    ///
    /// - Parameters:
    ///   - content: Raw ASS/SSA subtitle contents.
    ///
    /// The previous track stays visible until the new one is parsed, so no empty frame is published in between.
    public func reloadTrack(content: String) {
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            guard let library else {
                return logger.log(message: LogMessage(
                    message: "Track cannot be reloaded since library has not been initialized",
                    level: .verbose
                ))
            }
            replaceTrack(with: wrapper.readTrack(library, content: content))
            let offset = currentOffset
            publish(renderFrame(at: offset) ?? .none, at: offset)
        }
    }

    /// Parse and load ASS/SSA subtitle track in memory.
    ///
    /// - Parameters:
    ///   - url: File or remote URL to subtitle contents .
    ///
    /// Always call this method before starting to update the time offset.
    public func loadTrack(url: URL) {
        freeTrack()
        loadContents(from: url) { [weak self] contents in
            guard let self else { return }
            loadTrack(content: contents)
        }
    }

    /// Load a new track from provided URL and restore the time offset to last known position.
    ///
    /// - Parameters:
    ///   - url: File or remote URL to subtitle contents .
    public func reloadTrack(url: URL) {
        loadContents(from: url) { [weak self] contents in
            self?.reloadTrack(content: contents)
        }
    }

    /// Removes current track and resets the time offset and current visible frame.
    public func freeTrack() {
        currentOffset = 0
        workQueue.executeAsync { [weak self] in
            self?.replaceTrack(with: nil)
            self?.publish(.none, at: 0)
        }
    }

    /// Set subtitles canvas size and scale.
    ///
    /// - Parameters:
    ///   - size: Canvas size. Should match the video canvas for proper subtitle positioning.
    ///   - scale: Screen scale. Bigger scale results in sharper images, but lower performance.
    ///
    /// Always call this method before starting to update the time offset.
    /// When using the renderer with ``AssSubtitles`` / ``AssSubtitlesView``, you don't have to call this method.
    public func setCanvasSize(_ size: CGSize, scale: CGFloat) {
        if canvasSize == size && canvasScale == scale { return }
        canvasSize = size
        canvasScale = scale
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            guard let renderer else {
                return logger.log(message: LogMessage(
                    message: "Can't set canvas size since renderer has not been initialized",
                    level: .verbose
                ))
            }
            wrapper.setRendererSize(renderer, size: size * scale)
            wrapper.setMargins(renderer, margins: frameMargins * scale)
            reloadFrame()
        }
    }

    /// Set where the video picture sits relative to the canvas.
    ///
    /// - Parameters:
    ///   - margins: Distance, in points, from the picture to each canvas edge. Negative values crop the picture.
    ///   - useMargins: Whether regular events are laid out against the canvas instead of the picture.
    ///   With negative margins, this keeps dialogue on screen at its unzoomed size while positioned events
    ///   follow the picture. With positive margins, it lets dialogue move into the empty bands.
    public func setFrameMargins(_ margins: FrameMargins, useMargins: Bool) {
        if frameMargins == margins && usesFrameMargins == useMargins { return }
        frameMargins = margins
        usesFrameMargins = useMargins
        marginsGeneration += 1
        let generation = marginsGeneration
        workQueue.executeAsync { [weak self] in
            guard let self, generation == marginsGeneration else { return }
            guard let renderer else {
                return logger.log(message: LogMessage(
                    message: "Can't set frame margins since renderer has not been initialized",
                    level: .verbose
                ))
            }
            wrapper.setMargins(renderer, margins: margins * canvasScale)
            wrapper.setUseMargins(renderer, use: useMargins)
            reloadFrame()
        }
    }

    /// Set the video's storage size: its coded width and height in pixels, before any pixel aspect ratio.
    ///
    /// With the picture's displayed rect (the canvas less ``setFrameMargins(_:useMargins:)``), this gives
    /// libass the pixel aspect ratio, so anamorphic video keeps round glyphs and correctly scaled blur.
    public func setStorageSize(_ size: CGSize) {
        workQueue.executeAsync { [weak self] in
            guard let self, let renderer else { return }
            wrapper.setStorageSize(renderer, size: size)
            reloadFrame()
        }
    }

    /// Set how the video's YCbCr becomes RGB on screen, so script colours are shown as their author saw
    /// them against the video (see ``AssColorTransform``). nil leaves colours as written.
    public func setVideoColorimetry(_ colorimetry: VideoColorimetry?) {
        workQueue.executeAsync { [weak self] in
            guard let self, videoColorimetry != colorimetry else { return }
            videoColorimetry = colorimetry
            updateColorTransform()
            reloadFrame()
        }
    }

    /// Set current visible subtitle offset.
    ///
    /// - Parameters:
    ///   - offset: Time interval (in seconds) from where to render the current visible subtitle.
    ///
    /// This method should be called periodically to update the current visible subtitle.
    /// Calls made while a render is pending are coalesced: only the latest offset is rendered.
    public func setTimeOffset(_ offset: TimeInterval) {
        currentOffset = offset
        let isRenderPending = withLock(pendingOffsetLock) {
            defer { pendingOffset = offset }
            return pendingOffset != nil
        }
        guard !isRenderPending else { return }
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            let offset = withLock(pendingOffsetLock) {
                defer { pendingOffset = nil }
                return pendingOffset
            }
            guard let offset else { return }
            renderCurrentTrack(at: offset)
        }
    }

    /// Publisher of every render's outcome, tagged with the offset it was rendered at.
    ///
    /// - Returns: A Combine publisher of ``RenderedFrame``, one per render, in render order.
    ///
    /// When using the renderer with ``AssSubtitles`` / ``AssSubtitlesView``,
    /// you don't have to subscribe to this publisher and render the images.
    public func framesPublisher() -> AnyPublisher<RenderedFrame, Never> {
        renderedFrames
            .receive(on: scheduler)
            .eraseToAnyPublisher()
    }

    /// Forces the current visible subtitle to be reloaded and redrawn.
    ///
    /// When using the renderer with ``AssSubtitles`` / ``AssSubtitlesView``, you don't have to call this method.
    public func reloadFrame() {
        loadFrame(offset: currentOffset)
    }

    /// Load frame (if any) at the given offset.
    ///
    /// - Parameters:
    ///   - offset: Time interval (in seconds) where to load the subtitle frame.
    ///   - completion: Completion handler.
    public func loadFrame(offset: TimeInterval, completion: @escaping @Sendable (ProcessedImage?) -> Void = { _ in }) {
        workQueue.executeAsync { [weak self] in
            defer { completion(self?.currentFrame.value) }
            self?.renderCurrentTrack(at: offset)
        }
    }

    /// Load frame synchronously at the given offset.
    ///
    /// - Parameters:
    ///   - offset: Time interval (in seconds) where to load the subtitle frame.
    ///
    /// - Returns: ``FrameRenderResult`` relative to last renderer frame.
    public func loadFrameSync(offset: TimeInterval) -> FrameRenderResult {
        guard let result = renderFrame(at: offset) else { return .none }
        publish(result, at: offset)

        return result
    }

    /// Renders the frame at `offset` on the calling thread and returns it whole: the frame libass draws there, or
    /// nil when nothing shows. Where libass reports the frame unchanged since its last render, whoever asked for that
    /// one, the image of that render is returned, so a caller never has to know what came before.
    public func image(at offset: TimeInterval) -> ProcessedImage? {
        guard let result = renderFrame(at: offset) else { return nil }
        switch result {
        case .unchanged: return currentFrame.value
        case .none:
            currentFrame.value = nil
            return nil
        case .loaded(let image):
            currentFrame.value = image
            return image
        }
    }

    /// Load subtitle dialogues at the given offset.
    ///
    /// - Parameters:
    ///   - offset: Time interval (in seconds) where to load the dialogues from.
    ///
    /// - Returns: List of dialogue strings that are being presented at the given offset.
    public func dialogues(at offset: TimeInterval) -> [String] {
        withLock(trackLock) {
            guard let track = currentTrack?.pointee, let events = track.events else { return [] }
            return (0..<Int(track.n_events)).compactMap { index in
                let event = events.advanced(by: index).pointee
                guard event.range.contains(offset), let text = event.Text else { return nil }
                return String(cString: text)
            }
        }
    }
}

private extension AssSubtitlesRenderer {
    func replaceTrack(with track: UnsafeMutablePointer<ASS_Track>?) {
        withLock(trackLock) {
            let previousTrack = currentTrack
            currentTrack = track
            previousTrack.map(wrapper.freeTrack)
        }
        updateColorTransform()
    }

    /// Work queue only.
    func updateColorTransform() {
        let scriptMatrix = withLock(trackLock) { currentTrack.map { wrapper.colorMatrix(of: $0) } }
        colorTransform = scriptMatrix.map { AssColorTransform(scriptMatrix: $0, video: videoColorimetry) }
            ?? .identity
    }

    func renderCurrentTrack(at offset: TimeInterval) {
        guard let result = renderFrame(at: offset) else { return }
        publish(result, at: offset)
    }

    /// Nil without a track. The frame is published by the caller, outside `trackLock`,
    /// so a subscriber may read dialogues.
    func renderFrame(at offset: TimeInterval) -> FrameRenderResult? {
        withLock(trackLock) {
            guard let currentTrack else { return nil }
            return frame(at: offset, in: &currentTrack.pointee)
        }
    }

    private func publish(_ result: FrameRenderResult, at offset: TimeInterval) {
        switch result {
        case .unchanged: break
        case .none: currentFrame.value = nil
        case .loaded(let image): currentFrame.value = image
        }
        renderedFrames.send(RenderedFrame(offset: offset, result: result))
    }

    func frame(at offset: TimeInterval, in track: inout ASS_Track) -> FrameRenderResult {
        guard let renderer else {
            logger.log(message: LogMessage(
                message: "Can't render frame since renderer has not been initialized",
                level: .verbose
            ))
            return .none
        }
        let result = wrapper.renderImage(renderer, track: &track, at: offset)
        guard result.changed else { return .unchanged }
        guard let image = result.image,
              let processed = pipeline.process(images: linkedImages(from: image), colorTransform: colorTransform)
        else {
            return .none
        }
        // Not rounded to whole points: a tile drawn at a fractional point origin still lands on whole
        // pixels, where rounding would resample it.
        let scale = canvasScale
        return .loaded(ProcessedImage(tiles: processed.tiles.map { $0.moved(to: $0.rect / scale) }))
    }

    func loadContents(from url: URL, completion: @escaping (String) -> Void) {
        contentsLoader
            .loadContents(from: url)
            .sink { [weak self] completion in
                guard let self, case .failure(let error) = completion else { return }
                logger.log(
                    message: LogMessage(message: "Could not load subtitle contents: \(error)",
                    level: .fatal
                ))
            } receiveValue: { contents in
                guard let contents else { return }
                completion(contents)
            }.store(in: &cancellables)
    }
}

private extension AssSubtitlesRenderer {
    func configure() {
        workQueue.executeAsync { [weak self] in
            guard let self else { return }
            configureLibrary()
            configureFonts()
        }
    }

    func configureLibrary() {
        library = wrapper.libraryInit()
        guard let library else {
            return logger.log(message: LogMessage(
                message: "Library could not be initialized",
                level: .fatal
            ))
        }
        logger.configureLibrary(wrapper, library: library)
        renderer = wrapper.rendererInit(library)
        guard let renderer else {
            return logger.log(message: LogMessage(
                message: "Renderer could not be initialized",
                level: .fatal
            ))
        }
        librarySetup?(library)
        rendererSetup?(library, renderer)
    }

    func configureFonts() {
        do {
            guard let library, let renderer else {
                return logger.log(message: LogMessage(
                    message: "Library and renderer have not been initialized before setting fonts",
                    level: .fatal
                ))
            }
            try fontConfig.configure(library: library, renderer: renderer)
        } catch {
            logger.log(message: LogMessage(message: "Failed setting fonts - \(error)", level: .fatal))
        }
    }
}

private extension ASS_Event {
    var range: ClosedRange<TimeInterval> {
        let startSec = TimeInterval(Start) / 1000
        let durationSec = TimeInterval(Duration) / 1000
        let endSec = startSec + durationSec

        return startSec...endSec
    }
}
